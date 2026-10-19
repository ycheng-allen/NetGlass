import AppKit
import CoreGraphics

// Replicates LogoView: dark rounded tile + 4-color radial pinwheel circle + white highlight arc.
func drawIcon(_ px: Int) -> CGImage {
    let S = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    // dark tile (matches app background)
    let tileInset = S * 0.06
    let tileRect = CGRect(x: tileInset, y: tileInset, width: S - tileInset * 2, height: S - tileInset * 2)
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: S * 0.185, cornerHeight: S * 0.185, transform: nil)
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x0D1218))
    ctx.fillPath()
    ctx.addPath(tilePath)
    ctx.setStrokeColor(color(0x22303F))
    ctx.setLineWidth(S * 0.008)
    ctx.strokePath()

    // logo circle (frame = d, centered)
    let d = S * 0.62
    let frame = CGRect(x: (S - d) / 2, y: (S - d) / 2, width: d, height: d)
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let radius = d / 2

    // radial gradient: SwiftUI RadialGradient places colors evenly at 0, 1/3, 2/3, 1
    let grad = CGGradient(colorsSpace: space,
                          colors: [color(0x35E0CF), color(0x18A8D8), color(0xF26FA0), color(0xF5C542)] as CFArray,
                          locations: [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0])!
    // SwiftUI center (0.3, 0.25) from top-left → CG y-up (0.3, 0.75)
    let gCenter = CGPoint(x: frame.minX + 0.3 * d, y: frame.minY + 0.75 * d)
    let gRadius = d

    ctx.saveGState()
    ctx.addPath(CGPath(ellipseIn: frame, transform: nil))
    ctx.clip()
    ctx.drawRadialGradient(grad, startCenter: gCenter, startRadius: 0,
                           endCenter: gCenter, endRadius: gRadius,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // gray ring
    ctx.setStrokeColor(color(0x5A6B7D))
    ctx.setLineWidth(d * 0.07)
    ctx.strokeEllipse(in: frame)

    // white highlight arc: trim 0→0.28 rotated -70°, round caps
    let arcR = radius - d * 0.18
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(d * 0.12)
    ctx.setLineCap(.round)
    // SwiftUI screen-clockwise from -70°, span 0.28*360 ≈ 100.8° → CG y-up: 70° → -30.8°, decreasing = clockwise:true
    ctx.addArc(center: center, radius: arcR,
               startAngle: .pi * 70.0 / 180.0,
               endAngle: -.pi * 30.8 / 180.0,
               clockwise: true)
    ctx.strokePath()

    return ctx.makeImage()!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let img = drawIcon(px)
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: px, height: px)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name).png")
}
