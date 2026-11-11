// Builds AppIcon.iconset from the logo: the logo centred on a black rounded square that follows the
// macOS icon grid (824 pt body inside a 1024 canvas). Usage: swift make-icon.swift logo.png out.iconset
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift logo.png out.iconset\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k)
    NSGradient(colors: [NSColor(white: 0.12, alpha: 1), NSColor(white: 0.02, alpha: 1)])!.draw(in: shape, angle: -90)
    // The canvas dot grid, faintly, so the icon reads as the app.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSColor(white: 0.63, alpha: 0.22).setFill()
    let step = 40 * k, dot = max(1, 6 * k)
    var y = body.minY + step / 2
    while y < body.maxY { var x = body.minX + step / 2; while x < body.maxX { NSRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot).fill(); x += step }; y += step }
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: 0.12).setStroke()
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * k, dy: 1.5 * k), xRadius: 184 * k, yRadius: 184 * k)
    edge.lineWidth = 3 * k
    edge.stroke()
    let art = NSRect(x: 168 * k, y: 150 * k, width: 688 * k, height: 688 * k)
    logo.draw(in: art, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
