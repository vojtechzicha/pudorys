import SwiftUI
import RoomPlan
import ARKit
import AVFoundation
import CoreImage
import simd

/// A photo taken while scanning, with the camera pose so it can be pinned on the plan.
struct PendingPhoto {
    var jpeg: Data
    var camera: simd_float4x4
    var takenAt = Date()
}

/// Owns the RoomPlan capture view and turns its result into a saved `ScanRecord`.
final class ScanSession: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum Phase { case scanning, processing, done, failed(String) }

    @Published var phase: Phase = .scanning
    @Published var photoCount = 0
    @Published var flash = false
    let captureView: RoomCaptureView
    private(set) var result: CapturedRoom?
    private var photos: [PendingPhoto] = []
    private var cancelled = false
    private let ci = CIContext()

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    func encode(with coder: NSCoder) {}

    func start() {
        let access = AVCaptureDevice.authorizationStatus(for: .video)
        if access == .denied || access == .restricted {
            phase = .failed("Aplikace nemá přístup ke kameře. Povol ho v Nastavení → Půdorys → Kamera.")
            return
        }
        // Nobody touches the screen while walking around the room; keep it from locking.
        UIApplication.shared.isIdleTimerDisabled = true
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        captureView.captureSession.run(configuration: config)
    }

    func finish() {
        phase = .processing
        captureView.captureSession.stop()
    }

    func cancel() {
        cancelled = true
        captureView.captureSession.stop()
    }

    /// Called when the scan screen goes away, however it was closed.
    func end() { UIApplication.shared.isIdleTimerDisabled = false }

    func takePhoto() {
        guard let frame = captureView.captureSession.arSession.currentFrame else { return }
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(Self.orientation(of: frame.camera.transform))
        let opts = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]
        guard let jpeg = ci.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               options: opts) else { return }
        photos.append(PendingPhoto(jpeg: jpeg, camera: frame.camera.transform))
        photoCount = photos.count
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.flash = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: RoomCaptureViewDelegate

    /// How to turn the camera image (always sensor-landscape) so that up is up, however the phone is held.
    static func orientation(of camera: simd_float4x4) -> CGImagePropertyOrientation {
        // World up as it appears in the image: the image's right is the camera's +x, its top the camera's +y.
        let right = camera.columns.0.y, top = camera.columns.1.y
        // Pointing at the floor or the ceiling there is no up; scanning is done in portrait.
        if abs(right) < 0.25 && abs(top) < 0.25 { return .right }
        if abs(right) >= abs(top) { return right < 0 ? .right : .left }
        return top > 0 ? .up : .down
    }

    // RoomPlan does not promise the main thread for these, and they drive the UI.

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if cancelled { return false }
        if let error {
            DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.phase = .failed(error.localizedDescription)
                return
            }
            self.result = processedResult
            self.phase = .done
        }
    }

    /// Writes the scan into the store: plan, raw RoomPlan JSON, USDZ model and photos.
    func save(into store: ScanStore, name: String) -> ScanRecord? {
        guard let room = result else { return nil }
        let plan = PlanBuilder.build(from: room)
        var rec = ScanRecord(id: UUID().uuidString, name: name, createdAt: Date(), plan: plan)
        store.save(rec)
        // The plan is already saved; a failure here loses only the 3D model or the raw data, so note it and go on.
        var problems: [String] = []
        do { try room.export(to: store.modelURL(rec.id), exportOptions: .parametric) }
        catch { problems.append("model.usdz: \(error)") }
        do { try JSONEncoder().encode(room).write(to: store.roomURL(rec.id)) }
        catch { problems.append("room.json: \(error)") }
        if !problems.isEmpty {
            try? problems.joined(separator: "\n").write(to: store.dir(rec.id).appendingPathComponent("save-errors.txt"),
                                                        atomically: true, encoding: .utf8)
        }

        let t = plan.transform
        for p in photos {
            let pos = p.camera.columns.3, fwd = -p.camera.columns.2
            let dir = P2(x: Double(fwd.x), y: Double(fwd.z)).normalized.rotated(by: t.angle)
            store.addPhoto(p.jpeg, to: &rec,
                           position: t.toPlan(x: Double(pos.x), z: Double(pos.z)),
                           heading: atan2(dir.y, dir.x) * 180 / .pi, takenAt: p.takenAt)
        }
        store.save(rec)
        return rec
    }
}

struct CaptureViewHost: UIViewRepresentable {
    let session: ScanSession
    func makeUIView(context: Context) -> RoomCaptureView { session.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct ScanView: View {
    @Environment(ScanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = ScanSession()
    @State private var name = ""
    var onSaved: (ScanRecord) -> Void

    var body: some View {
        ZStack {
            CaptureViewHost(session: session).ignoresSafeArea()
            if session.flash { Color.white.opacity(0.6).ignoresSafeArea().allowsHitTesting(false) }
            VStack {
                HStack {
                    Button("Zrušit") { session.cancel(); dismiss() }
                        .buttonStyle(.bordered).tint(.white)
                    Spacer()
                    if session.photoCount > 0 {
                        Label("\(session.photoCount)", systemImage: "photo.on.rectangle")
                            .padding(8).background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                Spacer()
                controls.padding(.bottom, 30)
            }
        }
        .onAppear {
            name = store.nextName()
            session.start()
        }
        .onDisappear { session.end() }
        .statusBarHidden()
    }

    @ViewBuilder private var controls: some View {
        switch session.phase {
        case .scanning:
            HStack(spacing: 24) {
                Button { session.takePhoto() } label: {
                    Image(systemName: "camera.fill").font(.title2).frame(width: 64, height: 64)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Button { session.finish() } label: {
                    Text("Hotovo").font(.headline).frame(width: 160, height: 56)
                        .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                }
            }
            Text("Projdi pomalu místnost, mířit na stěny, rohy a podlahu. Tlačítkem s fotoaparátem ulož fotku, zobrazí se v půdorysu.")
                .font(.footnote).multilineTextAlignment(.center).padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
        case .processing:
            ProgressView("Zpracovávám sken…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .done:
            VStack(spacing: 12) {
                TextField("Název místnosti", text: $name)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Button {
                    if let rec = session.save(into: store, name: name.isEmpty ? store.nextName() : name) {
                        onSaved(rec)
                    }
                    dismiss()
                } label: {
                    Text("Uložit sken").font(.headline).frame(width: 200, height: 52)
                        .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
                }
            }
            .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .failed(let msg):
            VStack {
                Text("Sken se nepodařil: \(msg)").multilineTextAlignment(.center)
                Button("Zavřít") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
