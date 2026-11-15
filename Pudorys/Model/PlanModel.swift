import Foundation
import CoreGraphics

/// A 2D point on the floor plan, in metres. x grows to the right, y grows "down" on screen
/// (it is the world z axis seen from above). The plan is rotated so the longest wall is horizontal
/// and shifted so the room starts at (0, 0).
struct P2: Codable, Hashable {
    var x: Double
    var y: Double

    static let zero = P2(x: 0, y: 0)
    static func + (a: P2, b: P2) -> P2 { P2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: P2, b: P2) -> P2 { P2(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: P2, s: Double) -> P2 { P2(x: a.x * s, y: a.y * s) }
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: P2 { let l = length; return l > 0 ? P2(x: x / l, y: y / l) : self }
    func rotated(by a: Double) -> P2 { P2(x: x * cos(a) - y * sin(a), y: x * sin(a) + y * cos(a)) }
    func distance(to o: P2) -> Double { (self - o).length }
    func dot(_ o: P2) -> Double { x * o.x + y * o.y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

struct PlanWall: Codable, Hashable, Identifiable {
    var id: String
    var a: P2
    var b: P2
    var height: Double
    var length: Double { a.distance(to: b) }
    var mid: P2 { (a + b) * 0.5 }
}

enum OpeningKind: String, Codable { case door, window, opening }

struct PlanOpening: Codable, Hashable, Identifiable {
    var id: String
    var kind: OpeningKind
    var center: P2
    /// Unit vector along the wall the opening sits in.
    var direction: P2
    var width: Double
    var height: Double
    /// Height of the bottom edge above the floor (window sill), metres.
    var bottom: Double
    var isOpen: Bool = false
    var a: P2 { center - direction * (width / 2) }
    var b: P2 { center + direction * (width / 2) }
}

/// A furniture piece RoomPlan detected, or one the user / Claude placed in a layout.
struct PlanObject: Codable, Hashable, Identifiable {
    var id: String
    var category: String
    var center: P2
    var width: Double
    var depth: Double
    var height: Double
    /// Rotation in degrees, clockwise on screen. 0 means `width` runs along the x axis.
    var rotation: Double
    var bottom: Double = 0

    func corners() -> [P2] {
        let r = rotation * .pi / 180
        let hw = width / 2, hd = depth / 2
        return [P2(x: -hw, y: -hd), P2(x: hw, y: -hd), P2(x: hw, y: hd), P2(x: -hw, y: hd)]
            .map { $0.rotated(by: r) + center }
    }
}

/// Maps plan coordinates back to the RoomPlan world: world(x, z) = R(-angle) · (plan + offset).
struct PlanTransform: Codable, Hashable {
    var angle: Double
    var offset: P2
    var floorY: Double

    func toPlan(x: Double, z: Double) -> P2 { P2(x: x, y: z).rotated(by: angle) - offset }
    func toWorld(_ p: P2) -> P2 { (p + offset).rotated(by: -angle) }
}

struct PlanModel: Codable, Hashable {
    var walls: [PlanWall]
    var openings: [PlanOpening]
    var objects: [PlanObject]
    /// Floor outline (closed polygon, last point not repeated).
    var outline: [P2]
    var transform: PlanTransform
    var roomType: String?

    var area: Double { Geometry.polygonArea(outline) }
    var perimeter: Double {
        guard outline.count > 2 else { return walls.reduce(0) { $0 + $1.length } }
        return zip(outline, outline.dropFirst() + [outline[0]]).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
    var ceilingHeight: Double { walls.map(\.height).max() ?? 2.5 }
    var volume: Double { area * ceilingHeight }

    var bounds: CGRect {
        let pts = outline + walls.flatMap { [$0.a, $0.b] } + objects.flatMap { $0.corners() }
        guard let f = pts.first else { return CGRect(x: 0, y: 0, width: 4, height: 4) }
        var r = CGRect(origin: f.cg, size: .zero)
        for p in pts { r = r.union(CGRect(origin: p.cg, size: .zero)) }
        return r
    }

    /// Wall endpoints, for snapping the measuring tool.
    var snapPoints: [P2] { walls.flatMap { [$0.a, $0.b] } + outline }
}

enum Geometry {
    static func polygonArea(_ pts: [P2]) -> Double {
        guard pts.count > 2 else { return 0 }
        var s = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return abs(s) / 2
    }

    static func centroid(_ pts: [P2]) -> P2 {
        guard !pts.isEmpty else { return .zero }
        return pts.reduce(.zero, +) * (1 / Double(pts.count))
    }

    static func contains(_ poly: [P2], _ p: P2) -> Bool {
        guard poly.count > 2 else { return true }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Separating-axis test for two convex polygons.
    static func overlaps(_ p: [P2], _ q: [P2], tolerance: Double = 0.01) -> Bool {
        for poly in [p, q] {
            for i in poly.indices {
                let e = poly[(i + 1) % poly.count] - poly[i]
                let axis = P2(x: -e.y, y: e.x).normalized
                let pp = p.map { $0.dot(axis) }, qq = q.map { $0.dot(axis) }
                if pp.max()! <= qq.min()! + tolerance || qq.max()! <= pp.min()! + tolerance { return false }
            }
        }
        return true
    }

    static func distance(point p: P2, toSegment a: P2, _ b: P2) -> Double {
        let ab = b - a
        let t = max(0, min(1, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
        return p.distance(to: a + ab * t)
    }
}
