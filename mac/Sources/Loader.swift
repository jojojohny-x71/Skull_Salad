// The Skull Salad loader, ported from brand/loader/skull-loader.js so the app opens the same way the web version
// plays: the bowl lands, the leaves sprout and the skull pops up; the salad hops and tosses in its bowl, tipping in 3D;
// when loading is done the layers burst apart in depth and fade. Every pose is a function of time, so any frame can
// also be rendered offscreen for checking.
import AppKit
import SwiftUI

// MARK: - Timing

/// A CSS cubic-bezier timing curve.
struct Ease {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2) }

    static let out = Ease(0.23, 1, 0.32, 1)
    static let smooth = Ease(0.45, 0, 0.3, 1)
    static let pop = Ease(0.34, 1.45, 0.64, 1)

    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        // Find where the curve's x reaches t (Newton's method, then bisection if that stalls) and return its y there.
        var s = t
        for _ in 0..<8 {
            let dx = bezier(s, x1, x2) - t
            if abs(dx) < 1e-6 { return bezier(s, y1, y2) }
            let slope = 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2)
            if abs(slope) < 1e-6 { break }
            s -= dx / slope
        }
        var lo = 0.0, hi = 1.0
        s = t
        while hi - lo > 1e-6 {
            if bezier(s, x1, x2) < t { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return bezier(s, y1, y2)
    }

    private func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
    }
}

private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
private func lerp(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { zip(a, b).map { $0 + ($1 - $0) * t } }

/// A pose (a list of numbers) at a point in a loop, eased toward the next keyframe.
struct Key {
    var at: Double
    var pose: [Double]
    var ease: Ease = .smooth
}

/// The pose at `t` (0–1) along the keyframes, interpolated the way CSS keyframes are.
func sample(_ keys: [Key], _ t: Double) -> [Double] {
    guard let i = keys.lastIndex(where: { $0.at <= t }) else { return keys[0].pose }
    guard i + 1 < keys.count else { return keys[i].pose }
    let a = keys[i], b = keys[i + 1]
    return lerp(a.pose, b.pose, a.ease((t - a.at) / (b.at - a.at)))
}

// MARK: - The art

/// One cut-out layer of the logo. rect: left, top, width, height as fractions of the logo. pivot: where it hinges.
/// amp: how far it lifts out of the bowl on a toss, % of the logo; fan: how far it tips outward, degrees, signed by
/// side. Lifts stay under 2% because the hidden fills under each layer only reach about 3% of the logo.
/// enter: when it arrives during assembly; lag: its follow-through delay (both seconds).
struct LoaderLayer {
    let file: String
    let depth: Double
    let rect: CGRect
    var pivot: UnitPoint?
    var amp = 0.0, fan = 0.0
    var spin = false, bowl = false
    var enter = 0.0, lag = 0.0
}

/// A bit of leaf tossed out of the bowl. at: start, % of the logo; dx, rise: travel at the top of its arc, %.
struct LeafFleck {
    let at: CGPoint
    let dx, rise, spin, size: Double
}

enum Loader {
    // Layers back to front, the same rects as brand/loader/skull-loader.js (from tools/loader-assets.swift).
    static let layers: [LoaderLayer] = [
        LoaderLayer(file: "01-bowl-back", depth: -1, rect: r(10.547, 33.789, 80.664, 42.383), bowl: true),
        LoaderLayer(file: "02-leaf-back-right", depth: -0.7, rect: r(59.375, 16.797, 35.742, 25.195), pivot: p(68.95, 38.98), amp: 1.4, fan: 3.5, enter: 0.14, lag: 0.04),
        LoaderLayer(file: "03-leaf-mid-right", depth: -0.5, rect: r(67.383, 33.203, 27.734, 19.141), pivot: p(74.40, 49.03), amp: 1.2, fan: 3, enter: 0.17, lag: 0.06),
        LoaderLayer(file: "04-leaf-back-left", depth: -0.45, rect: r(4.492, 35.938, 18.750, 18.164), pivot: p(16.97, 50.78), amp: 1.2, fan: -3.5, enter: 0.2, lag: 0.05),
        LoaderLayer(file: "05-skull", depth: 0, rect: r(15.625, 11.914, 56.055, 49.023), pivot: p(43.79, 57.50), amp: 1.8, fan: 3, spin: true, enter: 0.26),
        LoaderLayer(file: "06-leaf-left-band", depth: 0.3, rect: r(4.492, 48.242, 29.102, 23.242), pivot: p(25.20, 68.17), amp: 1, fan: -2.5, enter: 0.38, lag: 0.03),
        LoaderLayer(file: "07-leaf-front-right", depth: 0.45, rect: r(45.703, 46.289, 41.992, 23.633), pivot: p(56.12, 66.60), amp: 1, fan: 2.5, enter: 0.42, lag: 0.02),
        LoaderLayer(file: "08-bowl-front", depth: 0.6, rect: r(10.742, 44.727, 80.859, 48.047), bowl: true),
        LoaderLayer(file: "09-leaf-front-left", depth: 0.85, rect: r(21.289, 54.688, 33.789, 19.531), pivot: p(48.17, 73.95), amp: 0.9, fan: -2.5, enter: 0.47, lag: 0.025),
    ]
    /// The flecks fly between the front-right leaf and the bowl's front, so they come up out of the bowl.
    static let fleckDepth = 0.5
    static let fleckSlot = 7
    static let flecks = [
        LeafFleck(at: CGPoint(x: 20, y: 50), dx: -16, rise: -24, spin: -200, size: 10),
        LeafFleck(at: CGPoint(x: 36, y: 46), dx: -12, rise: -34, spin: 150, size: 8),
        LeafFleck(at: CGPoint(x: 66, y: 44), dx: 22, rise: -30, spin: 190, size: 9),
    ]
    /// Bottom centre of the bowl, where the salad squashes and lands.
    static let bowlBase = UnitPoint(x: 0.512, y: 0.92)
    /// Z travel per unit of depth as a fraction of the size, and the viewing distance as a multiple of it.
    static let depth = 0.1
    static let perspective = 2.06
    /// The loop starts once the last layer has landed.
    static let enterEnd = 0.95
    static let exitLength = 0.38

    private static func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x / 100, y: y / 100, width: w / 100, height: h / 100) }
    private static func p(_ x: Double, _ y: Double) -> UnitPoint { UnitPoint(x: x / 100, y: y / 100) }

    static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: layers.compactMap { l in
        Bundle.main.url(forResource: l.file, withExtension: "png", subdirectory: "Loader")
            .flatMap(NSImage.init(contentsOf:)).map { (l.file, $0) }
    })
}

// MARK: - Motion

/// Two hops per loop, a big toss then a small one, tilting opposite ways so it never looks mechanical.
enum Toss {
    struct Hop { let from, to, height, toss, tilt: Double; var flecks = false }

    static let cycle = 2.0
    static let hops = [Hop(from: 0, to: 0.55, height: 12, toss: 1, tilt: 1, flecks: true), Hop(from: 0.55, to: 1, height: 7, toss: 0.6, tilt: -1)]

    /// Key moments of a hop, as fractions of it.
    static let moments: [(String, Double)] = [("rest", 0), ("crouch", 0.10), ("lift", 0.22), ("apex", 0.47), ("float", 0.60), ("touch", 0.70), ("land", 0.78), ("settle", 0.90)]
    static let fleckMoments: [(String, Double)] = [("rest", 0), ("hide", 0.28), ("out", 0.36), ("high", 0.52), ("drift", 0.64), ("gone", 0.76)]

    /// Keyframes for a whole loop: `pose(moment, hop)` gives the pose at each key moment of each hop, or nil to skip it.
    static func loop(_ moments: [(String, Double)] = moments, ease: [String: Ease] = [:], _ pose: (String, Hop) -> [Double]?) -> [Key] {
        var keys: [Key] = []
        for hop in hops {
            for (name, t) in moments {
                if let p = pose(name, hop) { keys.append(Key(at: hop.from + t * (hop.to - hop.from), pose: p, ease: ease[name] ?? .smooth)) }
            }
        }
        keys.append(Key(at: 1, pose: pose("rest", hops[0])!))
        return keys
    }

    // The whole salad: crouch, push off, rise (slowing), fall (speeding up), land and squash.
    private static let unitPose: [String: [Double]] = ["rest": [0, 1, 1], "crouch": [0, 1.05, 0.93], "lift": [-0.35, 0.97, 1.04], "apex": [-1, 1, 1],
                                                     "touch": [0, 0.98, 1.02], "land": [0, 1.05, 0.93], "settle": [0, 0.99, 1.01]]
    private static let unitEase = ["rest": Ease(0.33, 0, 0.2, 1), "crouch": Ease(0.5, 0, 0.9, 0.6), "lift": Ease(0.15, 0.55, 0.4, 1),
                                   "apex": Ease(0.55, 0, 0.85, 0.45), "touch": Ease.out]
    // The bowl tips back and sideways in the air, which shows off the layers' depth.
    private static let rigPose: [String: [Double]] = ["rest": [0, 0, 0], "crouch": [0, -3, 1], "lift": [3, 6, -2], "apex": [6, 12, -4], "touch": [1, 3, -0.5], "land": [0, 0, 0]]
    // Leaves and skull follow through: pressed into the bowl on take-off, thrown past it at the top, landing just after it.
    private static let movePose: [String: [Double]] = ["rest": [0, 0, 1, 1], "crouch": [0.3, -0.2, 1.02, 0.97], "lift": [0.8, -0.3, 0.99, 1.02], "apex": [-1, 1, 1, 1],
                                                     "float": [-0.75, 0.6, 1, 1], "touch": [-0.2, 0.2, 1, 1], "land": [0.6, -0.2, 1.02, 0.97], "settle": [-0.1, 0, 1, 1]]
    private static let fleckPose: [String: [Double]] = ["rest": [0, 0, 0, 0.6, 0], "hide": [0, 0, 0, 0.6, 0], "out": [0.15, 0.3, 0.15, 0.9, 1],
                                                      "high": [0.6, 1, 0.55, 1, 1], "drift": [0.9, 0.82, 0.8, 1, 1], "gone": [1.05, 0.3, 1, 0.85, 0]]
    private static let fleckEase = ["out": Ease(0.2, 0.6, 0.4, 1), "drift": Ease(0.5, 0, 0.9, 0.5)]

    /// translateY (% of the logo), scaleX, scaleY.
    static let unit = loop(ease: unitEase) { name, hop in
        unitPose[name].map { [$0[0] * hop.height, 1 + ($0[1] - 1) * hop.toss, 1 + ($0[2] - 1) * hop.toss] }
    }
    /// scaleX, scaleY, opacity: smaller and fainter the higher the salad is.
    static let shadow = loop(ease: unitEase) { name, hop in
        unitPose[name].map { p in
            let lift = -p[0] * hop.height / 12, s = 1 - 0.38 * lift
            return [s * (1 + (p[1] - 1) * hop.toss), s, 1 - 0.6 * lift]
        }
    }
    /// rotateX, rotateY, rotateZ, degrees.
    static let rig = loop { name, hop in
        rigPose[name].map { [$0[0] * hop.toss, $0[1] * hop.tilt * hop.toss, $0[2] * hop.tilt * hop.toss] }
    }
    /// translateY (% of the logo), rotation (degrees), scaleX, scaleY.
    static let moves: [[Key]?] = Loader.layers.map { l in
        guard l.pivot != nil else { return nil }
        return loop { name, hop in
            let p = movePose[name]!, g = hop.toss, fan = l.fan * (l.spin ? -hop.tilt : 1)
            return [p[0] * l.amp * g, p[1] * fan * g, 1 + (p[2] - 1) * g, 1 + (p[3] - 1) * g]
        }
    }
    /// x and y (% of the logo), rotation, scale, opacity.
    static let flecks: [[Key]] = Loader.flecks.map { f in
        loop(fleckMoments, ease: fleckEase) { name, hop in
            if !hop.flecks && name != "rest" { return nil }
            let p = hop.flecks ? fleckPose[name]! : fleckPose["rest"]!
            return [p[0] * f.dx, p[1] * f.rise, p[2] * f.spin, p[3], p[4]]
        }
    }
    /// A glint sweeps across the skull at the top of the small hop: its offset, % of its own width.
    static let glint = [Key(at: 0, pose: [-110]), Key(at: 0.66, pose: [-110]), Key(at: 0.88, pose: [190]), Key(at: 1, pose: [190])]
}

/// Everything the loader shows at one moment.
struct LoaderPose {
    struct Layer {
        var enterY = 0.0, enterScale = 1.0, enterAngle = 0.0, enterOpacity = 1.0
        var y = 0.0, angle = 0.0, sx = 1.0, sy = 1.0
        var burst = 1.0
    }

    var unit = [0.0, 1, 1]
    var shadow = [1.0, 1, 1]
    var rig = [0.0, 0, 0]
    var layers = [Layer](repeating: Layer(), count: Loader.layers.count)
    var flecks = [[Double]](repeating: [0, 0, 0, 0.6, 0], count: Loader.flecks.count)
    var fleckBurst = 1.0
    var glint = -110.0
    var stage = 1.0, blur = 0.0
    var meta = 1.0, metaY = 0.0

    /// `elapsed`: seconds since the loader appeared. `exitAt`: when the exit began, if it has.
    init(elapsed e: Double, exitAt: Double? = nil, reduced: Bool) {
        guard let x0 = exitAt, e >= x0 else { self.init(at: e, reduced: reduced); return }
        // Leave from wherever it is mid-hop: every part eases home from its pose when the exit began, while the
        // layers burst apart in depth and the whole thing fades, so nothing ever jumps.
        let base = LoaderPose(at: x0, reduced: reduced)
        self = base
        let k = Ease.out(clamp01((e - x0) / Loader.exitLength))
        meta = base.meta * (1 - Ease.out(clamp01((e - x0) / 0.16)))
        if reduced {
            stage = base.stage * (1 - Ease.out(clamp01((e - x0) / 0.2)))
            return
        }
        let fade = Ease.out(clamp01((e - x0 - 0.09) / 0.28))
        stage = base.stage * (1 - fade)
        blur = 4 * fade
        unit = lerp(base.unit, [-1.5, 1.03, 1.03], k)
        rig = lerp(base.rig, [0, 0, 0], k)
        shadow = lerp(base.shadow, [1.15, 1.15, 0], k)
        glint = -110
        flecks = base.flecks.map { lerp($0, [0, 0, 0, 1, 0], k) }
        let burst = { (d: Double) -> Double in
            let z0 = d * Loader.depth, p = Loader.perspective
            return (p - z0) / (p - z0 * (1 + 3 * k))
        }
        for i in layers.indices {
            let b = base.layers[i]
            layers[i] = Layer(enterY: b.enterY * (1 - k), enterScale: b.enterScale + (1 - b.enterScale) * k, enterAngle: b.enterAngle * (1 - k),
                              enterOpacity: b.enterOpacity + (1 - b.enterOpacity) * k, y: b.y * (1 - k), angle: b.angle * (1 - k),
                              sx: b.sx + (1 - b.sx) * k, sy: b.sy + (1 - b.sy) * k, burst: burst(Loader.layers[i].depth))
        }
        fleckBurst = burst(Loader.fleckDepth)
    }

    /// The assembly, then the loop, before any exit.
    private init(at e: Double, reduced: Bool) {
        let q = Ease.out(clamp01((e - (reduced ? 0 : 0.26)) / 0.32))
        meta = q
        metaY = 4 * (1 - q)
        if reduced {
            // No hopping: fade in, then breathe slowly so it still reads as working.
            stage = e < 0.32 ? Ease.out(clamp01(e / 0.3)) : sample([Key(at: 0, pose: [1]), Key(at: 0.5, pose: [0.55]), Key(at: 1, pose: [1])],
                                                                  ((e - 0.32) / 1.8).truncatingRemainder(dividingBy: 1))[0]
            return
        }
        let s = Ease.out(clamp01(e / 0.4))
        shadow = [0.7 + 0.3 * s, 0.7 + 0.3 * s, s]
        for (i, l) in Loader.layers.enumerated() {
            let q = Ease.pop(clamp01((e - l.enter) / (l.spin ? 0.56 : 0.48)))
            let from = l.bowl ? (y: 6.0, s: 0.92, a: 0.0) : l.spin ? (y: 5.0, s: 0.7, a: 0.0) : (y: 0.0, s: 0.55, a: -l.fan * 4)
            layers[i].enterY = from.y * (1 - q)
            layers[i].enterScale = from.s + (1 - from.s) * q
            layers[i].enterAngle = from.a * (1 - q)
            layers[i].enterOpacity = clamp01((e - l.enter) / 0.16)
        }
        guard e >= Loader.enterEnd else { return }
        let t = e - Loader.enterEnd
        let p = (t / Toss.cycle).truncatingRemainder(dividingBy: 1)
        unit = sample(Toss.unit, p)
        shadow = sample(Toss.shadow, p)
        rig = sample(Toss.rig, p)
        glint = sample(Toss.glint, p)[0]
        flecks = Toss.flecks.map { sample($0, p) }
        for (i, l) in Loader.layers.enumerated() {
            guard let keys = Toss.moves[i], t >= l.lag else { continue }
            let m = sample(keys, ((t - l.lag) / Toss.cycle).truncatingRemainder(dividingBy: 1))
            (layers[i].y, layers[i].angle, layers[i].sx, layers[i].sy) = (m[0], m[1], m[2], m[3])
        }
    }
}

// MARK: - Drawing

/// The loader at one moment. Drive `elapsed` from a TimelineView to play it, or fix it to render a single frame.
struct LoaderView: View {
    var elapsed: Double
    var exitAt: Double?
    var progress: Double?
    var label: String
    var size: CGFloat = 200
    var reduced = false
    /// The progress bar and status line under the logo; leave them off to place them yourself.
    var showsMeta = true

    var body: some View {
        let pose = LoaderPose(elapsed: elapsed, exitAt: exitAt, reduced: reduced)
        VStack(spacing: 10) {
            stage(pose)
                .frame(width: size, height: size)
            if showsMeta {
                LoaderMeta(progress: progress, label: label, width: min(168, max(72, size * 0.6)))
                    .padding(.top, -size * 0.02)
                    .opacity(pose.meta)
                    .offset(y: pose.metaY)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func stage(_ pose: LoaderPose) -> some View {
        ZStack(alignment: .topLeading) {
            // Contact shadow under the bowl.
            Rectangle()
                .fill(EllipticalGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .black.opacity(0.18), location: 0.6),
                                                 .init(color: .clear, location: 1)]))
                .frame(width: size * 0.54, height: size * 0.07)
                .scaleEffect(x: pose.shadow[0], y: pose.shadow[1])
                .opacity(pose.shadow[2])
                .offset(x: size * 0.24, y: size * 0.885)
            ZStack(alignment: .topLeading) {
                ForEach(Loader.layers.indices, id: \.self) { i in
                    if i == Loader.fleckSlot { flecks(pose) }
                    layer(i, pose)
                }
            }
            .scaleEffect(x: pose.unit[1], y: pose.unit[2], anchor: Loader.bowlBase)
            .offset(y: pose.unit[0] / 100 * size)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .opacity(pose.stage)
        .blur(radius: pose.blur)
    }

    private func layer(_ i: Int, _ pose: LoaderPose) -> some View {
        let l = Loader.layers[i], lp = pose.layers[i], pivot = l.pivot ?? Loader.bowlBase
        return ZStack(alignment: .topLeading) {
            if let image = Loader.images[l.file] {
                let art = Image(nsImage: image).resizable().interpolation(.high)
                art
                    .overlay {
                        if l.spin { Glint(offset: pose.glint).mask { art } }
                    }
                    .frame(width: l.rect.width * size, height: l.rect.height * size)
                    .offset(x: l.rect.minX * size, y: l.rect.minY * size)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .scaleEffect(x: lp.sx, y: lp.sy, anchor: pivot)
        .rotationEffect(.degrees(lp.angle), anchor: pivot)
        .offset(y: lp.y / 100 * size)
        .scaleEffect(lp.enterScale, anchor: pivot)
        .rotationEffect(.degrees(lp.enterAngle), anchor: pivot)
        .offset(y: lp.enterY / 100 * size)
        .opacity(lp.enterOpacity)
        .modifier(Tilt(rig: pose.rig, z: l.depth * Loader.depth * size))
        .scaleEffect(lp.burst)
    }

    private func flecks(_ pose: LoaderPose) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Loader.flecks.indices, id: \.self) { j in
                let f = Loader.flecks[j], v = pose.flecks[j], w = f.size / 100 * size
                let origin = UnitPoint(x: (f.at.x + f.size / 2) / 100, y: (f.at.y + f.size / 3) / 100)
                LeafBit()
                    .frame(width: w, height: w * 26 / 40)
                    .offset(x: f.at.x / 100 * size, y: f.at.y / 100 * size)
                    .frame(width: size, height: size, alignment: .topLeading)
                    .scaleEffect(v[3], anchor: origin)
                    .rotationEffect(.degrees(v[2]), anchor: origin)
                    .offset(x: v[0] / 100 * size, y: v[1] / 100 * size)
                    .opacity(v[4])
            }
        }
        .modifier(Tilt(rig: pose.rig, z: Loader.fleckDepth * Loader.depth * size))
        .scaleEffect(pose.fleckBurst)
    }
}

/// The bowl's 3D tip, applied to one layer as if it sat `z` points in front of the bowl's centre, so layers at
/// different depths slide past each other as it turns (CSS: perspective on the stage, preserve-3d, translateZ).
private struct Tilt: ViewModifier {
    let rig: [Double]
    let z: Double

    func body(content: Content) -> some View {
        // rotateX · rotateY · rotateZ as one turn about one axis.
        let (a, b, c) = (rig[0] * .pi / 180, rig[1] * .pi / 180, rig[2] * .pi / 180)
        let (ca, sa, cb, sb, cc, sc) = (cos(a), sin(a), cos(b), sin(b), cos(c), sin(c))
        let m = [[cb * cc, -cb * sc, sb],
                 [sa * sb * cc + ca * sc, -sa * sb * sc + ca * cc, -sa * cb],
                 [-ca * sb * cc + sa * sc, ca * sb * sc + sa * cc, ca * cb]]
        let angle = acos(min(1, max(-1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2)))
        let k = angle > 1e-6 ? 1 / (2 * sin(angle)) : 0
        let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = angle > 1e-6 ? ((m[2][1] - m[1][2]) * k, (m[0][2] - m[2][0]) * k, (m[1][0] - m[0][1]) * k) : (0, 0, 1)
        return content.rotation3DEffect(.radians(angle), axis: axis,
                                        anchor: UnitPoint(x: 0.5, y: 0.58), anchorZ: -z, perspective: 1 / Loader.perspective)
    }
}

/// A band of light swept across the skull.
private struct Glint: View {
    let offset: Double

    var body: some View {
        GeometryReader { g in
            LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .white.opacity(0.42), location: 0.5), .init(color: .clear, location: 0.8)],
                           startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6))
                .frame(width: g.size.width * 0.6)
                .offset(x: offset / 100 * g.size.width * 0.6)
        }
    }
}

/// A bit of leaf in the logo's greens.
private struct LeafBit: View {
    var body: some View {
        ZStack {
            LeafShape().fill(LinearGradient(stops: [.init(color: hex(0xBAF8C4), location: 0), .init(color: hex(0x21CA6A), location: 0.45),
                                                    .init(color: hex(0x006344), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
            LeafRib().stroke(hex(0x7EEF9A).opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    /// The fleck's outline, from its 40 × 26 drawing.
    private struct LeafShape: Shape {
        func path(in r: CGRect) -> Path {
            let pt = { (x: Double, y: Double) in CGPoint(x: r.minX + x / 40 * r.width, y: r.minY + y / 26 * r.height) }
            var path = Path()
            path.move(to: pt(2, 20))
            path.addCurve(to: pt(38, 3), control1: pt(7, 7), control2: pt(21, 1))
            path.addCurve(to: pt(2, 20), control1: pt(34, 14), control2: pt(21, 24))
            path.closeSubpath()
            return path
        }
    }

    private struct LeafRib: Shape {
        func path(in r: CGRect) -> Path {
            let pt = { (x: Double, y: Double) in CGPoint(x: r.minX + x / 40 * r.width, y: r.minY + y / 26 * r.height) }
            var path = Path()
            path.move(to: pt(7, 16))
            path.addCurve(to: pt(32, 5), control1: pt(13, 9), control2: pt(22, 6))
            return path
        }
    }
}

/// The progress bar and the status line under the logo.
struct LoaderMeta: View {
    let progress: Double?
    let label: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            if let p = progress {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .overlay(alignment: .leading) {
                        // The gradient stays put while the fill uncovers it, so green always starts the bar.
                        LinearGradient(stops: [.init(color: hex(0x2BD576), location: 0), .init(color: hex(0x5A6CF0), location: 0.58), .init(color: hex(0xF06ACD), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .mask(alignment: .leading) { Capsule().frame(width: width * p) }
                    }
                    .frame(width: width, height: 4)
                    .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.42), value: p)
            }
            ZStack {
                // A soft blur hides the swap, so a new status reads as the same line changing.
                Text(label)
                    .id(label)
                    .transition(.asymmetric(insertion: .modifier(active: Soft(amount: 1), identity: Soft(amount: 0)), removal: .identity))
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24), value: label)
        }
    }

    private struct Soft: ViewModifier {
        let amount: Double
        func body(content: Content) -> some View { content.opacity(1 - 0.7 * amount).blur(radius: 3 * amount) }
    }
}

func hex(_ v: UInt32) -> Color {
    Color(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}
