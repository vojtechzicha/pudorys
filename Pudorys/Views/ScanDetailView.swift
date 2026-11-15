import SwiftUI
import PhotosUI

struct ScanDetailView: View {
    @Environment(ScanStore.self) private var store
    @State var record: ScanRecord
    @State private var tab: Tab = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-tab"), i + 1 < a.count { return Tab.allCases.first { "\($0)" == a[i + 1] } ?? .plan }
        return .plan
    }()
    @State private var shareURL: URL?
    @State private var exportError: String?
    @State private var renaming = false
    @State private var newName = ""

    enum Tab: String, CaseIterable { case plan = "Půdorys", model = "3D", photos = "Fotky", ai = "AI plán" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 6)
            switch tab {
            case .plan: PlanView(record: $record, onChange: save)
            case .model: Room3DView(record: record)
            case .photos: PhotosView(record: $record, onChange: save)
            case .ai: PlannerView(record: $record, onChange: save)
            }
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { export() } label: { Label("Exportovat (ZIP)", systemImage: "square.and.arrow.up") }
                    Button { newName = record.name; renaming = true } label: { Label("Přejmenovat", systemImage: "pencil") }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
        .onAppear {
            // Debug: `-exportTest` writes the export and logs where (Simulator checks).
            if ProcessInfo.processInfo.arguments.contains("-exportTest") {
                print("EXPORT:", (try? Exporter.export(record, store: store).path) ?? "failed")
            }
        }
        .alert("Export selhal", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") {}
        } message: { Text(exportError ?? "") }
        .alert("Přejmenovat", isPresented: $renaming) {
            TextField("Název", text: $newName)
            Button("Uložit") { if !newName.isEmpty { record.name = newName; save() } }
            Button("Zrušit", role: .cancel) {}
        }
    }

    private func save() { store.save(record) }

    private func export() {
        do { shareURL = try Exporter.export(record, store: store) } catch { exportError = error.localizedDescription }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PhotosView: View {
    @Binding var record: ScanRecord
    var onChange: () -> Void
    @Environment(ScanStore.self) private var store
    @State private var picked: [PhotosPickerItem] = []
    @State private var open: PhotoRecord?

    var body: some View {
        ScrollView {
            if record.photos.isEmpty {
                ContentUnavailableView("Žádné fotky", systemImage: "photo",
                                       description: Text("Fotky pořízené při skenování se zobrazí i v půdorysu. Další můžeš přidat z knihovny."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(record.photos) { p in
                    Button { open = p } label: {
                        Color.clear.aspectRatio(0.75, contentMode: .fit)
                            .overlay {
                                if let img = store.image(record, p) { Image(uiImage: img).resizable().scaledToFill() }
                            }
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                if p.position != nil {
                                    Image(systemName: "mappin.circle.fill").foregroundStyle(.white, .orange).padding(4)
                                }
                            }
                    }
                }
            }
            .padding(4)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $picked, matching: .images) { Image(systemName: "plus") }
            }
        }
        .onChange(of: picked) {
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                       let jpeg = img.jpegData(compressionQuality: 0.85) {
                        store.addPhoto(jpeg, to: &record)
                    }
                }
                picked = []
                onChange()
            }
        }
        .sheet(item: $open) { p in
            PhotoDetail(record: $record, photo: p, onChange: onChange)
        }
    }
}

struct PhotoDetail: View {
    @Binding var record: ScanRecord
    var photo: PhotoRecord
    var onChange: () -> Void
    @Environment(ScanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            VStack {
                if let img = store.image(record, photo) { Image(uiImage: img).resizable().scaledToFit() }
                TextField("Popisek (pomůže Claudovi, např. „radiátor pod oknem“)", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder).padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") {
                        if let i = record.photos.firstIndex(where: { $0.id == photo.id }) { record.photos[i].caption = caption }
                        onChange(); dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        try? FileManager.default.removeItem(at: store.photoURL(record, photo))
                        record.photos.removeAll { $0.id == photo.id }
                        onChange(); dismiss()
                    } label: { Image(systemName: "trash") }
                }
            }
            .onAppear { caption = photo.caption }
        }
    }
}
