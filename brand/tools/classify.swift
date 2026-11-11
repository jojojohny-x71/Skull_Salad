// Classifies every pixel of the logo (background, skull pink, teeth, dark shadow, green, blue) and writes
// a colour-coded class map, so layer outlines can be traced from the image itself.
// usage: classify source.png classes.png
import AppKit

let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: FileManager.default.contents(atPath: args[1])!)!
let W = rep.pixelsWide, H = rep.pixelsHigh
var px = [UInt8](repeating: 0, count: W * H * 4)
var p = [Int](repeating: 0, count: 4)
for y in 0..<H { for x in 0..<W { rep.getPixel(&p, atX: x, y: y); let i = (y * W + x) * 4; px[i] = UInt8(p[0]); px[i+1] = UInt8(p[1]); px[i+2] = UInt8(p[2]); px[i+3] = UInt8(p[3]) } }

enum C: UInt8 { case bg = 0, light, pink, teeth, dark, green, blue }
func hsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
    let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
    if d < 1e-6 { return (0, 0, l) }
    let s = d / (1 - abs(2 * l - 1))
    var h: Double
    if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
    h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    return (h, s, l)
}
var cls = [C](repeating: .bg, count: W * H)
for i in 0..<(W * H) {
    let r = Double(px[i*4]) / 255, g = Double(px[i*4+1]) / 255, b = Double(px[i*4+2]) / 255, a = Double(px[i*4+3]) / 255
    let (h, s, l) = hsl(r, g, b)
    var c: C
    if a < 0.5 || (l > 0.93 && s < 0.5) || (l > 0.97) { c = .light }
    else if l < 0.22 { c = .dark }
    else if h >= 85 && h < 175 { c = .green }
    else if h >= 205 && h < 262 { c = .blue }
    else if (h >= 262 || h < 20) && l > 0.8 && s > 0.3 { c = .teeth }
    else if h >= 262 || h < 20 { c = .pink }
    else { c = .light }
    cls[i] = c
}
// Light pixels connected to the image border are background; enclosed light pixels are highlights.
var stack: [Int] = []
var isBg = [Bool](repeating: false, count: W * H)
for x in 0..<W { stack.append(x); stack.append((H - 1) * W + x) }
for y in 0..<H { stack.append(y * W); stack.append(y * W + W - 1) }
while let i = stack.popLast() {
    if isBg[i] || cls[i] != .light { continue }
    isBg[i] = true
    let x = i % W, y = i / W
    if x > 0 { stack.append(i - 1) }; if x < W - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - W) }; if y < H - 1 { stack.append(i + W) }
}
for i in 0..<(W * H) where isBg[i] { cls[i] = .bg }

// Colour-coded map for viewing.
let colors: [C: (UInt8, UInt8, UInt8)] = [.bg: (255, 255, 255), .light: (255, 230, 120), .pink: (240, 80, 200), .teeth: (255, 190, 230), .dark: (40, 20, 90), .green: (40, 200, 90), .blue: (70, 90, 240)]
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: W * 3, bitsPerPixel: 24)!
let d = out.bitmapData!
var counts: [C: Int] = [:]
for i in 0..<(W * H) { let (r, g, b) = colors[cls[i]]!; d[i*3] = r; d[i*3+1] = g; d[i*3+2] = b; counts[cls[i], default: 0] += 1 }
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
// Raw class bytes for later tools.
try! Data(cls.map { $0.rawValue }).write(to: URL(fileURLWithPath: args[2] + ".bin"))
print("size", W, H, counts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
