import Foundation

/// A hand-made room so the plan, 3D view and AI planner can be tried without LiDAR (e.g. in the Simulator).
enum DemoRoom {
    static func plan() -> PlanModel {
        // L-shaped bedroom: 4.6 × 3.8 m with a 1.2 × 0.9 m corner cut out for a hallway closet.
        let outline: [P2] = [
            P2(x: 0, y: 0), P2(x: 4.6, y: 0), P2(x: 4.6, y: 2.9),
            P2(x: 3.4, y: 2.9), P2(x: 3.4, y: 3.8), P2(x: 0, y: 3.8),
        ]
        var walls: [PlanWall] = []
        for i in outline.indices {
            walls.append(PlanWall(id: "w\(i)", a: outline[i], b: outline[(i + 1) % outline.count], height: 2.62))
        }
        let openings: [PlanOpening] = [
            PlanOpening(id: "d1", kind: .door, center: P2(x: 2.6, y: 3.8), direction: P2(x: 1, y: 0),
                        width: 0.8, height: 1.97, bottom: 0),
            PlanOpening(id: "o1", kind: .window, center: P2(x: 1.5, y: 0), direction: P2(x: 1, y: 0),
                        width: 1.5, height: 1.5, bottom: 0.85),
            PlanOpening(id: "o2", kind: .window, center: P2(x: 4.6, y: 1.4), direction: P2(x: 0, y: 1),
                        width: 1.2, height: 1.5, bottom: 0.85),
        ]
        let objects: [PlanObject] = [
            PlanObject(id: "b1", category: "bed", center: P2(x: 1.05, y: 2.0), width: 1.6, depth: 2.05,
                       height: 0.5, rotation: 90),
            PlanObject(id: "s1", category: "storage", center: P2(x: 0.3, y: 0.6), width: 1.0, depth: 0.6,
                       height: 2.1, rotation: 90),
        ]
        return PlanModel(walls: walls, openings: openings, objects: objects, outline: outline,
                         transform: PlanTransform(angle: 0, offset: .zero, floorY: 0), roomType: "bedroom")
    }

    static func record(name: String) -> ScanRecord {
        ScanRecord(id: UUID().uuidString, name: name, createdAt: Date(), plan: plan(),
                   notes: "Ukázková místnost bez LiDARu.")
    }

    static func sampleLayout() -> [LayoutItem] {
        [
            LayoutItem(id: "bed", name: "Postel 160×200", category: "bed", x: 1.05, y: 1.75, width: 1.6, depth: 2.05,
                       height: 0.5, rotation: 90, note: "čelo u levé stěny"),
            LayoutItem(id: "desk", name: "Pracovní stůl", category: "table", x: 4.2, y: 1.4, width: 1.4, depth: 0.7,
                       height: 0.75, rotation: 90, note: "u okna, světlo zleva"),
            LayoutItem(id: "chair", name: "Židle", category: "chair", x: 3.6, y: 1.4, width: 0.5, depth: 0.55,
                       height: 0.9, rotation: 270, note: nil),
            LayoutItem(id: "wardrobe", name: "Šatní skříň", category: "storage", x: 0.75, y: 3.48, width: 1.5, depth: 0.6,
                       height: 2.2, rotation: 180, note: nil),
            LayoutItem(id: "rug", name: "Koberec", category: "rug", x: 2.4, y: 2.0, width: 2.0, depth: 1.4,
                       height: 0.01, rotation: 0, note: nil),
        ]
    }
}
