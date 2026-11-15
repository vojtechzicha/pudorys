import Foundation
import UIKit

/// Calls the Claude Messages API over plain HTTPS (there is no official Swift SDK).
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    static var apiKey: String? {
        #if DEBUG
        // Simulator tests: SIMCTL_CHILD_ANTHROPIC_API_KEY=… xcrun simctl launch … (never stored).
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        #endif
        return Keychain.get("anthropic_api_key")
    }

    struct Reply {
        var message: String
        var layout: [LayoutItem]?
        var suggestions: [String]
        /// The assistant's full `content` array, thinking blocks included, to replay next turn.
        var rawContent: JSONValue
    }

    enum Failure: LocalizedError {
        case noKey, http(Int, String), refusal(String), truncated, badOutput(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Chybí API klíč Anthropic (Nastavení)."
            case .http(let c, let m): return "Chyba API \(c): \(m)"
            case .refusal(let why): return "Claude požadavek odmítl\(why.isEmpty ? "" : ": \(why)")."
            case .truncated: return "Odpověď byla příliš dlouhá a uřízla se. Zkus požadavek zjednodušit."
            case .badOutput(let s): return "Neplatná odpověď: \(s)"
            }
        }
    }

    static let categories = ["bed", "sofa", "chair", "table", "desk", "storage", "television", "rug", "plant",
                             "lamp", "refrigerator", "stove", "oven", "dishwasher", "sink", "washerDryer",
                             "toilet", "bathtub", "other"]

    static let schema: [String: Any] = {
        let num: [String: Any] = ["type": "number"]
        let str: [String: Any] = ["type": "string"]
        let item: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["id", "name", "category", "x", "y", "width", "depth", "height", "rotation", "note"],
            "properties": [
                "id": str, "name": str, "category": ["type": "string", "enum": categories],
                "x": num, "y": num, "width": num, "depth": num, "height": num, "rotation": num, "note": str,
            ],
        ]
        return [
            "type": "object", "additionalProperties": false,
            "required": ["message", "layout_changed", "layout", "suggestions"],
            "properties": [
                "message": str,
                "layout_changed": ["type": "boolean"],
                "layout": ["type": "array", "items": item],
                "suggestions": ["type": "array", "items": str],
            ],
        ]
    }()

    static let system = """
    You are an interior and space planner working inside an iPhone app that scans rooms with LiDAR.
    You get the measured floor plan as JSON, a rendered image of the plan, and photos taken during the scan.
    Plan coordinates are metres, x to the right, y downwards in the plan image (top view). A furniture
    piece is a rectangle: (x, y) is its centre, `width` runs along x and `depth` along y when rotation is 0,
    and its front (where you sit, open doors or drawers, or watch from) faces +y. `rotation` is in degrees,
    clockwise in the plan image: 90 makes the front face -x, 180 faces -y, 270 faces +x.

    Plan with real-world ergonomics: keep door clearance zones free, leave 60 cm or more for secondary
    passages and 80-90 cm for main walkways, 60-70 cm beside beds you get in from, about 90 cm in front of
    wardrobes and drawers, do not put tall furniture in front of windows, and put desks where daylight comes
    from the side. Everything must lie inside the room outline. List furniture that stands on the floor;
    mention things that stand on other furniture (a desk lamp, a TV on its stand) in that piece's `note`. Use realistic sizes of furniture sold in
    Europe. Look at the photos for radiators, sockets, sloped ceilings, flooring and style, and mention
    what you rely on. If something you need cannot be seen in the data, say so and make a sensible guess.

    Reply in the user's language (Czech unless they write otherwise). Keep `message` short: what you
    changed and why, a few sentences or a short list. When you propose or change a layout, set
    `layout_changed` to true and return the complete layout (all pieces, keeping ids of unchanged pieces);
    otherwise set it false and return an empty array. Offer two to four short follow-up ideas in
    `suggestions`, written as requests the user could send next.
    """

    /// First user message: plan, plan image, photos and the request.
    static func firstMessage(rec: ScanRecord, planImage: Data?, photos: [Data], request: String) -> JSONValue {
        var blocks: [[String: Any]] = [["type": "text", "text": "Půdorys (JSON):\n" + PlanBrief.json(PlanBrief.object(rec))]]
        if let planImage {
            blocks.append(["type": "text", "text": "Vykreslený půdorys (rozměry stěn v cm):"])
            blocks.append(image(planImage, type: "image/png"))
        }
        for (i, p) in photos.enumerated() {
            blocks.append(["type": "text", "text": "Fotka \(i + 1):"])
            blocks.append(image(p, type: "image/jpeg"))
        }
        blocks.append(["type": "text", "text": turnText(rec, request)])
        return JSONValue(any: ["role": "user", "content": blocks])
    }

    static func nextMessage(rec: ScanRecord, request: String) -> JSONValue {
        JSONValue(any: ["role": "user", "content": [["type": "text", "text": turnText(rec, request)]]])
    }

    private static func turnText(_ rec: ScanRecord, _ request: String) -> String {
        "Aktuální rozvržení v aplikaci (uživatel ho mohl ručně upravit):\n"
            + PlanBrief.json(PlanBrief.layoutObject(rec.layout)) + "\n\nPožadavek: " + request
    }

    private static func image(_ data: Data, type: String) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": type, "data": data.base64EncodedString()]]
    }

    static func send(messages: [JSONValue]) async throws -> Reply {
        do {
            return try await send(messages: messages, fallbacks: true)
        } catch Failure.http(400, let msg) where msg.lowercased().contains("fallback") {
            // Account without the server-side fallback beta: plain request instead.
            return try await send(messages: messages, fallbacks: false)
        }
    }

    private static func send(messages: [JSONValue], fallbacks: Bool) async throws -> Reply {
        guard let key = apiKey, !key.isEmpty else { throw Failure.noKey }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "cache_control": ["type": "ephemeral"],
            "output_config": ["effort": "high", "format": ["type": "json_schema", "schema": schema]],
            "messages": messages.map(\.any),
        ]
        // On a safety-classifier refusal the API re-runs the request on a fallback model.
        if fallbacks { body["fallbacks"] = "default" }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if fallbacks { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw Failure.http(status, msg)
        }
        switch json["stop_reason"] as? String {
        case "refusal":
            let why = (json["stop_details"] as? [String: Any])?["explanation"] as? String ?? ""
            throw Failure.refusal(why)
        case "max_tokens": throw Failure.truncated
        default: break
        }
        let content = json["content"] as? [[String: Any]] ?? []
        guard let text = content.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let out = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw Failure.badOutput("chybí JSON")
        }
        var layout: [LayoutItem]?
        if out["layout_changed"] as? Bool == true, let arr = out["layout"] {
            let d = try JSONSerialization.data(withJSONObject: arr)
            layout = try? JSONDecoder().decode([LayoutItem].self, from: d)
            if layout == nil { throw Failure.badOutput("rozvržení nejde načíst") }
        }
        return Reply(message: out["message"] as? String ?? "", layout: layout,
                     suggestions: out["suggestions"] as? [String] ?? [],
                     rawContent: JSONValue(any: ["role": "assistant", "content": content]))
    }

    /// Downscales a photo for upload (long side 1024 px).
    static func shrink(_ img: UIImage, maxSide: CGFloat = 1024) -> Data? {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).jpegData(withCompressionQuality: 0.7) { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
