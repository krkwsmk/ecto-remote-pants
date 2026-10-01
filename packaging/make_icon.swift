// Renders a 1024x1024 cyberpunk app icon PNG using CoreGraphics only.
// Usage: swift make_icon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let W = CGFloat(size)
let neonCyan = color(0.098, 0.941, 1.0)
let neonMag = color(1.0, 0.18, 0.59)
let neonPurple = color(0.61, 0.36, 1.0)

// Background gradient
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.02, 0.03, 0.06), color(0.05, 0.02, 0.10)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: W), end: CGPoint(x: W, y: 0), options: [])

// Rounded panel inset
let inset: CGFloat = 70
let rect = CGRect(x: inset, y: inset, width: W - inset * 2, height: W - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 150, cornerHeight: 150, transform: nil)
ctx.addPath(path)
ctx.setFillColor(color(0.04, 0.06, 0.10))
ctx.fillPath()

// Neon border
ctx.addPath(path)
ctx.setStrokeColor(neonCyan)
ctx.setLineWidth(14)
ctx.setShadow(offset: .zero, blur: 40, color: neonCyan.copy(alpha: 0.9))
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Scanlines
ctx.setFillColor(color(1, 1, 1, 0.025))
var y: CGFloat = inset
while y < W - inset {
    ctx.fill(CGRect(x: inset, y: y, width: W - inset * 2, height: 3))
    y += 10
}

// Lightning bolt (reverse-tunnel energy) centered
func bolt(offset: CGFloat, stroke: CGColor, width: CGFloat) {
    let pts = [
        CGPoint(x: 560, y: 790), CGPoint(x: 420, y: 520),
        CGPoint(x: 520, y: 520), CGPoint(x: 440, y: 250),
        CGPoint(x: 640, y: 560), CGPoint(x: 530, y: 560),
        CGPoint(x: 600, y: 790)
    ].map { CGPoint(x: $0.x + offset, y: $0.y) }
    let p = CGMutablePath()
    p.move(to: pts[0])
    for pt in pts.dropFirst() { p.addLine(to: pt) }
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(stroke)
    ctx.setShadow(offset: .zero, blur: 50, color: stroke.copy(alpha: 0.8))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}
bolt(offset: 8, stroke: neonMag.copy(alpha: 0.5)!, width: 0)
bolt(offset: 0, stroke: neonCyan, width: 0)

// Chevrons >> at bottom
func chevron(x: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: 360))
    p.addLine(to: CGPoint(x: x + 70, y: 320))
    p.addLine(to: CGPoint(x: x, y: 280))
    ctx.addPath(p)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}
chevron(x: 395, color: neonPurple)
chevron(x: 475, color: neonCyan)

guard let image = ctx.makeImage() else { fatalError("image") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) { fatalError("write") }
print("wrote \(outPath)")
