// Cuts the logo into depth layers for 2.5D animation.
//  1. Every pixel goes to one layer: regions already identified are assigned directly; the rest is split by a
//     seeded watershed over the image's colour edges, constrained by colour class.
//  2. The source's own alpha is kept (its soft outer edge), so no halo shows when layers move apart.
//  3. Each layer continues up to 48 px underneath whatever covers it, or to its full outline (the skull's
//     cranium, the bowl's opening), filled by pulling in its own colours, so parallax never reveals holes.
//  4. The layers are stacked back over white and compared with the source over white.
// usage: cutlayers source.png classes.bin regions.comp outDir
import AppKit

let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: FileManager.default.contents(atPath: args[1])!)!
let W = rep.pixelsWide, H = rep.pixelsHigh, N = W * H
let cls = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: args[2])))
let compData = try! Data(contentsOf: URL(fileURLWithPath: args[3]))
let comp: [Int32] = compData.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }
let outDir = URL(fileURLWithPath: args[4])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var src = [Double](repeating: 0, count: N * 3)
var srcA = [Double](repeating: 0, count: N)
var pxl = [Int](repeating: 0, count: 4)
for y in 0..<H { for x in 0..<W {
    rep.getPixel(&pxl, atX: x, y: y); let i = y * W + x
    src[i*3] = Double(pxl[0]); src[i*3+1] = Double(pxl[1]); src[i*3+2] = Double(pxl[2]); srcA[i] = Double(pxl[3]) / 255
} }

// MARK: - Layers, back to front

enum CL: UInt8 { case bg = 0, light, pink, teeth, dark, green, blue }
struct Layer { let name: String; let depth: Double; let points: [(Int, Int)]; let regions: [Int32] }
let layers: [Layer] = [
    Layer(name: "bowl-back", depth: -1.0,
          points: [(250, 1040), (232, 1005), (275, 1075), (1300, 735), (1360, 790)],
          regions: [284, 756, 692, 428, 395, 1078]),
    Layer(name: "leaf-back-right", depth: -0.7,
          points: [(1150, 330), (1200, 420), (1300, 420), (1400, 470), (1250, 540), (1340, 520), (1100, 470), (1060, 400)],
          regions: [140, 68]),
    Layer(name: "leaf-mid-right", depth: -0.5,
          points: [(1200, 700), (1300, 640), (1400, 600), (1470, 562), (1180, 742), (1250, 690), (1160, 760)],
          regions: [219]),
    Layer(name: "leaf-back-left", depth: -0.45,
          points: [(150, 700), (200, 650), (120, 760), (250, 640), (230, 700)],
          regions: [340]),
    Layer(name: "skull", depth: 0,
          points: [(500, 400), (700, 330), (900, 450), (400, 650), (800, 700), (600, 760), (1050, 640), (450, 800), (722, 830), (680, 840)],
          regions: [2, 194, 98, 290, 22, 25, 54, 224, 315, 316, 230, 550, 572, 517, 440, 589]),
    Layer(name: "leaf-left-band", depth: 0.3,
          points: [(120, 830), (200, 830), (300, 845), (380, 885), (250, 900), (300, 960), (330, 1040), (345, 1080)],
          regions: [568]),
    Layer(name: "leaf-front-right", depth: 0.45,
          points: [(800, 1010), (900, 935), (1000, 885), (1100, 835), (1200, 795), (1290, 795), (1050, 950), (950, 990)],
          regions: [525, 828]),
    Layer(name: "bowl-front", depth: 0.6,
          points: [(800, 1300), (400, 1250), (1100, 1250), (200, 1150), (700, 1400), (1430, 900), (1000, 1350), (1200, 1150)],
          regions: [488, 641, 1029, 1053, 988]),
    Layer(name: "leaf-front-left", depth: 0.85,
          points: [(330, 1120), (400, 1000), (480, 950), (560, 925), (650, 935), (720, 965), (500, 1050), (700, 1020), (600, 1060), (420, 1100)],
          regions: [860, 1041]),
]
let L = layers.count
let idx = Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($1.name, $0) })
func allowed(_ c: UInt8, _ l: Int) -> Bool {
    let name = layers[l].name
    switch CL(rawValue: c)! {
    case .bg: return false
    case .pink, .teeth: return name == "skull" || name.hasPrefix("bowl")
    case .green: return name.hasPrefix("leaf") || name == "bowl-front"
    case .blue: return name.hasPrefix("bowl")
    case .dark, .light: return true
    }
}

// MARK: - Watershed

var label = [Int8](repeating: -1, count: N)
var elev = [UInt8](repeating: 0, count: N)
for y in 1..<(H - 1) { for x in 1..<(W - 1) {
    let i = y * W + x
    var m = 0.0
    for c in 0..<3 {
        func v(_ dx: Int, _ dy: Int) -> Double { src[((y + dy) * W + x + dx) * 3 + c] }
        let gx = (v(1, -1) + 2 * v(1, 0) + v(1, 1)) - (v(-1, -1) + 2 * v(-1, 0) + v(-1, 1))
        let gy = (v(-1, 1) + 2 * v(0, 1) + v(1, 1)) - (v(-1, -1) + 2 * v(0, -1) + v(1, -1))
        m += (gx * gx + gy * gy).squareRoot()
    }
    elev[i] = UInt8(min(255, m / 12))
} }
var buckets = [[Int]](repeating: [], count: 256)
func seed(_ i: Int, _ l: Int) { if label[i] < 0 && cls[i] != 0 && allowed(cls[i], l) { label[i] = Int8(l); buckets[Int(elev[i])].append(i) } }
var regionLayer = [Int32: Int]()
for (l, layer) in layers.enumerated() { for r in layer.regions { regionLayer[r] = l } }
for i in 0..<N where comp[i] >= 0 { if let l = regionLayer[comp[i]] { seed(i, l) } }
for (l, layer) in layers.enumerated() {
    for (sx, sy) in layer.points {
        for dy in -5...5 { for dx in -5...5 where dx * dx + dy * dy <= 25 { seed((sy + dy) * W + sx + dx, l) } }
    }
}
var level = 0
while level < 256 {
    guard let i = buckets[level].popLast() else { level += 1; continue }
    let l = Int(label[i]), x = i % W, y = i / W
    for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && label[j] < 0 && cls[j] != 0 && allowed(cls[j], l) {
        label[j] = Int8(l)
        let p = max(Int(elev[j]), level)
        buckets[p].append(j)
        if p < level { level = p }
    }
}
// Anything unreached (no allowed seed connected) joins the nearest labelled pixel.
var queue: [Int] = (0..<N).filter { label[$0] >= 0 }
var head = 0
var unreached = 0
for i in 0..<N where label[i] < 0 && cls[i] != 0 { unreached += 1 }
while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % W, y = i / W
    for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && label[j] < 0 && cls[j] != 0 {
        label[j] = label[i]; queue.append(j)
    }
}
print("unreached pixels resolved by proximity:", unreached)

// In dark, low-contrast shadow the watershed has no edge to follow and leaves staircase boundaries;
// smooth those with a few passes of a majority filter (dark pixels only, so highlights stay intact).
for _ in 0..<4 {
    var next = label
    for y in 4..<(H - 4) { for x in 4..<(W - 4) {
        let i = y * W + x
        guard cls[i] == CL.dark.rawValue, label[i] >= 0 else { continue }
        var votes = [Int](repeating: 0, count: L)
        var differs = false
        for dy in -4...4 { for dx in -4...4 where dx * dx + dy * dy <= 16 {
            let l = label[(y + dy) * W + x + dx]
            if l >= 0 { votes[Int(l)] += 1; if l != label[i] { differs = true } }
        } }
        if !differs { continue }
        var best = Int(label[i])
        for l in 0..<L where votes[l] > votes[best] && allowed(cls[i], l) { best = l }
        next[i] = Int8(best)
    } }
    label = next
}

// MARK: - Background fringe: within 2 px of a layer, white-blended pixels join it with a computed alpha

var owner = label
var dist = [UInt8](repeating: 255, count: N)
queue = (0..<N).filter { label[$0] >= 0 }
for i in queue { dist[i] = 0 }
head = 0
// Every pixel with any opacity joins its nearest layer (soft edges can fade over more than a few pixels).
while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % W, y = i / W
    for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && dist[j] == 255 && srcA[j] > 0 {
        dist[j] = min(254, dist[i] + 1); owner[j] = owner[i]; queue.append(j)
    }
}
// The source is transparent with soft alpha edges, and its interior sits at alpha 253 (WebP compression):
// keep the source alpha, treating ≥ 245 as fully opaque so layers are solid inside. Nearly invisible edge
// pixels (under 4%) carry unreliable colour, so they take the colour of the nearest pixel of the same layer.
var alpha = [Double](repeating: 0, count: N)
for i in 0..<N where owner[i] >= 0 { alpha[i] = srcA[i] >= 0.96 ? 1 : srcA[i] }
var trueCol = src
var known = [Bool](repeating: false, count: N)
queue = []
for i in 0..<N where owner[i] >= 0 && alpha[i] >= 0.04 { known[i] = true; queue.append(i) }
head = 0
while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % W, y = i / W
    for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && !known[j] && owner[j] == owner[i] {
        known[j] = true
        for c in 0..<3 { trueCol[j*3+c] = trueCol[i*3+c] }
        queue.append(j)
    }
}

// MARK: - Layer images: visible pixels, plus hidden parts under the layers in front

/// Hidden parts reach this far beyond what is visible...
let reach = 48
/// ...except where a layer has a known full outline: the skull's round cranium, and the bowl's whole opening
/// (near rim along the bottom, an assumed far rim hidden behind the skull and leaves along the top).
let skullCranium = (cx: 665.0, cy: 560.0, rx: 405.0, ry: 362.0)
let bowlOpening: [(Double, Double)] = [
    (150, 1040), (184, 1081), (245, 1118), (355, 1161), (460, 1125), (564, 1093), (784, 1059), (1017, 1008),
    (1225, 947), (1336, 867), (1403, 787), (1446, 720), (1350, 655), (1150, 615), (900, 630), (620, 690),
    (400, 780), (250, 870), (165, 960),
]
func inPolygon(_ x: Double, _ y: Double, _ poly: [(Double, Double)]) -> Bool {
    var inside = false
    var j = poly.count - 1
    for i in 0..<poly.count {
        let (xi, yi) = poly[i], (xj, yj) = poly[j]
        if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
        j = i
    }
    return inside
}
func inOutline(_ l: Int, _ x: Int, _ y: Int) -> Bool {
    switch layers[l].name {
    case "skull":
        let dx = (Double(x) - skullCranium.cx) / skullCranium.rx, dy = (Double(y) - skullCranium.cy) / skullCranium.ry
        return dx * dx + dy * dy <= 1
    case "bowl-back": return inPolygon(Double(x), Double(y), bowlOpening)
    default: return false
    }
}

/// Push-pull fill: averages the known colours down a pyramid, then interpolates back up into the unknown
/// pixels, so hidden areas continue the layer's shading smoothly instead of streaking.
func pushPull(_ w0: [Double], _ c0: [Double], _ bw: Int, _ bh: Int) -> [Double] {
    var lw = [w0], lc = [c0], lW = [bw], lH = [bh]
    while lW.last! > 1 || lH.last! > 1 {
        let pw = lw.last!, pc = lc.last!, PW = lW.last!, PH = lH.last!
        let nw = (PW + 1) / 2, nh = (PH + 1) / 2
        var w = [Double](repeating: 0, count: nw * nh), c = [Double](repeating: 0, count: nw * nh * 3)
        for y in 0..<nh { for x in 0..<nw {
            var sw = 0.0, s0 = 0.0, s1 = 0.0, s2 = 0.0
            for dy in 0...1 { for dx in 0...1 {
                let xx = 2 * x + dx, yy = 2 * y + dy
                guard xx < PW, yy < PH else { continue }
                let k = yy * PW + xx, wk = pw[k]
                sw += wk; s0 += wk * pc[k*3]; s1 += wk * pc[k*3+1]; s2 += wk * pc[k*3+2]
            } }
            let i = y * nw + x
            if sw > 0 { c[i*3] = s0 / sw; c[i*3+1] = s1 / sw; c[i*3+2] = s2 / sw }
            w[i] = min(1, sw)
        } }
        lw.append(w); lc.append(c); lW.append(nw); lH.append(nh)
    }
    for li in stride(from: lw.count - 2, through: 0, by: -1) {
        let cc = lc[li + 1], CW = lW[li + 1], CH = lH[li + 1]
        var fw = lw[li], fc = lc[li]
        let FW = lW[li], FH = lH[li]
        for y in 0..<FH { for x in 0..<FW {
            let i = y * FW + x, w = fw[i]
            if w >= 1 { continue }
            let fx = min(Double(CW - 1), max(0, (Double(x) + 0.5) / 2 - 0.5)), fy = min(Double(CH - 1), max(0, (Double(y) + 0.5) / 2 - 0.5))
            let x0 = Int(fx), y0 = Int(fy), x1 = min(CW - 1, x0 + 1), y1 = min(CH - 1, y0 + 1)
            let tx = fx - Double(x0), ty = fy - Double(y0)
            for ch in 0..<3 {
                let a = cc[(y0 * CW + x0) * 3 + ch] * (1 - tx) + cc[(y0 * CW + x1) * 3 + ch] * tx
                let b = cc[(y1 * CW + x0) * 3 + ch] * (1 - tx) + cc[(y1 * CW + x1) * 3 + ch] * tx
                fc[i*3+ch] = w * fc[i*3+ch] + (1 - w) * (a * (1 - ty) + b * ty)
            }
            fw[i] = 1
        } }
        lw[li] = fw; lc[li] = fc
    }
    return lc[0]
}

var front = [Bool](repeating: false, count: N)   // solidly covered by some layer in front of the current one
var images: [[UInt8]] = []
var hiddenCounts: [Int] = []
for l in (0..<L).reversed() {
    var rgba = [UInt8](repeating: 0, count: N * 4)
    var vis = [Bool](repeating: false, count: N)
    var bx0 = W, by0 = H, bx1 = 0, by1 = 0
    for i in 0..<N where owner[i] == Int8(l) {
        vis[i] = true
        let x = i % W, y = i / W
        bx0 = min(bx0, x); by0 = min(by0, y); bx1 = max(bx1, x); by1 = max(by1, y)
        rgba[i*4] = UInt8(min(255, max(0, trueCol[i*3].rounded()))); rgba[i*4+1] = UInt8(min(255, max(0, trueCol[i*3+1].rounded())))
        rgba[i*4+2] = UInt8(min(255, max(0, trueCol[i*3+2].rounded()))); rgba[i*4+3] = UInt8((alpha[i] * 255).rounded())
    }
    // Hidden targets: covered pixels within reach of the visible part, or inside the layer's full outline.
    var d = [UInt8](repeating: 255, count: N)
    queue = []
    for i in 0..<N where vis[i] && alpha[i] >= 1 { d[i] = 0; queue.append(i) }
    head = 0
    var targets: [Int] = []
    var isTarget = [Bool](repeating: false, count: N)
    while head < queue.count {
        let i = queue[head]; head += 1
        if Int(d[i]) >= reach { continue }
        let x = i % W, y = i / W
        for j in [x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1] where j >= 0 && d[j] == 255 && !vis[j] && front[j] {
            d[j] = d[i] + 1; queue.append(j); targets.append(j); isTarget[j] = true
        }
    }
    let outlined = ["skull", "bowl-back"].contains(layers[l].name)
    if outlined {
        for y in 0..<H { for x in 0..<W {
            let i = y * W + x
            if !isTarget[i] && !vis[i] && front[i] && inOutline(l, x, y) { targets.append(i); isTarget[i] = true; d[i] = 0 }
        } }
    }
    for i in targets { let x = i % W, y = i / W; bx0 = min(bx0, x); by0 = min(by0, y); bx1 = max(bx1, x); by1 = max(by1, y) }
    if !targets.isEmpty {
        // Learn colours only from clean interior pixels, not edges mixed with a neighbouring layer.
        let bw = bx1 - bx0 + 1, bh = by1 - by0 + 1
        var w = [Double](repeating: 0, count: bw * bh), c = [Double](repeating: 0, count: bw * bh * 3)
        for y in by0...by1 { for x in bx0...bx1 {
            let i = y * W + x
            guard vis[i], alpha[i] >= 1 else { continue }
            var clean = true
            for dy in -2...2 { for dx in -2...2 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < W, yy < H, owner[yy * W + xx] != Int8(l) { clean = false }
            } }
            guard clean else { continue }
            // The bowl's interior borders leaf shadows; let it learn only from its own blue-violet pixels.
            if layers[l].name == "bowl-back" && trueCol[i*3+2] < trueCol[i*3+1] + 10 { continue }
            let k = (y - by0) * bw + (x - bx0)
            w[k] = 1; for ch in 0..<3 { c[k*3+ch] = trueCol[i*3+ch] }
        } }
        let filled = pushPull(w, c, bw, bh)
        for i in targets {
            let k = (i / W - by0) * bw + (i % W - bx0)
            for ch in 0..<3 { rgba[i*4+ch] = UInt8(min(255, max(0, filled[k*3+ch].rounded()))) }
            let edge = !outlined || !inOutline(l, i % W, i / W)
            rgba[i*4+3] = edge && Int(d[i]) > reach - 8 ? UInt8(255 * Double(reach - Int(d[i]) + 1) / 9) : 255
        }
    }
    hiddenCounts.insert(targets.count, at: 0)
    images.insert(rgba, at: 0)
    // Only solidly covered pixels hide what is behind; soft edges over empty space stay see-through.
    for i in 0..<N where vis[i] && alpha[i] >= 0.9 { front[i] = true }
}

// MARK: - Write layers, a stacked check, and an exploded preview

func writePNG(_ rgba: [UInt8], _ name: String) {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: W * 4, bitsPerPixel: 32)!
    memcpy(r.bitmapData!, rgba, N * 4)
    try! r.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}
var manifest: [[String: Any]] = []
for (l, layer) in layers.enumerated() {
    let file = String(format: "%02d-%@.png", l + 1, layer.name)
    writePNG(images[l], file)
    var vis = 0, x0 = W, y0 = H, x1 = 0, y1 = 0
    for i in 0..<N where owner[i] == Int8(l) && alpha[i] >= 0.5 {
        vis += 1; let x = i % W, y = i / W
        x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
    }
    manifest.append(["order": l + 1, "name": layer.name, "file": file, "depth": layer.depth, "bbox": [x0, y0, x1, y1]])
    print(String(format: "%@  visible %7d px  hidden fill %6d px", file, vis, hiddenCounts[l]))
}
let json = try! JSONSerialization.data(withJSONObject: ["width": W, "height": H, "layers": manifest], options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outDir.appendingPathComponent("layers.json"))

// Stack the layers over white and compare with the source over white.
var comp3 = [Double](repeating: 255, count: N * 3)
for l in 0..<L { let img = images[l]; for i in 0..<N { let a = Double(img[i*4+3]) / 255; if a == 0 { continue }; for c in 0..<3 { comp3[i*3+c] = comp3[i*3+c] * (1 - a) + Double(img[i*4+c]) * a } } }
var sum = 0.0, maxErr = 0.0, over2 = 0
var diffImg = [UInt8](repeating: 255, count: N * 4)
for i in 0..<N {
    var e = 0.0
    for c in 0..<3 { e = max(e, abs(comp3[i*3+c] - (src[i*3+c] * srcA[i] + 255 * (1 - srcA[i])))) }
    sum += e; maxErr = max(maxErr, e); if e > 2 { over2 += 1 }
    let v = UInt8(max(0, 255 - min(255, e * 8)))
    diffImg[i*4] = 255; diffImg[i*4+1] = v; diffImg[i*4+2] = v; diffImg[i*4+3] = 255
}
writePNG(diffImg, "_check-diff.png")
var stacked = [UInt8](repeating: 255, count: N * 4)
for i in 0..<N { for c in 0..<3 { stacked[i*4+c] = UInt8(min(255, max(0, comp3[i*3+c].rounded()))) } }
writePNG(stacked, "_check-stacked.png")
// Label map for review.
let tints: [(UInt8, UInt8, UInt8)] = [(40, 40, 160), (20, 120, 60), (60, 200, 120), (140, 220, 80), (240, 80, 200), (250, 200, 40), (40, 200, 220), (90, 120, 255), (255, 120, 60)]
var lab = [UInt8](repeating: 255, count: N * 4)
for i in 0..<N where owner[i] >= 0 { let t = tints[Int(owner[i]) % tints.count]; lab[i*4] = t.0; lab[i*4+1] = t.1; lab[i*4+2] = t.2 }
writePNG(lab, "_check-labels.png")
print(String(format: "stacked vs source: mean error %.3f, max %.0f, pixels off by more than 2/255: %d of %d", sum / Double(N), maxErr, over2, N))
if CommandLine.arguments.contains("--debug") {
    var errs: [(Double, Int)] = []
    var bins = [Int](repeating: 0, count: 6)
    for i in 0..<N {
        var e = 0.0
        for c in 0..<3 { e = max(e, abs(comp3[i*3+c] - (src[i*3+c] * srcA[i] + 255 * (1 - srcA[i])))) }
        bins[e <= 2 ? 0 : e <= 4 ? 1 : e <= 10 ? 2 : e <= 30 ? 3 : e <= 100 ? 4 : 5] += 1
        if e > 30 { errs.append((e, i)) }
    }
    print("error bins ≤2, ≤4, ≤10, ≤30, ≤100, >100:", bins)
    for (e, i) in errs.sorted(by: { $0.0 > $1.0 }).prefix(12) {
        print(String(format: "  (%d,%d) err %.0f src rgba (%.0f,%.0f,%.0f,%.2f) owner %d alpha %.2f cls %d", i % W, i / W, e, src[i*3], src[i*3+1], src[i*3+2], srcA[i], owner[i], alpha[i], cls[i]))
    }
}
