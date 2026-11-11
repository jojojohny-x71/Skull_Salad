// Splits each colour class (from classify.swift's .bin output) into connected regions and reports them,
// with a colour-coded map labelled by region id, so each region can be assigned to a layer.
// usage: regions classes.png.bin W H out.png
import AppKit

let a = CommandLine.arguments
let cls = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: a[1])))
let W = Int(a[2])!, H = Int(a[3])!
let names = ["bg", "light", "pink", "teeth", "dark", "green", "blue"]
var comp = [Int32](repeating: -1, count: W * H)
struct R { var id: Int; var cls: Int; var n = 0; var x0 = Int.max, y0 = Int.max, x1 = 0, y1 = 0, sx = 0, sy = 0 }
var regions: [R] = []
var stack: [Int] = []
for start in 0..<(W * H) where comp[start] < 0 && cls[start] != 0 {
    let c = cls[start], id = regions.count
    var r = R(id: id, cls: Int(c))
    stack.append(start); comp[start] = Int32(id)
    while let i = stack.popLast() {
        let x = i % W, y = i / W
        r.n += 1; r.x0 = min(r.x0, x); r.y0 = min(r.y0, y); r.x1 = max(r.x1, x); r.y1 = max(r.y1, y); r.sx += x; r.sy += y
        for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && comp[j] < 0 && cls[j] == c {
            comp[j] = Int32(id); stack.append(j)
        }
    }
    regions.append(r)
}
try! Data(bytes: comp, count: comp.count * 4).write(to: URL(fileURLWithPath: a[4] + ".comp"))
let big = regions.filter { $0.n >= 400 }.sorted { $0.n > $1.n }
print("regions:", regions.count, "with ≥400 px:", big.count)
for r in big { print(String(format: "#%-5d %-6@ n=%-7d bbox=(%d,%d)-(%d,%d) centroid=(%d,%d)", r.id, names[r.cls] as NSString, r.n, r.x0, r.y0, r.x1, r.y1, r.sx / r.n, r.sy / r.n)) }

// Map: each big region a distinct tint of its class colour, small regions grey, labels at centroids.
let base: [(Double, Double, Double)] = [(1, 1, 1), (1, 0.85, 0.3), (0.95, 0.3, 0.8), (1, 0.75, 0.9), (0.2, 0.1, 0.4), (0.15, 0.75, 0.35), (0.3, 0.35, 0.95)]
var tint = [Int: (Double, Double, Double)]()
for (k, r) in big.enumerated() { let b = base[r.cls], f = 0.55 + 0.45 * Double((k * 7919) % 10) / 10; tint[r.id] = (b.0 * f, b.1 * f, b.2 * f) }
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: W * 3, bitsPerPixel: 24)!
let d = out.bitmapData!
for i in 0..<(W * H) {
    let c = comp[i] < 0 ? (1.0, 1.0, 1.0) : (tint[Int(comp[i])] ?? (0.6, 0.6, 0.6))
    d[i*3] = UInt8(c.0 * 255); d[i*3+1] = UInt8(c.1 * 255); d[i*3+2] = UInt8(c.2 * 255)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .heavy), .foregroundColor: NSColor.black, .backgroundColor: NSColor(white: 1, alpha: 0.8)]
for r in big where r.n >= 1500 { NSString(string: "\(r.id)").draw(at: NSPoint(x: r.sx / r.n - 12, y: H - r.sy / r.n - 12), withAttributes: attrs) }
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[4]))
