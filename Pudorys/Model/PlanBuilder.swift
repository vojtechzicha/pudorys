import Foundation
import RoomPlan
import simd

/// Turns RoomPlan's 3D result into the flat, normalised `PlanModel` the app draws and sends to Claude.
enum PlanBuilder {
    static func build(from room: CapturedRoom) -> PlanModel {
        let walls = room.walls
        let floorY: Double = {
            if let f = room.floors.first { return Double(f.transform.columns.3.y) }
            let mins = walls.map { Double($0.transform.columns.3.y - $0.dimensions.y / 2) }
            return mins.min() ?? 0
        }()

        // Rotate so the longest wall runs along the x axis.
        let longest = walls.max { $0.dimensions.x < $1.dimensions.x }
        var angle = 0.0
        if let w = longest {
            let d = w.transform.columns.0
            angle = -atan2(Double(d.z), Double(d.x))
        }
        var t = PlanTransform(angle: angle, offset: .zero, floorY: floorY)

        func center(_ m: simd_float4x4) -> P2 { t.toPlan(x: Double(m.columns.3.x), z: Double(m.columns.3.z)) }
        func axis(_ m: simd_float4x4) -> P2 {
            P2(x: Double(m.columns.0.x), y: Double(m.columns.0.z)).normalized.rotated(by: angle)
        }
        func degrees(_ v: P2) -> Double { atan2(v.y, v.x) * 180 / .pi }

        var planWalls: [PlanWall] = walls.map { w in
            let c = center(w.transform), d = axis(w.transform), half = Double(w.dimensions.x) / 2
            return PlanWall(id: w.identifier.uuidString, a: c - d * half, b: c + d * half, height: Double(w.dimensions.y))
        }

        var openings: [PlanOpening] = []
        for (list, kind) in [(room.doors, OpeningKind.door), (room.windows, .window), (room.openings, .opening)] {
            for s in list {
                var isOpen = false
                if case .door(let open) = s.category { isOpen = open }
                let h = Double(s.dimensions.y)
                openings.append(PlanOpening(
                    id: s.identifier.uuidString, kind: kind,
                    center: center(s.transform), direction: axis(s.transform),
                    width: Double(s.dimensions.x), height: h,
                    bottom: max(0, Double(s.transform.columns.3.y) - h / 2 - floorY),
                    isOpen: isOpen))
            }
        }

        var objects: [PlanObject] = room.objects.map { o in
            let h = Double(o.dimensions.y)
            return PlanObject(
                id: o.identifier.uuidString, category: String(describing: o.category),
                center: center(o.transform), width: Double(o.dimensions.x), depth: Double(o.dimensions.z),
                height: h, rotation: degrees(axis(o.transform)),
                bottom: max(0, Double(o.transform.columns.3.y) - h / 2 - floorY))
        }

        var outline: [P2] = []
        if let floor = room.floors.first, floor.polygonCorners.count > 2 {
            outline = floor.polygonCorners.map { c in
                let w = floor.transform * simd_float4(c, 1)
                return t.toPlan(x: Double(w.x), z: Double(w.z))
            }
        }
        if outline.count < 3 { outline = chain(planWalls) }

        // Shift so everything starts at (0, 0).
        let pts = outline + planWalls.flatMap { [$0.a, $0.b] }
        let minP = P2(x: pts.map(\.x).min() ?? 0, y: pts.map(\.y).min() ?? 0)
        t.offset = minP
        func shift(_ p: P2) -> P2 { p - minP }
        outline = outline.map(shift)
        planWalls = planWalls.map { var w = $0; w.a = shift(w.a); w.b = shift(w.b); return w }
        openings = openings.map { var o = $0; o.center = shift(o.center); return o }
        objects = objects.map { var o = $0; o.center = shift(o.center); return o }

        let roomType = room.sections.first.map { String(describing: $0.label) }
        return PlanModel(walls: planWalls, openings: openings, objects: objects, outline: outline,
                         transform: t, roomType: roomType)
    }

    /// Orders wall segments into a loop when RoomPlan gives no floor polygon.
    static func chain(_ walls: [PlanWall]) -> [P2] {
        guard var current = walls.first else { return [] }
        var rest = Array(walls.dropFirst())
        var pts = [current.a, current.b]
        while !rest.isEmpty {
            let end = pts.last!
            var best = 0, bestFlip = false, bestD = Double.infinity
            for (i, w) in rest.enumerated() {
                if w.a.distance(to: end) < bestD { bestD = w.a.distance(to: end); best = i; bestFlip = false }
                if w.b.distance(to: end) < bestD { bestD = w.b.distance(to: end); best = i; bestFlip = true }
            }
            current = rest.remove(at: best)
            let next = bestFlip ? current.a : current.b
            pts[pts.count - 1] = (end + (bestFlip ? current.b : current.a)) * 0.5
            pts.append(next)
        }
        if let f = pts.first, let l = pts.last, f.distance(to: l) < 0.5 { pts[0] = (f + l) * 0.5; pts.removeLast() }
        return pts
    }
}
