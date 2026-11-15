import Foundation

/// A furniture piece in a planned layout. This is also the exact JSON shape Claude returns
/// (in the app or via Claude Code, see docs/layout-format.md).
struct LayoutItem: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: String
    /// Centre of the piece on the plan, metres.
    var x: Double
    var y: Double
    var width: Double
    var depth: Double
    var height: Double
    /// Degrees, clockwise on the plan. 0 means `width` runs along x and the front faces +y (down).
    var rotation: Double
    var note: String?

    var center: P2 { get { P2(x: x, y: y) } set { x = newValue.x; y = newValue.y } }

    func corners() -> [P2] {
        PlanObject(id: id, category: category, center: center, width: width, depth: depth,
                   height: height, rotation: rotation).corners()
    }
}

struct LayoutIssue: Hashable {
    enum Kind { case outside, overlap, blocksDoor }
    var kind: Kind
    var text: String
}

enum LayoutCheck {
    /// Square in front of each door that should stay free for the door leaf and for walking through.
    static func doorZones(_ plan: PlanModel) -> [(PlanOpening, [P2])] {
        let c = Geometry.centroid(plan.outline)
        return plan.openings.filter { $0.kind == .door }.map { d in
            var n = P2(x: -d.direction.y, y: d.direction.x)
            if (c - d.center).dot(n) < 0 { n = n * -1 }
            let depth = min(max(d.width, 0.7), 1.0)
            return (d, [d.a, d.b, d.b + n * depth, d.a + n * depth])
        }
    }

    static func issues(for item: LayoutItem, in layout: [LayoutItem], plan: PlanModel) -> [LayoutIssue] {
        var out: [LayoutIssue] = []
        let corners = item.corners()
        let inset = corners.map { $0 + (item.center - $0).normalized * 0.03 }
        if plan.outline.count > 2, !inset.allSatisfy({ Geometry.contains(plan.outline, $0) }) {
            out.append(LayoutIssue(kind: .outside, text: "zasahuje mimo místnost"))
        }
        for other in layout where other.id != item.id && !mayOverlap(item, other) && Geometry.overlaps(corners, other.corners()) {
            out.append(LayoutIssue(kind: .overlap, text: "překrývá se s: \(other.name)"))
        }
        for (_, zone) in doorZones(plan) where !isFlat(item) && Geometry.overlaps(corners, zone) {
            out.append(LayoutIssue(kind: .blocksDoor, text: "blokuje dveře"))
        }
        return out
    }

    /// Rugs lie under furniture, chairs tuck under tables, lamps stand on desks.
    static func isFlat(_ i: LayoutItem) -> Bool { i.category == "rug" || i.height < 0.05 }
    static func mayOverlap(_ a: LayoutItem, _ b: LayoutItem) -> Bool {
        if isFlat(a) || isFlat(b) { return true }
        let pair = Set([a.category, b.category])
        let surfaces: Set = ["table", "desk", "storage"]
        if pair.contains("chair") && (pair.contains("table") || pair.contains("desk")) { return true }
        return pair.contains("lamp") && !pair.isDisjoint(with: surfaces)   // a lamp standing on a desk
    }

    static func summary(_ layout: [LayoutItem], plan: PlanModel) -> [String: [LayoutIssue]] {
        var r: [String: [LayoutIssue]] = [:]
        for i in layout {
            let iss = issues(for: i, in: layout, plan: plan)
            if !iss.isEmpty { r[i.id] = iss }
        }
        return r
    }
}

struct FurniturePreset: Identifiable {
    var id: String { name }
    var name: String
    var category: String
    var width: Double
    var depth: Double
    var height: Double

    static let all: [FurniturePreset] = [
        .init(name: "Postel 160×200", category: "bed", width: 1.6, depth: 2.05, height: 0.5),
        .init(name: "Postel 90×200", category: "bed", width: 0.9, depth: 2.05, height: 0.5),
        .init(name: "Gauč 3místný", category: "sofa", width: 2.2, depth: 0.95, height: 0.85),
        .init(name: "Křeslo", category: "chair", width: 0.85, depth: 0.85, height: 0.9),
        .init(name: "Pracovní stůl", category: "table", width: 1.4, depth: 0.7, height: 0.75),
        .init(name: "Jídelní stůl (4)", category: "table", width: 1.4, depth: 0.85, height: 0.75),
        .init(name: "Židle", category: "chair", width: 0.5, depth: 0.55, height: 0.9),
        .init(name: "Šatní skříň", category: "storage", width: 1.5, depth: 0.6, height: 2.2),
        .init(name: "Knihovna", category: "storage", width: 0.8, depth: 0.35, height: 1.9),
        .init(name: "Komoda", category: "storage", width: 1.2, depth: 0.5, height: 0.8),
        .init(name: "Noční stolek", category: "storage", width: 0.45, depth: 0.4, height: 0.5),
        .init(name: "TV stolek", category: "television", width: 1.8, depth: 0.45, height: 0.5),
        .init(name: "Konferenční stolek", category: "table", width: 1.1, depth: 0.6, height: 0.45),
        .init(name: "Koberec 200×300", category: "rug", width: 3.0, depth: 2.0, height: 0.01),
        .init(name: "Pokojová rostlina", category: "plant", width: 0.45, depth: 0.45, height: 1.2),
    ]
}
