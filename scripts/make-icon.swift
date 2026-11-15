// Draws the 1024 px app icon: a floor plan with a dimension line on a blue background.
// Run: swift scripts/make-icon.swift Pudorys/Assets.xcassets/AppIcon.appiconset/icon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let n = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let grad = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.10, green: 0.36, blue: 0.85, alpha: 1),
                                               CGColor(srgbRed: 0.05, green: 0.18, blue: 0.50, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: n), end: CGPoint(x: n, y: 0), options: [])
// Floor fill
let room: [CGPoint] = [(230, 230), (800, 230), (800, 560), (640, 560), (640, 800), (230, 800)].map { CGPoint(x: $0.0, y: $0.1) }
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
ctx.addLines(between: room); ctx.closePath(); ctx.fillPath()
// Walls with a door gap
ctx.setStrokeColor(.white)
ctx.setLineWidth(44)
ctx.setLineCap(.square)
ctx.setLineJoin(.miter)
ctx.addLines(between: [CGPoint(x: 420, y: 230), CGPoint(x: 230, y: 230), CGPoint(x: 230, y: 800), CGPoint(x: 640, y: 800),
                       CGPoint(x: 640, y: 560), CGPoint(x: 800, y: 560), CGPoint(x: 800, y: 230), CGPoint(x: 620, y: 230)])
ctx.strokePath()
// Door swing
ctx.setLineWidth(10)
ctx.move(to: CGPoint(x: 420, y: 230)); ctx.addLine(to: CGPoint(x: 420, y: 430)); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [18, 14])
ctx.addArc(center: CGPoint(x: 420, y: 230), radius: 200, startAngle: .pi / 2, endAngle: 0, clockwise: true)
ctx.strokePath()
// Dimension line
ctx.setLineDash(phase: 0, lengths: [])
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.78, blue: 0.25, alpha: 1))
ctx.setLineWidth(12)
ctx.move(to: CGPoint(x: 230, y: 900)); ctx.addLine(to: CGPoint(x: 640, y: 900))
for x in [230.0, 640.0] { ctx.move(to: CGPoint(x: x, y: 865)); ctx.addLine(to: CGPoint(x: x, y: 935)) }
ctx.strokePath()
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
