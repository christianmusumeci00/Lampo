// Renders Lampo's app icon (Assets.xcassets/AppIcon.appiconset) with Core Graphics.
// The bolt is drawn by hand: SF Symbols may not be used in app icons.
//   swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: "Lampo/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    // Core Graphics is y-up; the drawing below uses y-down coordinates.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 × 824 body, 100 pt margin, continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x2F6FDE))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x5B95F2), color(0x2F6FDE), color(0x1D4CB0)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 300, y: 100), end: CGPoint(x: 724, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft glow behind the bolt.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 520, y: 500), startRadius: 0,
                           endCenter: CGPoint(x: 520, y: 500), endRadius: 380, options: [])
    ctx.restoreGState()

    // The bolt.
    let bolt = CGMutablePath()
    bolt.addLines(between: [
        CGPoint(x: 598, y: 196), CGPoint(x: 352, y: 566), CGPoint(x: 498, y: 566), CGPoint(x: 424, y: 852),
        CGPoint(x: 690, y: 438), CGPoint(x: 544, y: 438), CGPoint(x: 712, y: 196),
    ])
    bolt.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: color(0x0B2A6B, 0.45))
    ctx.addPath(bolt)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bolt)
    ctx.clip()
    let shine = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xFFF4C8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 600, y: 196), end: CGPoint(x: 430, y: 852), options: [])
    ctx.restoreGState()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")
