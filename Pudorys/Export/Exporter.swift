import SwiftUI
import SceneKit

/// A printable sheet: title, key numbers and the plan.
struct PlanSheet: View {
    var record: ScanRecord
    var size: CGSize
    var showLayout = true

    var body: some View {
        let p = record.plan
        VStack(alignment: .leading, spacing: 6) {
            Text(record.name).font(.system(size: 22, weight: .bold))
            Text("Plocha \(Fmt.m2(p.area)) · obvod \(Fmt.m(p.perimeter, digits: 1)) · světlá výška \(Fmt.m(p.ceilingHeight)) · \(Fmt.date(record.createdAt))")
                .font(.system(size: 12)).foregroundColor(.gray)
            Canvas { ctx, sz in
                var layers = PlanLayers()
                layers.layout = showLayout
                layers.grid = false
                PlanDrawing(plan: p, layout: record.layout, photos: record.photos, layers: layers,
                            issues: LayoutCheck.summary(record.layout, plan: p))
                    .draw(&ctx, PlanMapper(size: sz, bounds: p.bounds, padding: 0.5))
            }
        }
        .padding(24)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
enum Exporter {
    /// Builds the export folder and zips it. Returns the zip and the plan image (for the planner).
    static func export(_ rec: ScanRecord, store: ScanStore) throws -> URL {
        let fm = FileManager.default
        let safe = rec.name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .map { $0.isASCII && ($0.isLetter || $0.isNumber || "-_ ".contains($0)) ? String($0) : "-" }.joined()
        let base = fm.temporaryDirectory.appendingPathComponent("export-\(rec.id)", isDirectory: true)
        try? fm.removeItem(at: base)
        let dir = base.appendingPathComponent(safe, isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("photos"), withIntermediateDirectories: true)

        try Data(PlanBrief.json(PlanBrief.object(rec)).utf8).write(to: dir.appendingPathComponent("plan.json"))
        try Data(PlanBrief.json(PlanBrief.layoutObject(rec.layout)).utf8).write(to: dir.appendingPathComponent("layout.json"))
        try Data(PlanBrief.prompt(rec, request: "").utf8).write(to: dir.appendingPathComponent("prompt-pro-clauda.txt"))
        try svg(rec).data(using: .utf8)!.write(to: dir.appendingPathComponent("pudorys.svg"))
        if let png = planPNG(rec) { try png.write(to: dir.appendingPathComponent("pudorys.png")) }
        try pdf(rec, to: dir.appendingPathComponent("pudorys.pdf"))

        for (src, name) in [(store.modelURL(rec.id), "model-sken.usdz"), (store.roomURL(rec.id), "roomplan-captured-room.json")]
            where fm.fileExists(atPath: src.path) {
            try fm.copyItem(at: src, to: dir.appendingPathComponent(name))
        }
        for p in rec.photos where fm.fileExists(atPath: store.photoURL(rec, p).path) {
            try fm.copyItem(at: store.photoURL(rec, p), to: dir.appendingPathComponent("photos").appendingPathComponent(p.fileName))
        }
        let scene = RoomScene.make(plan: rec.plan, layout: rec.layout, showDetected: rec.layout.isEmpty,
                                   showLayout: true, lowWalls: false)
        _ = scene.write(to: dir.appendingPathComponent("model-s-rozvrzenim.usdz"), options: nil, delegate: nil, progressHandler: nil)

        return try zip(dir, to: base.appendingPathComponent("\(safe).zip"))
    }

    static func planPNG(_ rec: ScanRecord, width: CGFloat = 1200, showLayout: Bool = true) -> Data? {
        let b = rec.plan.bounds
        let h = min(2400, max(600, width * (b.height + 1) / max(b.width + 1, 0.1) + 80))
        let r = ImageRenderer(content: PlanSheet(record: rec, size: CGSize(width: width, height: h), showLayout: showLayout))
        r.scale = 1
        return r.uiImage?.pngData()
    }

    static func pdf(_ rec: ScanRecord, to url: URL) throws {
        let r = ImageRenderer(content: PlanSheet(record: rec, size: CGSize(width: 842, height: 595)))  // A4 landscape
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
    }

    static func svg(_ rec: ScanRecord) -> String {
        let p = rec.plan, s = 100.0, pad = 80.0
        let b = p.bounds
        func X(_ v: Double) -> String { String(format: "%.1f", (v - b.minX) * s + pad) }
        func Y(_ v: Double) -> String { String(format: "%.1f", (v - b.minY) * s + pad) }
        let w = b.width * s + 2 * pad, h = b.height * s + 2 * pad
        var o = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(w))" height="\(Int(h))" viewBox="0 0 \(Int(w)) \(Int(h))" font-family="Helvetica" font-size="12">
        <rect width="100%" height="100%" fill="white"/>
        <!-- 1 m = 100 units; dimensions in cm -->

        """
        if p.outline.count > 2 {
            o += "<polygon fill=\"#efe6d6\" points=\"\(p.outline.map { "\(X($0.x)),\(Y($0.y))" }.joined(separator: " "))\"/>\n"
        }
        for x in p.objects {
            o += "<polygon fill=\"none\" stroke=\"#888\" stroke-dasharray=\"4 3\" points=\"\(x.corners().map { "\(X($0.x)),\(Y($0.y))" }.joined(separator: " "))\"/>\n"
        }
        for i in rec.layout {
            o += "<polygon fill=\"#4a7bd955\" stroke=\"#4a7bd9\" points=\"\(i.corners().map { "\(X($0.x)),\(Y($0.y))" }.joined(separator: " "))\"/>\n"
            o += "<text x=\"\(X(i.x))\" y=\"\(Y(i.y))\" text-anchor=\"middle\" font-size=\"11\">\(esc(i.name))</text>\n"
        }
        for wl in p.walls {
            o += "<line x1=\"\(X(wl.a.x))\" y1=\"\(Y(wl.a.y))\" x2=\"\(X(wl.b.x))\" y2=\"\(Y(wl.b.y))\" stroke=\"#222\" stroke-width=\"12\" stroke-linecap=\"square\"/>\n"
        }
        for op in p.openings {
            let col = op.kind == .window ? "#6aa8ff" : op.kind == .door ? "#a0522d" : "white"
            o += "<line x1=\"\(X(op.a.x))\" y1=\"\(Y(op.a.y))\" x2=\"\(X(op.b.x))\" y2=\"\(Y(op.b.y))\" stroke=\"white\" stroke-width=\"13\"/>\n"
            o += "<line x1=\"\(X(op.a.x))\" y1=\"\(Y(op.a.y))\" x2=\"\(X(op.b.x))\" y2=\"\(Y(op.b.y))\" stroke=\"\(col)\" stroke-width=\"4\"/>\n"
        }
        let c = Geometry.centroid(p.outline)
        for wl in p.walls where wl.length > 0.25 {
            let d = (wl.b - wl.a).normalized
            var n = P2(x: -d.y, y: d.x)
            if (c - wl.mid).dot(n) > 0 { n = n * -1 }
            let m = wl.mid + n * 0.25
            var ang = atan2(d.y, d.x) * 180 / .pi
            if ang > 90 { ang -= 180 } else if ang < -90 { ang += 180 }
            o += "<text x=\"\(X(m.x))\" y=\"\(Y(m.y))\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-weight=\"bold\" transform=\"rotate(\(String(format: "%.1f", ang)) \(X(m.x)) \(Y(m.y)))\">\(Fmt.short(wl.length))</text>\n"
        }
        o += "<text x=\"\(Int(pad))\" y=\"\(Int(h - 12))\">\(esc(rec.name)) · \(Fmt.m2(p.area)) · rozměry v cm</text>\n</svg>\n"
        return o
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Zips a folder using the system's built-in "upload as zip" coordination.
    private static func zip(_ dir: URL, to dest: URL) throws -> URL {
        var err: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &err) { tmp in
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: tmp, to: dest)
            } catch { thrown = error }
        }
        if let e = err ?? thrown { throw e }
        return dest
    }
}
