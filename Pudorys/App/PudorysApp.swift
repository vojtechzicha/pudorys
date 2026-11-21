import SwiftUI
import RoomPlan

@main
struct PudorysApp: App {
    @State private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            ScanListView().environment(store)
        }
    }
}

struct ScanListView: View {
    @Environment(ScanStore.self) private var store
    @State private var scanning = false
    @State private var unsupported = false
    @State private var showSettings = false
    @State private var path: [ScanRecord] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.records.isEmpty {
                    ContentUnavailableView {
                        Label("Zatím žádný sken", systemImage: "cube.transparent")
                    } description: {
                        Text("Naskenuj místnost LiDARem. Vznikne půdorys s rozměry, 3D model a můžeš s Claudem plánovat rozmístění nábytku.")
                    }
                }
                ForEach(store.records) { rec in
                    NavigationLink(value: rec) { row(rec) }
                }
                .onDelete { idx in idx.map { store.records[$0] }.forEach(store.delete) }
            }
            .navigationTitle("Půdorys")
            .navigationDestination(for: ScanRecord.self) { ScanDetailView(record: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { addDemo() } label: { Label("Ukázková místnost", systemImage: "square.dashed") }
                        Button { showSettings = true } label: { Label("Nastavení", systemImage: "gear") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if RoomCaptureSession.isSupported { scanning = true } else { unsupported = true }
                } label: {
                    Label("Nový sken", systemImage: "camera.viewfinder").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .fullScreenCover(isPresented: $scanning) {
                ScanView { rec in path = [rec] }.environment(store)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Toto zařízení nemá LiDAR", isPresented: $unsupported) {
                Button("Otevřít ukázku") { addDemo() }
                Button("Zavřít", role: .cancel) {}
            } message: {
                Text("Skenování místnosti (RoomPlan) potřebuje iPhone nebo iPad s LiDARem (řada Pro). Můžeš si vyzkoušet ukázkovou místnost.")
            }
            .onAppear {
                store.load()
                // Debug: `-demo` opens the sample room (used for Simulator screenshots).
                if ProcessInfo.processInfo.arguments.contains("-demo"), path.isEmpty {
                    var rec = store.records.first { $0.name == "Ukázka – ložnice" } ?? DemoRoom.record(name: "Ukázka – ložnice")
                    if ProcessInfo.processInfo.arguments.contains("-demoLayout") { rec.layout = DemoRoom.sampleLayout() }
                    store.save(rec)
                    path = [rec]
                }
                debugReplay()
            }
        }
    }

    private func row(_ rec: ScanRecord) -> some View {
        HStack(spacing: 12) {
            Canvas { ctx, size in
                var layers = PlanLayers()
                layers.dimensions = false; layers.grid = false; layers.photos = false; layers.labels = false
                PlanDrawing(plan: rec.plan, layout: rec.layout, photos: [], layers: layers)
                    .draw(&ctx, PlanMapper(size: size, bounds: rec.plan.bounds, padding: 0.2))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, .light)
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.name).font(.headline)
                Text("\(Fmt.m2(rec.plan.area)) · \(rec.photos.count) fotek · \(rec.layout.count) v rozvržení")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Fmt.date(rec.createdAt)).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// Debug: `-rebuild` runs PlanBuilder again on every scan's stored RoomPlan data;
    /// `-importRoom <file>` adds a scan from a RoomPlan JSON file and opens it;
    /// `-open <name>` opens the scan with that name.
    private func debugReplay() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-rebuild") {
            for rec in store.records {
                print("REBUILD:", rec.name, store.rebuildPlan(rec) == nil ? "no RoomPlan data" : "ok")
            }
        }
        if let i = args.firstIndex(of: "-importRoom"), i + 1 < args.count, path.isEmpty {
            let url = URL(fileURLWithPath: args[i + 1])
            do {
                let rec = try store.importRoom(at: url, name: url.deletingPathExtension().lastPathComponent)
                print("IMPORT: ok", rec.plan.walls.count, "walls,", rec.plan.outline.count, "outline points,",
                      rec.plan.openings.count, "openings,", rec.plan.objects.count, "objects")
                path = [rec]
            } catch {
                print("IMPORT: failed", error)
            }
        }
        if let i = args.firstIndex(of: "-open"), i + 1 < args.count, path.isEmpty,
           let rec = store.records.first(where: { $0.name == args[i + 1] }) {
            path = [rec]
        }
    }

    private func addDemo() {
        let rec = DemoRoom.record(name: "Ukázka – ložnice")
        store.save(rec)
        path = [rec]
    }
}
