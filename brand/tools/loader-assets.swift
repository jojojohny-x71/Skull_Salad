// Lightweight images for the loader: each layer cropped to its own pixels (hidden fills included) and scaled down
// to a small canvas, plus a flattened mark for tiny sizes. Prints each layer's rect as a percentage of the canvas,
// ready to paste into loader/skull-loader.js.
// usage: loader-assets logoDir outDir [canvas]
import AppKit

let a = CommandLine.arguments
let logo = URL(fileURLWithPath: a[1]), out = URL(fileURLWithPath: a[2])
let canvas = a.count > 3 ? Int(a[3])! : 640
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue

func load(_ url: URL) -> CGImage { NSBitmapImageRep(data: try! Data(contentsOf: url))!.cgImage! }

func write(_ img: CGImage, _ name: String) -> Int {
    let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try! data.write(to: out.appendingPathComponent(name))
    return data.count
}

/// Bounding box of every pixel with any alpha, in source pixels: x0, y0, x1, y1 (inclusive).
func alphaBox(_ img: CGImage) -> (Int, Int, Int, Int) {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb, bitmapInfo: info)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 0 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    return (x0, y0, x1, y1)
}

/// The part of `img` (scaled to the canvas) inside the canvas rect, as its own image.
func crop(_ img: CGImage, _ r: (Int, Int, Int, Int)) -> CGImage {
    let (dx0, dy0, dx1, dy1) = r
    let ctx = CGContext(data: nil, width: dx1 - dx0, height: dy1 - dy0, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: -dx0, y: -(canvas - dy1), width: canvas, height: canvas))
    return ctx.makeImage()!
}

let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: logo.appendingPathComponent("layers/layers.json"))) as! [String: Any]
let size = Double(manifest["width"] as? Int ?? 1593)
let s = Double(canvas) / size
let pct = { (v: Int) in String(format: "%.3f", Double(v) / Double(canvas) * 100) }
var total = 0
for layer in manifest["layers"] as! [[String: Any]] {
    let file = layer["file"] as! String
    let img = load(logo.appendingPathComponent("layers/\(file)"))
    let (x0, y0, x1, y1) = alphaBox(img)
    let r = (max(0, Int((Double(x0) * s).rounded(.down)) - 1), max(0, Int((Double(y0) * s).rounded(.down)) - 1),
             min(canvas, Int((Double(x1 + 1) * s).rounded(.up)) + 1), min(canvas, Int((Double(y1 + 1) * s).rounded(.up)) + 1))
    let bytes = write(crop(img, r), file)
    total += bytes
    print("\(file): rect [\(pct(r.0)), \(pct(r.1)), \(pct(r.2 - r.0)), \(pct(r.3 - r.1))]  \(r.2 - r.0)×\(r.3 - r.1)  \(bytes / 1024) KB")
}
let mark = crop(load(logo.appendingPathComponent("source.png")), (0, 0, canvas, canvas))
let small = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)!
small.interpolationQuality = .high
small.draw(mark, in: CGRect(x: 0, y: 0, width: 128, height: 128))
total += write(small.makeImage()!, "mark-128.png")
print("total \(total / 1024) KB")
