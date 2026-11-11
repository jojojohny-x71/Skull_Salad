// Vector redraw of the cut-out layers, built the way this kind of art is made: shapes with gradient fills.
// For each layer:
//   1. split it into shapes wherever the art has a real edge (socket rims, highlights, leaf folds),
//   2. give each shape the gradient that best fits its pixels: linear, or radial for sphere-like shading,
//   3. trace each shape (marching squares on a softened mask), simplify, and draw it as smooth Béziers,
//   4. clip the layer to its own soft outer edge so the silhouette stays exact.
// Shapes are drawn biggest first and overlap their neighbours by a hair, so there are never gaps.
// Writes logo.svg (all layers as groups, back to front) and one SVG per layer.
// usage: vectorize layersDir outDir
import AppKit

let args = CommandLine.arguments
let layersDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: layersDir.appendingPathComponent("layers.json"))) as! [String: Any]
let layerList = manifest["layers"] as! [[String: Any]]
/// Colour change per pixel (Oklab distance) that counts as an edge between shapes.
let edgeThreshold = 0.016
/// Shapes smaller than this many pixels join their neighbour.
let minShape = 80

struct Img { let w: Int; let h: Int; var rgba: [UInt8] }
func load(_ url: URL) -> Img {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var out = [UInt8](repeating: 0, count: w * h * 4)
    var p = [Int](repeating: 0, count: 4)
    for y in 0..<h { for x in 0..<w { rep.getPixel(&p, atX: x, y: y); let i = (y * w + x) * 4; for c in 0..<4 { out[i + c] = UInt8(p[c]) } } }
    return Img(w: w, h: h, rgba: out)
}
func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
func oklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let (lr, lg, lb) = (lin(r), lin(g), lin(b))
    let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
    let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
    let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { let x = a.0 - b.0, y = a.1 - b.1, z = a.2 - b.2; return (x * x + y * y + z * z).squareRoot() }

// MARK: - Contours

struct Pt { var x: Double; var y: Double }
/// Iso-line at `level` through a scalar field, edge crossings interpolated for sub-pixel accuracy.
func fieldContours(_ f: [Double], _ w: Int, _ h: Int, _ level: Double) -> [[Pt]] {
    func v(_ x: Int, _ y: Int) -> Double { x >= 0 && y >= 0 && x < w && y < h ? f[y * w + x] : 0 }
    struct K: Hashable { let x: Int; let y: Int }
    var next = [K: K](), pos = [K: Pt]()
    func cross(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Pt {
        let fa = v(ax, ay), fb = v(bx, by)
        let t = abs(fb - fa) < 1e-9 ? 0.5 : min(1, max(0, (level - fa) / (fb - fa)))
        return Pt(x: Double(ax) + Double(bx - ax) * t + 0.5, y: Double(ay) + Double(by - ay) * t + 0.5)
    }
    for y in -1..<h { for x in -1..<w {
        let a = v(x, y) >= level, b = v(x + 1, y) >= level, c = v(x + 1, y + 1) >= level, d = v(x, y + 1) >= level
        let code = (a ? 8 : 0) | (b ? 4 : 0) | (c ? 2 : 0) | (d ? 1 : 0)
        if code == 0 || code == 15 { continue }
        let top = K(x: 2 * x + 1, y: 2 * y), right = K(x: 2 * x + 2, y: 2 * y + 1), bottom = K(x: 2 * x + 1, y: 2 * y + 2), left = K(x: 2 * x, y: 2 * y + 1)
        pos[top] = cross(x, y, x + 1, y); pos[right] = cross(x + 1, y, x + 1, y + 1)
        pos[bottom] = cross(x, y + 1, x + 1, y + 1); pos[left] = cross(x, y, x, y + 1)
        switch code {
        case 1: next[bottom] = left
        case 2: next[right] = bottom
        case 3: next[right] = left
        case 4: next[top] = right
        case 5: next[top] = left; next[bottom] = right
        case 6: next[top] = bottom
        case 7: next[top] = left
        case 8: next[left] = top
        case 9: next[bottom] = top
        case 10: next[left] = bottom; next[right] = top
        case 11: next[right] = top
        case 12: next[left] = right
        case 13: next[bottom] = right
        case 14: next[left] = bottom
        default: break
        }
    } }
    var loops: [[Pt]] = []
    while let start = next.keys.first {
        var loop: [Pt] = []
        var k = start
        while let n = next.removeValue(forKey: k) { loop.append(pos[k]!); k = n; if k == start { break } }
        if loop.count >= 6 { loops.append(loop) }
    }
    return loops
}
func blurField(_ m: [Double], _ w: Int, _ h: Int, passes: Int) -> [Double] {
    var f = m
    for _ in 0..<passes {
        var t = f
        for y in 0..<h { for x in 0..<w { var s = 0.0, n = 0.0; for dx in -1...1 { let xx = x + dx; if xx >= 0 && xx < w { s += f[y * w + xx]; n += 1 } }; t[y * w + x] = s / n } }
        for y in 0..<h { for x in 0..<w { var s = 0.0, n = 0.0; for dy in -1...1 { let yy = y + dy; if yy >= 0 && yy < h { s += t[yy * w + x]; n += 1 } }; f[y * w + x] = s / n } }
    }
    return f
}
func area(_ p: [Pt]) -> Double { var s = 0.0; for i in 0..<p.count { let a = p[i], b = p[(i + 1) % p.count]; s += a.x * b.y - b.x * a.y }; return abs(s) / 2 }
func rdp(_ pts: [Pt], _ eps: Double) -> [Pt] {
    if pts.count < 3 { return pts }
    var keep = [Bool](repeating: false, count: pts.count); keep[0] = true; keep[pts.count - 1] = true
    var stack = [(0, pts.count - 1)]
    while let (s, e) = stack.popLast() {
        if e - s < 2 { continue }
        let a = pts[s], b = pts[e], dx = b.x - a.x, dy = b.y - a.y, len = max(1e-9, (dx * dx + dy * dy).squareRoot())
        var md = 0.0, mi = -1
        for i in (s + 1)..<e { let d = abs(dy * pts[i].x - dx * pts[i].y + b.x * a.y - b.y * a.x) / len; if d > md { md = d; mi = i } }
        if md > eps { keep[mi] = true; stack.append((s, mi)); stack.append((mi, e)) }
    }
    return pts.enumerated().filter { keep[$0.offset] }.map { $0.element }
}
func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
/// Closed loop → smooth path (Catmull-Rom as cubic Béziers).
func smoothPath(_ raw: [Pt], _ eps: Double, dx: Double, dy: Double) -> String {
    let half = raw.count / 2
    var p = Array(rdp(Array(raw[0...half]), eps).dropLast()) + Array(rdp(Array(raw[half...]) + [raw[0]], eps).dropLast())
    if p.count < 3 { p = raw }
    p = p.map { Pt(x: $0.x + dx, y: $0.y + dy) }
    let n = p.count
    var d = "M\(fmt(p[0].x)) \(fmt(p[0].y))"
    for i in 0..<n {
        let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
        d += "C\(fmt(p1.x + (p2.x - p0.x) / 6)) \(fmt(p1.y + (p2.y - p0.y) / 6)) \(fmt(p2.x - (p3.x - p1.x) / 6)) \(fmt(p2.y - (p3.y - p1.y) / 6)) \(fmt(p2.x)) \(fmt(p2.y))"
    }
    return d + "Z"
}

// MARK: - Gradient fitting

/// Solves a small symmetric linear system (Gaussian elimination with partial pivoting).
func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
    let n = b.count
    var m = a.enumerated().map { $0.element + [b[$0.offset]] }
    for c in 0..<n {
        guard let p = (c..<n).max(by: { abs(m[$0][c]) < abs(m[$1][c]) }), abs(m[p][c]) > 1e-12 else { return nil }
        m.swapAt(c, p)
        for r in 0..<n where r != c { let f = m[r][c] / m[c][c]; for k in c...n { m[r][k] -= f * m[c][k] } }
    }
    return (0..<n).map { m[$0][n] / m[$0][$0] }
}
func hex(_ v: [Double]) -> String { String(format: "#%02x%02x%02x", Int(min(255, max(0, v[0])).rounded()), Int(min(255, max(0, v[1])).rounded()), Int(min(255, max(0, v[2])).rounded())) }
/// Least-squares fit of each channel against the given features; returns coefficients and the RMS error.
func fit(_ feats: [[Double]], _ cols: [[Double]]) -> (coef: [[Double]], rms: Double)? {
    let m = feats[0].count
    var ata = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
    var atb = [[Double]](repeating: [Double](repeating: 0, count: m), count: 3)
    for (f, c) in zip(feats, cols) {
        for i in 0..<m { for j in 0..<m { ata[i][j] += f[i] * f[j] }; for ch in 0..<3 { atb[ch][i] += f[i] * c[ch] } }
    }
    var coef: [[Double]] = []
    for ch in 0..<3 { guard let s = solve(ata, atb[ch]) else { return nil }; coef.append(s) }
    var err = 0.0
    for (f, c) in zip(feats, cols) { for ch in 0..<3 { let p = zip(coef[ch], f).reduce(0) { $0 + $1.0 * $1.1 }; err += (p - c[ch]) * (p - c[ch]) } }
    return (coef, (err / Double(feats.count * 3)).squareRoot())
}

// MARK: - Per layer

var defs: [String] = []
var layerDefs: [[String]] = []
var groups: [String] = []
var gid = 0
var totalShapes = 0
for layer in layerList {
    let name = layer["name"] as! String, file = layer["file"] as! String
    let img = load(layersDir.appendingPathComponent(file))
    let W = img.w, H = img.h
    let defsStart = defs.count
    var x0 = W, y0 = H, x1 = 0, y1 = 0
    for i in 0..<(W * H) where img.rgba[i * 4 + 3] >= 128 { let x = i % W, y = i / W; x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y) }
    guard x1 >= x0 else { continue }
    x0 = max(0, x0 - 3); y0 = max(0, y0 - 3); x1 = min(W - 1, x1 + 3); y1 = min(H - 1, y1 + 3)
    let bw = x1 - x0 + 1, bh = y1 - y0 + 1, n = bw * bh
    var inLayer = [Bool](repeating: false, count: n)
    var rgb = [[Double]](repeating: [0, 0, 0], count: n)
    var lab = [(Double, Double, Double)](repeating: (0, 0, 0), count: n)
    for y in 0..<bh { for x in 0..<bw {
        let i = ((y + y0) * W + x + x0) * 4
        guard img.rgba[i + 3] >= 128 else { continue }
        let k = y * bw + x
        inLayer[k] = true
        rgb[k] = [Double(img.rgba[i]), Double(img.rgba[i + 1]), Double(img.rgba[i + 2])]
        lab[k] = oklab(rgb[k][0], rgb[k][1], rgb[k][2])
    } }
    // 1. Shapes: connected areas with no sharp colour change between neighbours.
    var region = [Int](repeating: -1, count: n)
    var sizes: [Int] = []
    var smooth = [Bool](repeating: false, count: n)
    for k in 0..<n where inLayer[k] {
        let x = k % bw, y = k / bw
        var g = 0.0
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, yy >= 0, xx < bw, yy < bh, inLayer[yy * bw + xx] else { continue }
            g = max(g, dist(lab[k], lab[yy * bw + xx]))
        }
        smooth[k] = g < edgeThreshold
    }
    for s in 0..<n where smooth[s] && region[s] < 0 {
        let id = sizes.count
        var stack = [s]; region[s] = id; var count = 0
        while let k = stack.popLast() {
            count += 1
            let x = k % bw, y = k / bw
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < bw, yy < bh else { continue }
                let j = yy * bw + xx
                if smooth[j] && region[j] < 0 { region[j] = id; stack.append(j) }
            }
        }
        sizes.append(count)
    }
    for k in 0..<n where region[k] >= 0 && sizes[region[k]] < minShape { region[k] = -1 }
    func neighbours(_ k: Int) -> [Int] {
        let x = k % bw, y = k / bw
        var out: [Int] = []
        if x > 0 { out.append(k - 1) }; if x < bw - 1 { out.append(k + 1) }
        if y > 0 { out.append(k - bw) }; if y < bh - 1 { out.append(k + bw) }
        return out
    }
    /// Unassigned pixels join the neighbouring shape whose average colour they are closest to, most similar
    /// first, so boundaries settle where the colour actually changes.
    func flood() {
        let maxId = (region.max() ?? -1) + 1
        var sum = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: maxId)
        for k in 0..<n where region[k] >= 0 { let r = region[k]; sum[r].0 += lab[k].0; sum[r].1 += lab[k].1; sum[r].2 += lab[k].2; sum[r].3 += 1 }
        let mean = sum.map { $0.3 > 0 ? ($0.0 / $0.3, $0.1 / $0.3, $0.2 / $0.3) : (0, 0, 0) }
        var buckets = [[(Int, Int)]](repeating: [], count: 256)
        func push(_ j: Int, _ r: Int) { buckets[min(255, Int(dist(lab[j], mean[r]) * 600))].append((j, r)) }
        for k in 0..<n where region[k] >= 0 { for j in neighbours(k) where inLayer[j] && region[j] < 0 { push(j, region[k]) } }
        var level = 0
        while level < 256 {
            guard let (j, r) = buckets[level].popLast() else { level += 1; continue }
            if region[j] >= 0 { continue }
            region[j] = r
            for m in neighbours(j) where inLayer[m] && region[m] < 0 {
                let q = min(255, Int(dist(lab[m], mean[r]) * 600))
                buckets[q].append((m, r)); if q < level { level = q }
            }
        }
    }
    /// Re-number shapes as connected pieces; pieces too small to stand alone are released for flood().
    func relabel() {
        var next = [Int](repeating: -1, count: n)
        var id = 0
        for s in 0..<n where region[s] >= 0 && next[s] < 0 {
            var stack = [s], piece: [Int] = []
            next[s] = id
            while let k = stack.popLast() {
                piece.append(k)
                for j in neighbours(k) where region[j] == region[s] && next[j] < 0 { next[j] = id; stack.append(j) }
            }
            if piece.count < minShape { for k in piece { next[k] = -2 } } else { id += 1 }
        }
        region = next.map { $0 == -2 ? -1 : $0 }
    }
    flood()
    // Split shapes whose single gradient can't follow their colours (soft-edged facets, glints) in two by
    // colour, a few rounds, until each piece is well described by one gradient.
    for _ in 0..<4 {
        let maxId = (region.max() ?? -1) + 1
        var groupsOf = [[Int]](repeating: [], count: maxId)
        for k in 0..<n where region[k] >= 0 { groupsOf[region[k]].append(k) }
        var nextId = maxId, changed = false
        for (r, pts) in groupsOf.enumerated() where pts.count > 700 {
            let step = max(1, pts.count / 4000)
            let sample = stride(from: 0, to: pts.count, by: step).map { pts[$0] }
            let mx = sample.reduce(0.0) { $0 + Double($1 % bw) } / Double(sample.count), my = sample.reduce(0.0) { $0 + Double($1 / bw) } / Double(sample.count)
            guard let lf = fit(sample.map { [1, Double($0 % bw) - mx, Double($0 / bw) - my] }, sample.map { rgb[$0] }), lf.rms > 8 else { continue }
            // Two colour groups, seeded at the two most different colours.
            let m0 = sample.reduce((0.0, 0.0, 0.0)) { ($0.0 + lab[$1].0, $0.1 + lab[$1].1, $0.2 + lab[$1].2) }
            let meanLab = (m0.0 / Double(sample.count), m0.1 / Double(sample.count), m0.2 / Double(sample.count))
            var c0 = lab[sample.max { dist(lab[$0], meanLab) < dist(lab[$1], meanLab) }!]
            var c1 = lab[sample.max { dist(lab[$0], c0) < dist(lab[$1], c0) }!]
            for _ in 0..<8 {
                var s0 = (0.0, 0.0, 0.0, 0.0), s1 = (0.0, 0.0, 0.0, 0.0)
                for k in sample { let p = lab[k]; if dist(p, c0) <= dist(p, c1) { s0 = (s0.0 + p.0, s0.1 + p.1, s0.2 + p.2, s0.3 + 1) } else { s1 = (s1.0 + p.0, s1.1 + p.1, s1.2 + p.2, s1.3 + 1) } }
                if s0.3 > 0 { c0 = (s0.0 / s0.3, s0.1 / s0.3, s0.2 / s0.3) }
                if s1.3 > 0 { c1 = (s1.0 / s1.3, s1.1 / s1.3, s1.2 / s1.3) }
            }
            for k in pts where dist(lab[k], c1) < dist(lab[k], c0) { region[k] = nextId }
            nextId += 1; changed = true
        }
        if !changed { break }
        relabel()
        flood()
    }
    relabel()
    flood()
    for k in 0..<n where inLayer[k] && region[k] < 0 { region[k] = 0 }
    sizes = [Int](repeating: 0, count: (region.max() ?? -1) + 1)
    var members = [[Int]](repeating: [], count: sizes.count)
    for k in 0..<n where inLayer[k] && region[k] >= 0 { members[region[k]].append(k) }
    let order = members.indices.filter { !members[$0].isEmpty }.sorted { members[$0].count > members[$1].count }
    // The layer's own soft outline, used as a clip so the silhouette is exact.
    let alphaField = (0..<n).map { k in Double(img.rgba[((k / bw + y0) * W + k % bw + x0) * 4 + 3]) / 255 }
    let outline = fieldContours(alphaField, bw, bh, 0.5).filter { area($0) >= 20 }.map { smoothPath($0, 0.5, dx: Double(x0), dy: Double(y0)) }.joined()
    gid += 1
    let clipId = "clip-\(name)"
    defs.append("<clipPath id=\"\(clipId)\"><path fill-rule=\"evenodd\" d=\"\(outline)\"/></clipPath>")
    var paths: [String] = []
    for r in order {
        let pts = members[r]
        // 2. Gradient: linear (a + bx + cy) or radial (a + b·distance from a fitted centre), whichever fits better.
        let step = max(1, pts.count / 6000)
        let sample = stride(from: 0, to: pts.count, by: step).map { pts[$0] }
        let xs = sample.map { Double($0 % bw + x0) }, ys = sample.map { Double($0 / bw + y0) }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let cols = sample.map { rgb[$0] }
        let mean = (0..<3).map { ch in cols.reduce(0) { $0 + $1[ch] } / Double(cols.count) }
        // Gradient end colours stay within the colours the shape really has (no overshoot into new hues).
        let lo = (0..<3).map { ch in cols.map { $0[ch] }.sorted()[Int(Double(cols.count - 1) * 0.03)] }
        let hi = (0..<3).map { ch in cols.map { $0[ch] }.sorted()[Int(Double(cols.count - 1) * 0.97)] }
        func clamp(_ c: [Double]) -> [Double] { (0..<3).map { min(hi[$0], max(lo[$0], c[$0])) } }
        var fill = hex(mean)
        if sample.count >= 12, let lf = fit(zip(xs, ys).map { [1, $0 - mx, $1 - my] }, cols) {
            // Radial candidate: centre from the brightness's isotropic quadratic fit.
            let lum = cols.map { [0.299 * $0[0] + 0.587 * $0[1] + 0.114 * $0[2], 0, 0] }
            var radial: (cx: Double, cy: Double, coef: [[Double]], rms: Double, rs: [Double])? = nil
            if let q = fit(zip(xs, ys).map { [1, $0 - mx, $1 - my, ($0 - mx) * ($0 - mx) + ($1 - my) * ($1 - my)] }, lum), abs(q.coef[0][3]) > 1e-7 {
                let cx = mx - q.coef[0][1] / (2 * q.coef[0][3]), cy = my - q.coef[0][2] / (2 * q.coef[0][3])
                let ext = Double(max(x1 - x0, y1 - y0))
                if abs(cx - mx) < ext * 1.5, abs(cy - my) < ext * 1.5 {
                    let rs = zip(xs, ys).map { (($0 - cx) * ($0 - cx) + ($1 - cy) * ($1 - cy)).squareRoot() }
                    if let rf = fit(rs.map { [1, $0] }, cols) { radial = (cx, cy, rf.coef, rf.rms, rs) }
                }
            }
            let swing = (0..<3).map { ch in abs(lf.coef[ch][1]) + abs(lf.coef[ch][2]) }.max()! * Double(max(x1 - x0, y1 - y0)) / 4
            if let rad = radial, rad.rms < lf.rms * 0.85 {
                let sorted = rad.rs.sorted()
                let r0 = sorted[Int(Double(sorted.count - 1) * 0.01)], r1 = max(r0 + 1, sorted[Int(Double(sorted.count - 1) * 0.99)])
                let c0 = clamp((0..<3).map { rad.coef[$0][0] + rad.coef[$0][1] * r0 }), c1 = clamp((0..<3).map { rad.coef[$0][0] + rad.coef[$0][1] * r1 })
                gid += 1
                defs.append("<radialGradient id=\"g\(gid)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(fmt(rad.cx))\" cy=\"\(fmt(rad.cy))\" r=\"\(fmt(r1))\"><stop offset=\"\(String(format: "%.3f", r0 / r1))\" stop-color=\"\(hex(c0))\"/><stop offset=\"1\" stop-color=\"\(hex(c1))\"/></radialGradient>")
                fill = "url(#g\(gid))"
            } else if swing > 4 {
                // Direction of steepest brightness change; stops at the shape's extent along it.
                let lx = 0.299 * lf.coef[0][1] + 0.587 * lf.coef[1][1] + 0.114 * lf.coef[2][1]
                let ly = 0.299 * lf.coef[0][2] + 0.587 * lf.coef[1][2] + 0.114 * lf.coef[2][2]
                let len = max(1e-9, (lx * lx + ly * ly).squareRoot()), dx = lx / len, dy = ly / len
                let ts = zip(xs, ys).map { ($0 - mx) * dx + ($1 - my) * dy }.sorted()
                let t0 = ts[Int(Double(ts.count - 1) * 0.01)], t1 = ts[Int(Double(ts.count - 1) * 0.99)]
                func at(_ t: Double) -> [Double] { clamp((0..<3).map { lf.coef[$0][0] + (lf.coef[$0][1] * dx + lf.coef[$0][2] * dy) * t }) }
                gid += 1
                defs.append("<linearGradient id=\"g\(gid)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(fmt(mx + dx * t0))\" y1=\"\(fmt(my + dy * t0))\" x2=\"\(fmt(mx + dx * t1))\" y2=\"\(fmt(my + dy * t1))\"><stop offset=\"0\" stop-color=\"\(hex(at(t0)))\"/><stop offset=\"1\" stop-color=\"\(hex(at(t1)))\"/></linearGradient>")
                fill = "url(#g\(gid))"
            }
        }
        // 3. Outline: the shape's own pixels, softened, traced slightly outside so neighbours overlap.
        var sx0 = bw, sy0 = bh, sx1 = 0, sy1 = 0
        for k in pts { sx0 = min(sx0, k % bw); sy0 = min(sy0, k / bw); sx1 = max(sx1, k % bw); sy1 = max(sy1, k / bw) }
        sx0 = max(0, sx0 - 4); sy0 = max(0, sy0 - 4); sx1 = min(bw - 1, sx1 + 4); sy1 = min(bh - 1, sy1 + 4)
        let sw = sx1 - sx0 + 1, sh = sy1 - sy0 + 1
        var mask = [Double](repeating: 0, count: sw * sh)
        for k in pts { mask[(k / bw - sy0) * sw + k % bw - sx0] = 1 }
        let field = blurField(mask, sw, sh, passes: 3)
        let loops = fieldContours(field, sw, sh, 0.32).filter { area($0) >= 12 }
        guard !loops.isEmpty else { continue }
        let d = loops.map { smoothPath($0, 0.9, dx: Double(sx0 + x0), dy: Double(sy0 + y0)) }.joined()
        paths.append("<path fill=\"\(fill)\" fill-rule=\"evenodd\" d=\"\(d)\"/>")
    }
    totalShapes += paths.count
    groups.append("<g id=\"\(name)\" clip-path=\"url(#\(clipId))\">\n\(paths.joined(separator: "\n"))\n</g>")
    layerDefs.append(Array(defs[defsStart...]))
    print("\(name): \(paths.count) shapes")
}

let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1593 1593\" width=\"1593\" height=\"1593\">"
let svg = "\(header)\n<defs>\n\(defs.joined(separator: "\n"))\n</defs>\n\(groups.joined(separator: "\n"))\n</svg>\n"
try! svg.write(to: outDir.appendingPathComponent("logo.svg"), atomically: true, encoding: .utf8)
for (i, g) in groups.enumerated() {
    let name = layerList[i]["name"] as! String
    try! "\(header)\n<defs>\n\(layerDefs[i].joined(separator: "\n"))\n</defs>\n\(g)\n</svg>\n".write(to: outDir.appendingPathComponent(String(format: "%02d-%@.svg", i + 1, name)), atomically: true, encoding: .utf8)
}
print("shapes:", totalShapes, "size:", svg.utf8.count / 1024, "KB")
