import SwiftUI

enum PlanSelection: Hashable {
    case none, wall(String), opening(String), object(String), item(String), photo(String)
}

struct PlanLayers: Hashable {
    var dimensions = true
    var detected = true
    var layout = true
    var photos = true
    var grid = true
}

/// Converts between plan metres and view points.
struct PlanMapper {
    var size: CGSize
    var bounds: CGRect
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var padding: CGFloat = 0.7

    var scale: CGFloat {
        let b = bounds.insetBy(dx: -padding, dy: -padding)
        return min(size.width / max(b.width, 0.1), size.height / max(b.height, 0.1)) * zoom
    }

    func pt(_ p: P2) -> CGPoint {
        CGPoint(x: size.width / 2 + pan.width + (p.x - bounds.midX) * scale,
                y: size.height / 2 + pan.height + (p.y - bounds.midY) * scale)
    }

    func plan(_ q: CGPoint) -> P2 {
        P2(x: (q.x - size.width / 2 - pan.width) / scale + bounds.midX,
           y: (q.y - size.height / 2 - pan.height) / scale + bounds.midY)
    }
}

/// Everything drawn on the floor plan. Used by the interactive view and by the PNG/PDF export.
struct PlanDrawing {
    var plan: PlanModel
    var layout: [LayoutItem]
    var photos: [PhotoRecord]
    var layers: PlanLayers
    var selection: PlanSelection = .none
    var measure: [P2] = []
    var issues: [String: [LayoutIssue]] = [:]
    var dark = false

    var ink: Color { dark ? .white : Color(white: 0.12) }
    var paper: Color { dark ? Color(white: 0.08) : .white }

    func draw(_ ctx: inout GraphicsContext, _ m: PlanMapper) {
        let s = m.scale
        ctx.fill(Path(CGRect(origin: .zero, size: m.size)), with: .color(paper))

        if layers.grid {
            var grid = Path()
            let tl = m.plan(.zero), br = m.plan(CGPoint(x: m.size.width, y: m.size.height))
            let step = s > 60 ? 0.5 : 1.0
            var x = (tl.x / step).rounded(.down) * step
            while x <= br.x { grid.move(to: m.pt(P2(x: x, y: tl.y))); grid.addLine(to: m.pt(P2(x: x, y: br.y))); x += step }
            var y = (tl.y / step).rounded(.down) * step
            while y <= br.y { grid.move(to: m.pt(P2(x: tl.x, y: y))); grid.addLine(to: m.pt(P2(x: br.x, y: y))); y += step }
            ctx.stroke(grid, with: .color(ink.opacity(0.06)), lineWidth: 0.5)
        }

        // Floor
        if plan.outline.count > 2 {
            var floor = Path()
            floor.addLines(plan.outline.map(m.pt))
            floor.closeSubpath()
            ctx.fill(floor, with: .color(Color(red: 0.93, green: 0.89, blue: 0.82).opacity(dark ? 0.15 : 0.6)))
        }

        // Detected furniture
        if layers.detected {
            for o in plan.objects {
                let sel = selection == .object(o.id)
                let path = poly(o.corners(), m)
                ctx.fill(path, with: .color(ink.opacity(0.08)))
                ctx.stroke(path, with: .color(ink.opacity(sel ? 0.9 : 0.45)),
                           style: StrokeStyle(lineWidth: sel ? 2 : 1, dash: [4, 3]))
                label(&ctx, Names.category(o.category), at: m.pt(o.center), size: 10, color: ink.opacity(0.55))
            }
        }

        // Walls
        let wallWidth = max(3, 0.12 * s)
        for w in plan.walls {
            var p = Path(); p.move(to: m.pt(w.a)); p.addLine(to: m.pt(w.b))
            let sel = selection == .wall(w.id)
            ctx.stroke(p, with: .color(sel ? .accentColor : ink), style: StrokeStyle(lineWidth: wallWidth, lineCap: .square))
        }

        // Doors, windows, openings
        let centre = Geometry.centroid(plan.outline)
        for o in plan.openings {
            var gap = Path(); gap.move(to: m.pt(o.a)); gap.addLine(to: m.pt(o.b))
            ctx.stroke(gap, with: .color(paper), style: StrokeStyle(lineWidth: wallWidth + 1, lineCap: .butt))
            let sel = selection == .opening(o.id)
            let col: Color = sel ? .accentColor : ink
            switch o.kind {
            case .window:
                let n = P2(x: -o.direction.y, y: o.direction.x) * 0.04
                for k in [-1.0, 0, 1] {
                    var l = Path(); l.move(to: m.pt(o.a + n * k)); l.addLine(to: m.pt(o.b + n * k))
                    ctx.stroke(l, with: .color(k == 0 ? Color.blue.opacity(0.7) : col), lineWidth: 1)
                }
            case .door:
                var n = P2(x: -o.direction.y, y: o.direction.x)
                if (centre - o.center).dot(n) < 0 { n = n * -1 }
                let hinge = o.a, tip = o.a + n * o.width
                var leaf = Path(); leaf.move(to: m.pt(hinge)); leaf.addLine(to: m.pt(tip))
                ctx.stroke(leaf, with: .color(col), lineWidth: 1.5)
                var arc = Path()
                let steps = 16
                for i in 0...steps {
                    let t = Double(i) / Double(steps) * .pi / 2
                    let v = o.direction * cos(t) + n * sin(t)
                    let q = m.pt(hinge + v * o.width)
                    if i == 0 { arc.move(to: q) } else { arc.addLine(to: q) }
                }
                ctx.stroke(arc, with: .color(col.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            case .opening:
                for q in [o.a, o.b] {
                    let n = P2(x: -o.direction.y, y: o.direction.x) * 0.08
                    var l = Path(); l.move(to: m.pt(q - n)); l.addLine(to: m.pt(q + n))
                    ctx.stroke(l, with: .color(col), lineWidth: 1.5)
                }
            }
        }

        // Wall dimensions
        if layers.dimensions {
            for w in plan.walls where w.length > 0.25 {
                let d = (w.b - w.a).normalized
                var n = P2(x: -d.y, y: d.x)
                if (centre - w.mid).dot(n) > 0 { n = n * -1 }
                let off = Double(wallWidth / s) / 2 + 16 / Double(s)
                let a = w.a + n * off, b = w.b + n * off
                var line = Path(); line.move(to: m.pt(a)); line.addLine(to: m.pt(b))
                for q in [a, b] {
                    line.move(to: m.pt(q - n * (6 / Double(s)))); line.addLine(to: m.pt(q + n * (6 / Double(s))))
                }
                ctx.stroke(line, with: .color(ink.opacity(0.55)), lineWidth: 0.7)
                var ang = atan2(d.y, d.x)
                if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
                label(&ctx, Fmt.short(w.length), at: m.pt(w.mid + n * off), size: 11, color: ink,
                      angle: ang, pill: true, bold: true)
            }
        }

        // Planned layout
        if layers.layout {
            for item in layout.sorted(by: { LayoutCheck.isFlat($0) && !LayoutCheck.isFlat($1) }) {
                let sel = selection == .item(item.id)
                let bad = issues[item.id] != nil
                let base = Names.color(item.category)
                let path = poly(item.corners(), m)
                ctx.fill(path, with: .color(base.opacity(sel ? 0.4 : 0.25)))
                ctx.stroke(path, with: .color(bad ? .red : base), lineWidth: sel ? 3 : 1.5)
                // Front edge marker
                let c = item.corners()
                var front = Path(); front.move(to: m.pt(c[2])); front.addLine(to: m.pt(c[3]))
                ctx.stroke(front, with: .color(base), lineWidth: sel ? 5 : 3)
                let fs = min(12, max(8, CGFloat(min(item.width, item.depth)) * s / 5))
                // Rugs usually lie under other pieces: name them only when selected.
                if sel || !LayoutCheck.isFlat(item) {
                    label(&ctx, item.name, at: m.pt(item.center), size: fs, color: ink, bold: true)
                }
                if sel {
                    label(&ctx, "\(Fmt.short(item.width))×\(Fmt.short(item.depth))",
                          at: m.pt(item.center) + CGSize(width: 0, height: fs + 3), size: fs - 1, color: ink.opacity(0.7))
                }
            }
        }

        // Photos
        if layers.photos {
            for p in photos {
                guard let pos = p.position else { continue }
                let c = m.pt(pos)
                if let h = p.heading {
                    let r = h * .pi / 180
                    var cone = Path()
                    cone.move(to: c)
                    cone.addLine(to: c + CGSize(width: cos(r - 0.4) * 34, height: sin(r - 0.4) * 34))
                    cone.addLine(to: c + CGSize(width: cos(r + 0.4) * 34, height: sin(r + 0.4) * 34))
                    cone.closeSubpath()
                    ctx.fill(cone, with: .color(Color.orange.opacity(0.25)))
                }
                let sel = selection == .photo(p.id)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                         with: .color(sel ? .accentColor : .orange))
                ctx.draw(Image(systemName: "camera.fill"), in: CGRect(x: c.x - 6, y: c.y - 5, width: 12, height: 10))
            }
        }

        // Measuring tape
        if !measure.isEmpty {
            var p = Path()
            p.addLines(measure.map(m.pt))
            ctx.stroke(p, with: .color(.red), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            for q in measure {
                let c = m.pt(q)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.red))
            }
            if measure.count == 2 {
                let d = measure[1] - measure[0]
                var ang = atan2(d.y, d.x)
                if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
                label(&ctx, Fmt.m(d.length), at: m.pt((measure[0] + measure[1]) * 0.5) + CGSize(width: 0, height: -12),
                      size: 13, color: .red, angle: ang, pill: true, bold: true)
            }
        }

        // Scale bar
        let bar = CGRect(x: 16, y: m.size.height - 28, width: s, height: 4)
        if bar.width < m.size.width - 40 {
            ctx.fill(Path(bar), with: .color(ink))
            label(&ctx, "1 m · rozměry v cm", at: CGPoint(x: bar.minX, y: bar.minY - 10), size: 10, color: ink, anchor: .leading)
        }
    }

    private func poly(_ pts: [P2], _ m: PlanMapper) -> Path {
        var p = Path(); p.addLines(pts.map(m.pt)); p.closeSubpath(); return p
    }

    private func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat, color: Color,
                       angle: Double = 0, pill: Bool = false, bold: Bool = false, anchor: UnitPoint = .center) {
        let text = Text(s).font(.system(size: size, weight: bold ? .semibold : .regular)).foregroundColor(color)
        ctx.drawLayer { c in
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(angle))
            if pill {
                let r = c.resolve(text).measure(in: CGSize(width: 400, height: 100))
                let rect = CGRect(x: -r.width / 2 - 4, y: -r.height / 2 - 1, width: r.width + 8, height: r.height + 2)
                c.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(paper.opacity(0.9)))
            }
            c.draw(text, at: .zero, anchor: anchor)
        }
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGSize) -> CGPoint { CGPoint(x: a.x + b.width, y: a.y + b.height) }
}
