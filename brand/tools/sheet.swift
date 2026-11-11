// Contact sheet: every layer of layers.json on a checkerboard (so hidden fills and edges are visible),
// with its name, in a grid. usage: sheet layersDir out.png [cellSize]
import AppKit

let a = CommandLine.arguments
let dir = URL(fileURLWithPath: a[1])
let cell = a.count > 3 ? Int(a[3])! : 420
let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("layers.json"))) as! [String: Any]
let layers = manifest["layers"] as! [[String: Any]]
let cols = 3, rows = (layers.count + cols - 1) / cols, label = 26
let W = cols * cell, H = rows * (cell + label)
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (k, layer) in layers.enumerated() {
    let cx = (k % cols) * cell, top = (k / cols) * (cell + label)
    let y = H - top - label - cell
    for ty in 0..<(cell / 14 + 1) { for tx in 0..<(cell / 14 + 1) where (tx + ty) % 2 == 0 {
        NSColor(white: 0.86, alpha: 1).setFill()
        NSRect(x: cx + tx * 14, y: y + ty * 14, width: 14, height: 14).intersection(NSRect(x: cx, y: y, width: cell, height: cell)).fill()
    } }
    if let img = NSImage(contentsOf: dir.appendingPathComponent(layer["file"] as! String)) {
        img.draw(in: NSRect(x: cx + 4, y: y + 4, width: cell - 8, height: cell - 8))
    }
    NSString(string: "\(layer["order"]!). \(layer["name"]!)").draw(at: NSPoint(x: cx + 8, y: H - top - label + 5),
        withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.black])
}
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
