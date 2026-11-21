import Foundation
import SwiftUI

enum Fmt {
    private static let cs = Locale(identifier: "cs_CZ")

    /// "3,42 m"
    static func m(_ v: Double, digits: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).locale(cs)) + " m"
    }
    /// "342 cm"
    static func cm(_ v: Double) -> String { "\(Int((v * 100).rounded())) cm" }
    static func m2(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1)).locale(cs)) + " m²" }
    static func m3(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1)).locale(cs)) + " m³" }
    /// Short label for drawing on the plan: "342" (cm), the unit is in the legend.
    static func short(_ v: Double) -> String { "\(Int((v * 100).rounded()))" }
    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month().year().hour().minute().locale(cs)) }
}

enum Names {
    static func opening(_ o: PlanOpening) -> String {
        let kind: String
        switch o.kind {
        case .door: kind = o.slides ? "Posuvné dveře" : "Dveře"
        case .window: kind = "Okno"
        case .opening: kind = "Průchod"
        case .wardrobe: kind = "Vestavěná skříň"
        }
        if let l = o.label, !l.isEmpty { return "\(kind) – \(l)" }
        return kind
    }

    static func category(_ c: String) -> String {
        switch c {
        case "storage": return "Úložný prostor"
        case "refrigerator": return "Lednice"
        case "stove": return "Sporák"
        case "bed": return "Postel"
        case "sink": return "Umyvadlo / dřez"
        case "washerDryer": return "Pračka / sušička"
        case "toilet": return "WC"
        case "bathtub": return "Vana"
        case "oven": return "Trouba"
        case "dishwasher": return "Myčka"
        case "table": return "Stůl"
        case "sofa": return "Gauč"
        case "chair": return "Židle / křeslo"
        case "fireplace": return "Krb"
        case "television": return "Televize"
        case "stairs": return "Schody"
        case "rug": return "Koberec"
        case "plant": return "Rostlina"
        case "lamp": return "Lampa"
        case "desk": return "Psací stůl"
        default: return c
        }
    }

    static func room(_ r: String?) -> String? {
        switch r {
        case "bedroom": return "Ložnice"
        case "bathroom": return "Koupelna"
        case "kitchen": return "Kuchyně"
        case "livingRoom": return "Obývací pokoj"
        case "diningRoom": return "Jídelna"
        case nil, "unidentified": return nil
        default: return r
        }
    }

    static func color(_ c: String) -> Color {
        switch c {
        case "bed": return .indigo
        case "sofa", "chair": return .orange
        case "table", "desk": return .brown
        case "storage": return .teal
        case "television": return .purple
        case "rug": return .pink
        case "plant": return .green
        case "refrigerator", "stove", "oven", "dishwasher", "sink", "washerDryer": return .cyan
        case "toilet", "bathtub": return .blue
        default: return .gray
        }
    }
}

/// Arbitrary JSON, used to keep the raw Claude API messages (thinking blocks included) for replay.
enum JSONValue: Codable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    init(any: Any) {
        switch any {
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
        case let n as NSNumber: self = .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }
}
