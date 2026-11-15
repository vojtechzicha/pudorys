import Foundation

/// The room described as compact JSON for Claude, both in the in-app planner and in the export
/// (plan.json) that Claude Code reads. Format documented in docs/layout-format.md.
enum PlanBrief {
    static func object(_ rec: ScanRecord) -> [String: Any] {
        let p = rec.plan
        func pt(_ q: P2) -> [NSDecimalNumber] { [r(q.x), r(q.y)] }
        var photoIndex = 0
        return [
            "format": "pudorys-plan/1",
            "name": rec.name,
            "units": "metres; x to the right, y downwards on the plan (top view); rotation in degrees clockwise",
            "room_type": p.roomType.map { $0 as Any } ?? NSNull(),
            "area_m2": r(p.area),
            "perimeter_m": r(p.perimeter),
            "ceiling_height_m": r(p.ceilingHeight),
            "outline": p.outline.map(pt),
            "walls": p.walls.map { ["id": $0.id, "from": pt($0.a), "to": pt($0.b), "length": r($0.length), "height": r($0.height)] },
            "openings": p.openings.map { o -> [String: Any] in
                ["id": o.id, "kind": o.kind.rawValue, "from": pt(o.a), "to": pt(o.b), "width": r(o.width),
                 "height": r(o.height), "sill": r(o.bottom), "door_open": o.isOpen]
            },
            "door_clearance_zones": LayoutCheck.doorZones(p).map { $0.1.map(pt) },
            "detected_furniture": p.objects.map { o -> [String: Any] in
                ["id": o.id, "category": o.category, "x": r(o.center.x), "y": r(o.center.y), "width": r(o.width),
                 "depth": r(o.depth), "height": r(o.height), "rotation": r(o.rotation)]
            },
            "photos": rec.photos.map { ph -> [String: Any] in
                photoIndex += 1
                var d: [String: Any] = ["index": photoIndex, "file": "photos/\(ph.fileName)"]
                if let pos = ph.position { d["camera_at"] = pt(pos) }
                if let h = ph.heading { d["looking_towards_deg"] = r(h, 1) }
                if !ph.caption.isEmpty { d["caption"] = ph.caption }
                return d
            },
            "notes": rec.notes,
        ]
    }

    static func layoutObject(_ layout: [LayoutItem]) -> [[String: Any]] {
        layout.map { i in
            ["id": i.id, "name": i.name, "category": i.category, "x": r(i.x), "y": r(i.y), "width": r(i.width),
             "depth": r(i.depth), "height": r(i.height), "rotation": r(i.rotation, 1), "note": i.note ?? ""]
        }
    }

    /// Rounded number that JSONSerialization prints without binary noise (2.62, not 2.6200000000000001).
    static func r(_ v: Double, _ digits: Int = 2) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.\(digits)f", v))
    }

    static func json(_ any: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    /// Text to paste into claude.ai or Claude Code when not using the in-app planner.
    static func prompt(_ rec: ScanRecord, request: String) -> String {
        """
        Tady je půdorys místnosti z LiDAR skenu (aplikace Půdorys). Navrhni rozmístění nábytku.

        Požadavek: \(request.isEmpty ? "(doplň)" : request)

        Vrať výsledek jako JSON pole `layout` podle formátu níže, aby šlo nahrát zpět do aplikace (Importovat rozvržení).
        Každý kus: {"id","name","category","x","y","width","depth","height","rotation","note"}; x,y = střed v metrech,
        width podél osy x při rotation 0, přední strana míří k +y, rotation ve stupních po směru hodinových ručiček.

        Půdorys:
        \(json(object(rec)))

        Současné rozvržení:
        \(json(layoutObject(rec.layout)))
        """
    }
}
