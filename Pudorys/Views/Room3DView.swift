import SwiftUI
import SceneKit
import QuickLook

/// Builds a SceneKit model of the room from plan data (x = plan x, z = plan y, y up).
enum RoomScene {
    static func make(plan: PlanModel, layout: [LayoutItem], showDetected: Bool, showLayout: Bool,
                     lowWalls: Bool) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode

        if plan.outline.count > 2 {
            let path = UIBezierPath()
            path.move(to: plan.outline[0].cg)
            for p in plan.outline.dropFirst() { path.addLine(to: p.cg) }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.02)
            shape.firstMaterial = mat(UIColor(red: 0.82, green: 0.72, blue: 0.58, alpha: 1))
            let n = SCNNode(geometry: shape)
            n.eulerAngles.x = .pi / 2
            root.addChildNode(n)
        }

        for w in plan.walls {
            let h = lowWalls ? min(1.0, w.height) : w.height
            let box = SCNBox(width: w.length + 0.1, height: h, length: 0.1, chamferRadius: 0)
            box.firstMaterial = mat(UIColor(white: 0.95, alpha: 1))
            root.addChildNode(place(box, at: w.mid, along: w.b - w.a, bottom: 0, height: h))
        }

        for o in plan.openings {
            let wallTop = lowWalls ? 1.0 : plan.ceilingHeight
            guard o.bottom < wallTop else { continue }
            let h = min(o.height, wallTop - o.bottom)
            let box = SCNBox(width: o.width, height: h, length: 0.14, chamferRadius: 0)
            switch o.kind {
            case .door: box.firstMaterial = mat(UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1))
            case .window: box.firstMaterial = mat(UIColor.systemBlue.withAlphaComponent(0.35))
            case .opening: box.firstMaterial = mat(UIColor(white: 0.3, alpha: 0.25))
            }
            root.addChildNode(place(box, at: o.center, along: o.direction, bottom: o.bottom, height: h))
        }

        if showDetected {
            for o in plan.objects {
                let box = SCNBox(width: o.width, height: o.height, length: o.depth, chamferRadius: 0.02)
                box.firstMaterial = mat(UIColor(white: 0.55, alpha: showLayout && !layout.isEmpty ? 0.35 : 0.9))
                root.addChildNode(place(box, at: o.center, rotation: o.rotation, bottom: o.bottom, height: o.height))
            }
        }

        if showLayout {
            for i in layout {
                let h = max(i.height, 0.01)
                let box = SCNBox(width: i.width, height: h, length: i.depth, chamferRadius: min(0.03, h / 3))
                box.firstMaterial = mat(UIColor(Names.color(i.category)).withAlphaComponent(0.9))
                let node = place(box, at: i.center, rotation: i.rotation, bottom: 0, height: h)
                node.name = i.name
                root.addChildNode(node)
            }
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 450
        root.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 700
        sun.light!.castsShadow = true
        sun.eulerAngles = SCNVector3(-1.0, 0.6, 0)
        root.addChildNode(sun)

        let b = plan.bounds
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 55
        let span = max(b.width, b.height)
        cam.position = SCNVector3(b.midX + span * 0.15, span * 1.5 + 1.5, b.maxY + span * 0.55)
        cam.look(at: SCNVector3(b.midX, 0, b.midY))
        root.addChildNode(cam)
        return scene
    }

    private static func mat(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.8
        if c.cgColor.alpha < 1 { m.transparencyMode = .dualLayer }
        return m
    }

    private static func place(_ g: SCNGeometry, at c: P2, along d: P2, bottom: Double, height: Double) -> SCNNode {
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(c.x, bottom + height / 2, c.y)
        n.eulerAngles.y = Float(atan2(-d.y, d.x))
        return n
    }

    private static func place(_ g: SCNGeometry, at c: P2, rotation: Double, bottom: Double, height: Double) -> SCNNode {
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(c.x, bottom + height / 2, c.y)
        n.eulerAngles.y = Float(-rotation * .pi / 180)
        return n
    }
}

struct SceneHost: UIViewRepresentable {
    var scene: SCNScene
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .systemGroupedBackground
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.scene = scene
        return v
    }
    func updateUIView(_ v: SCNView, context: Context) {
        if v.scene !== scene { v.scene = scene }
    }
}

struct Room3DView: View {
    var record: ScanRecord
    @Environment(ScanStore.self) private var store
    @State private var showDetected = true
    @State private var showLayout = true
    @State private var lowWalls = false
    @State private var quickLook: URL?
    @State private var scene: SCNScene?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let scene { SceneHost(scene: scene).ignoresSafeArea(edges: .bottom) }
            HStack {
                Toggle("Nízké stěny", isOn: $lowWalls).toggleStyle(.button)
                Toggle("Nábytek", isOn: $showDetected).toggleStyle(.button)
                Toggle("Rozvržení", isOn: $showLayout).toggleStyle(.button)
            }
            .font(.footnote)
            .padding(8).background(.ultraThinMaterial, in: Capsule()).padding()
        }
        .toolbar {
            if FileManager.default.fileExists(atPath: store.modelURL(record.id).path) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { quickLook = store.modelURL(record.id) } label: { Label("AR", systemImage: "arkit") }
                }
            }
        }
        .quickLookPreview($quickLook)
        .onAppear(perform: rebuild)
        .onChange(of: [showDetected, showLayout, lowWalls]) { rebuild() }
        .onChange(of: record.layout) { rebuild() }
    }

    private func rebuild() {
        scene = RoomScene.make(plan: record.plan, layout: record.layout, showDetected: showDetected,
                               showLayout: showLayout, lowWalls: lowWalls)
    }
}
