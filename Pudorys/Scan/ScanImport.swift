import Foundation
import RoomPlan

/// Builds plans from stored RoomPlan data (`room.json`), without scanning. RoomPlan can decode a
/// `CapturedRoom` anywhere, the Simulator included, so a scan from a real device can be replayed there.
extension ScanStore {
    /// Runs `PlanBuilder` again on the scan's stored RoomPlan data and moves the photos and the
    /// layout to the new plan coordinates. Returns nil when the scan has no readable `room.json`.
    @discardableResult
    func rebuildPlan(_ rec: ScanRecord) -> ScanRecord? {
        guard let data = try? Data(contentsOf: roomURL(rec.id)),
              let room = try? JSONDecoder().decode(CapturedRoom.self, from: data) else { return nil }
        var new = rec
        new.plan = PlanBuilder.build(from: room)
        let old = rec.plan.transform, t = new.plan.transform
        func move(_ p: P2) -> P2 {
            let w = old.toWorld(p)
            return t.toPlan(x: w.x, z: w.y)
        }
        let turn = (t.angle - old.angle) * 180 / .pi
        new.photos = rec.photos.map { p in
            var p = p
            p.position = p.position.map(move)
            p.heading = p.heading.map { $0 + turn }
            return p
        }
        new.layout = rec.layout.map { item in
            var item = item
            item.center = move(item.center)
            item.rotation += turn
            return item
        }
        save(new)
        return new
    }

    /// Adds a scan from a RoomPlan JSON file (a `room.json` taken from a device, or
    /// `roomplan-captured-room.json` from an export).
    func importRoom(at url: URL, name: String) throws -> ScanRecord {
        let data = try Data(contentsOf: url)
        let room = try JSONDecoder().decode(CapturedRoom.self, from: data)
        let rec = ScanRecord(id: UUID().uuidString, name: name, createdAt: Date(), plan: PlanBuilder.build(from: room))
        save(rec)
        try data.write(to: roomURL(rec.id))
        return rec
    }
}
