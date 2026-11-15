import SwiftUI

struct PlanView: View {
    @Binding var record: ScanRecord
    var onChange: () -> Void
    @Environment(ScanStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var layers = PlanLayers()
    @State private var selection: PlanSelection = .none
    @State private var measuring = false
    @State private var measure: [P2] = []
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var drag: (id: String, start: P2)?
    @State private var dragActive = false
    @State private var rotationBase: Double?
    @State private var editing: LayoutItem?

    var body: some View {
        let issues = LayoutCheck.summary(record.layout, plan: record.plan)
        VStack(spacing: 0) {
            GeometryReader { geo in
                let m = PlanMapper(size: geo.size, bounds: record.plan.bounds, zoom: zoom, pan: pan)
                Canvas { ctx, _ in
                    PlanDrawing(plan: record.plan, layout: record.layout, photos: record.photos, layers: layers,
                                selection: selection, measure: measure, issues: issues, dark: scheme == .dark)
                        .draw(&ctx, m)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(m))
                .simultaneousGesture(zoomGesture)
                .simultaneousGesture(rotateGesture)
            }
            .clipped()
            infoPanel(issues: issues)
        }
        .toolbar { toolbar }
        .onAppear { layers.detected = record.layout.isEmpty }
        .onChange(of: record.layout.isEmpty) { layers.detected = record.layout.isEmpty }
        .sheet(item: $editing) { item in
            ItemEditor(item: item) { updated in
                if let updated, let i = record.layout.firstIndex(where: { $0.id == updated.id }) {
                    record.layout[i] = updated
                } else if updated == nil {
                    record.layout.removeAll { $0.id == item.id }
                    selection = .none
                }
                onChange()
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Gestures

    private func dragGesture(_ m: PlanMapper) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !dragActive {
                    dragActive = true
                    let p = m.plan(v.startLocation)
                    if !measuring, layers.layout, let item = hitItem(p) {
                        drag = (item.id, item.center)
                        selection = .item(item.id)
                    } else {
                        drag = nil
                        panBase = pan
                    }
                }
                if let d = drag, let i = record.layout.firstIndex(where: { $0.id == d.id }) {
                    let delta = P2(x: v.translation.width / m.scale, y: v.translation.height / m.scale)
                    var c = d.start + delta
                    c.x = (c.x * 100).rounded() / 100   // centimetre steps
                    c.y = (c.y * 100).rounded() / 100
                    record.layout[i].center = c
                } else {
                    pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
                }
            }
            .onEnded { v in
                dragActive = false
                let moved = hypot(v.translation.width, v.translation.height) > 6
                if !moved { tap(m.plan(v.location), m) }
                if drag != nil, moved { onChange() }
                drag = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in zoom = max(0.5, min(8, zoomBase * v.magnification)) }
            .onEnded { _ in zoomBase = zoom }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { v in
                guard case .item(let id) = selection, let i = record.layout.firstIndex(where: { $0.id == id }) else { return }
                if rotationBase == nil { rotationBase = record.layout[i].rotation }
                let r = rotationBase! + v.rotation.degrees
                record.layout[i].rotation = ((r / 5).rounded() * 5).truncatingRemainder(dividingBy: 360)
            }
            .onEnded { _ in rotationBase = nil; onChange() }
    }

    private func tap(_ p: P2, _ m: PlanMapper) {
        let tol = 14 / Double(m.scale)
        if measuring {
            let snapped = record.plan.snapPoints.min { $0.distance(to: p) < $1.distance(to: p) }
            let q = (snapped.map { $0.distance(to: p) < tol * 1.5 } ?? false) ? snapped! : p
            measure = measure.count >= 2 ? [q] : measure + [q]
            return
        }
        if layers.photos, let ph = record.photos.first(where: { $0.position.map { $0.distance(to: p) < tol } ?? false }) {
            selection = .photo(ph.id); return
        }
        if layers.layout, let item = hitItem(p) { selection = .item(item.id); return }
        if let o = record.plan.openings.first(where: { Geometry.distance(point: p, toSegment: $0.a, $0.b) < tol }) {
            selection = .opening(o.id); return
        }
        if let w = record.plan.walls.min(by: { Geometry.distance(point: p, toSegment: $0.a, $0.b) < Geometry.distance(point: p, toSegment: $1.a, $1.b) }),
           Geometry.distance(point: p, toSegment: w.a, w.b) < tol { selection = .wall(w.id); return }
        if layers.detected, let o = record.plan.objects.first(where: { Geometry.contains($0.corners(), p) }) {
            selection = .object(o.id); return
        }
        selection = .none
    }

    private func hitItem(_ p: P2) -> LayoutItem? {
        record.layout.filter { Geometry.contains($0.corners(), p) }.min { !LayoutCheck.isFlat($0) && LayoutCheck.isFlat($1) }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { measuring.toggle(); measure = [] } label: {
                Image(systemName: measuring ? "ruler.fill" : "ruler")
            }
            Menu {
                Section("Přidat nábytek") {
                    ForEach(FurniturePreset.all) { p in Button(p.name) { add(p) } }
                }
            } label: { Image(systemName: "plus.square.on.square") }
            Menu {
                Toggle("Rozměry stěn", isOn: $layers.dimensions)
                Toggle("Nalezený nábytek", isOn: $layers.detected)
                Toggle("Plánované rozvržení", isOn: $layers.layout)
                Toggle("Fotky", isOn: $layers.photos)
                Toggle("Mřížka", isOn: $layers.grid)
                Divider()
                Button("Vycentrovat") { withAnimation { zoom = 1; zoomBase = 1; pan = .zero } }
                if !record.plan.objects.isEmpty {
                    Button("Převzít nalezený nábytek do rozvržení") { adoptDetected() }
                }
                if !record.layout.isEmpty {
                    Button("Smazat rozvržení", role: .destructive) { record.layout = []; selection = .none; onChange() }
                }
            } label: { Image(systemName: "square.3.layers.3d") }
        }
    }

    private func add(_ p: FurniturePreset) {
        let c = Geometry.centroid(record.plan.outline)
        let item = LayoutItem(id: UUID().uuidString.prefix(8).lowercased(), name: p.name, category: p.category,
                              x: c.x, y: c.y, width: p.width, depth: p.depth, height: p.height, rotation: 0)
        record.layout.append(item)
        selection = .item(item.id)
        layers.layout = true
        onChange()
    }

    private func adoptDetected() {
        for o in record.plan.objects where !record.layout.contains(where: { $0.id == o.id }) {
            record.layout.append(LayoutItem(id: o.id, name: Names.category(o.category), category: o.category,
                                            x: o.center.x, y: o.center.y, width: o.width, depth: o.depth,
                                            height: o.height, rotation: o.rotation, note: "stávající"))
        }
        layers.layout = true
        onChange()
    }

    // MARK: Info panel

    @ViewBuilder private func infoPanel(issues: [String: [LayoutIssue]]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch selection {
            case .none:
                if measuring {
                    Text(measure.count == 2 ? "Vzdálenost: \(Fmt.m(measure[0].distance(to: measure[1])))"
                                            : "Měření: klepni na dva body (přichytí se k rohům).")
                } else {
                    roomSummary
                }
            case .wall(let id):
                if let w = record.plan.walls.first(where: { $0.id == id }) {
                    Text("Stěna").font(.headline)
                    Text("Délka \(Fmt.m(w.length)) · výška \(Fmt.m(w.height)) · plocha \(Fmt.m2(w.length * w.height))")
                }
            case .opening(let id):
                if let o = record.plan.openings.first(where: { $0.id == id }) {
                    Text(o.kind == .door ? "Dveře" : o.kind == .window ? "Okno" : "Otvor").font(.headline)
                    Text("Šířka \(Fmt.cm(o.width)) · výška \(Fmt.cm(o.height))" + (o.bottom > 0.05 ? " · parapet \(Fmt.cm(o.bottom))" : ""))
                }
            case .object(let id):
                if let o = record.plan.objects.first(where: { $0.id == id }) {
                    Text(Names.category(o.category) + " (nalezeno skenem)").font(.headline)
                    Text("\(Fmt.cm(o.width)) × \(Fmt.cm(o.depth)), výška \(Fmt.cm(o.height))")
                }
            case .item(let id):
                if let i = record.layout.firstIndex(where: { $0.id == id }) { itemPanel(i, issues: issues[id] ?? []) }
            case .photo(let id):
                if let p = record.photos.first(where: { $0.id == id }), let img = store.image(record, p) {
                    HStack {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 120).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(p.caption.isEmpty ? Fmt.date(p.takenAt) : p.caption).font(.footnote)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
    }

    private var roomSummary: some View {
        let p = record.plan
        return VStack(alignment: .leading, spacing: 4) {
            if let t = Names.room(p.roomType) { Text(t).font(.headline) }
            Text("Plocha \(Fmt.m2(p.area)) · obvod \(Fmt.m(p.perimeter, digits: 1)) · výška \(Fmt.m(p.ceilingHeight)) · objem \(Fmt.m3(p.volume))")
                .font(.subheadline)
            Text("\(p.walls.count) stěn · \(p.openings.filter { $0.kind == .door }.count) dveře · \(p.openings.filter { $0.kind == .window }.count) okna · \(record.layout.count) kusů v rozvržení")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func itemPanel(_ i: Int, issues: [LayoutIssue]) -> some View {
        let item = record.layout[i]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                Button { rotate(i, -15) } label: { Image(systemName: "rotate.left") }
                Button { rotate(i, 90) } label: { Image(systemName: "rotate.right") }
                Button { editing = item } label: { Image(systemName: "slider.horizontal.3") }
            }
            .buttonStyle(.bordered)
            Text("\(Fmt.cm(item.width)) × \(Fmt.cm(item.depth)) × \(Fmt.cm(item.height)) · otočení \(Int(item.rotation))°")
                .font(.footnote)
            if let n = item.note, !n.isEmpty { Text(n).font(.footnote).foregroundStyle(.secondary) }
            ForEach(issues, id: \.self) { Label($0.text, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
        }
    }

    private func rotate(_ i: Int, _ deg: Double) {
        var r = (record.layout[i].rotation + deg).truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        record.layout[i].rotation = r
        onChange()
    }
}

extension LayoutItem {
    init(id: Substring, name: String, category: String, x: Double, y: Double, width: Double, depth: Double,
         height: Double, rotation: Double) {
        self.init(id: String(id), name: name, category: category, x: x, y: y, width: width, depth: depth,
                  height: height, rotation: rotation, note: nil)
    }
}

struct ItemEditor: View {
    @State var item: LayoutItem
    var done: (LayoutItem?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Název", text: $item.name)
                Section("Rozměry (cm)") {
                    cmField("Šířka", $item.width)
                    cmField("Hloubka", $item.depth)
                    cmField("Výška", $item.height)
                    Stepper("Otočení \(Int(item.rotation))°", value: $item.rotation, in: 0...355, step: 5)
                }
                TextField("Poznámka", text: Binding(get: { item.note ?? "" }, set: { item.note = $0 }), axis: .vertical)
                Button("Smazat", role: .destructive) { done(nil); dismiss() }
            }
            .navigationTitle("Upravit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { done(item); dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
            }
        }
    }

    private func cmField(_ title: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: Binding(get: { (v.wrappedValue * 100).rounded() }, set: { v.wrappedValue = max(1, $0) / 100 }),
                      format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
        }
    }
}
