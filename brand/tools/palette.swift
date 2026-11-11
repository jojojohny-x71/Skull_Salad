// The Skull Salad colour palette, built from the logo. Black is the primary colour; the logo's pink, green, blue and
// plum each get a 50–950 ramp. Colours measured from logo/source.png (`palette measure source.png` prints them) are
// kept exactly at their steps, and the steps between them are filled in OKLCH so the ramps stay even and keep the
// art's hue shifts (the skull's pink cools to violet in its shadows, the leaves' green to teal). Writes palette.json,
// colors.css and BrandColors.swift.
// usage: palette build outDir | palette measure source.png
import AppKit

// MARK: Colour maths (OKLab / OKLCH ↔ sRGB, WCAG contrast)

struct LCH { var l, c, h: Double }

func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
func toGamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

func lch(fromHex hex: String) -> LCH {
    let v = Int(hex.dropFirst(), radix: 16)!
    let (r, g, b) = (toLinear(Double(v >> 16 & 255) / 255), toLinear(Double(v >> 8 & 255) / 255), toLinear(Double(v & 255) / 255))
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    var h = atan2(B, A) * 180 / .pi
    if h < 0 { h += 360 }
    return LCH(l: L, c: hypot(A, B), h: h)
}

/// Linear sRGB for an OKLCH colour (may fall outside 0–1 when it is out of gamut).
func linearRGB(_ c: LCH) -> (Double, Double, Double) {
    let a = c.c * cos(c.h * .pi / 180), b = c.c * sin(c.h * .pi / 180)
    let l = pow(c.l + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(c.l - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(c.l - 0.0894841775 * a - 1.2914855480 * b, 3)
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
}

/// The colour as sRGB hex, lowering chroma (keeping lightness and hue) until it fits in sRGB.
func hex(_ c: LCH) -> String {
    var lo = 0.0, hi = c.c, best = LCH(l: c.l, c: 0, h: c.h)
    let fits = { (x: LCH) -> Bool in let (r, g, b) = linearRGB(x); return [r, g, b].allSatisfy { $0 >= -1e-4 && $0 <= 1.0001 } }
    if fits(c) { best = c } else {
        for _ in 0..<30 { let mid = (lo + hi) / 2; if fits(LCH(l: c.l, c: mid, h: c.h)) { lo = mid } else { hi = mid } }
        best = LCH(l: c.l, c: lo, h: c.h)
    }
    let (r, g, b) = linearRGB(best)
    let byte = { (v: Double) in Int((toGamma(min(1, max(0, v))) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
}

func luminance(_ hex: String) -> Double {
    let v = Int(hex.dropFirst(), radix: 16)!
    return 0.2126 * toLinear(Double(v >> 16 & 255) / 255) + 0.7152 * toLinear(Double(v >> 8 & 255) / 255) + 0.0722 * toLinear(Double(v & 255) / 255)
}
func contrast(_ a: String, _ b: String) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

// MARK: Measuring

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "measure" {
    // Groups opaque pixels by hue and prints each group at seven lightness percentiles.
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))!
    var groups: [String: [(LCH, String)]] = [:]
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) { for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.96 else { continue }
        let h = String(format: "#%02X%02X%02X", Int(c.redComponent * 255 + 0.5), Int(c.greenComponent * 255 + 0.5), Int(c.blueComponent * 255 + 0.5))
        let v = lch(fromHex: h)
        let g = v.c < 0.04 ? (v.l > 0.8 ? "white" : "neutral") : v.h >= 120 && v.h < 175 ? "green" : v.h >= 175 && v.h < 250 ? "cyan"
            : v.h >= 250 && v.h < 285 ? "blue" : v.h >= 285 && v.h < 315 ? "violet" : v.h >= 315 || v.h < 20 ? "pink" : "other"
        groups[g, default: []].append((v, h))
    } }
    for (g, px) in groups.sorted(by: { $0.value.count > $1.value.count }) {
        let s = px.sorted { $0.0.l < $1.0.l }
        let picks = [0.03, 0.15, 0.3, 0.5, 0.7, 0.85, 0.97].map { s[Int(Double(s.count - 1) * $0)] }
        print(g, px.count, picks.map { String(format: "%@ L%.2f C%.3f h%.0f", $0.1, $0.0.l, $0.0.c, $0.0.h) }.joined(separator: " | "))
    }
    exit(0)
}

// MARK: The palette

let steps = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

struct Ramp {
    let name, title, use: String
    /// Colours measured from the logo, kept exactly at these steps.
    let anchors: [Int: String]
}

let ramps = [
    Ramp(name: "skull", title: "Skull", use: "The brand accent. Highlights, focus, the one thing on screen you want noticed.",
         anchors: [100: "#FCE0FB", 200: "#FEC8F1", 400: "#FF78D2", 600: "#BA4AB4", 700: "#883F93"]),
    Ramp(name: "leaf", title: "Leaf", use: "Fresh and done: success, saved, new ideas.",
         anchors: [100: "#C1F8DD", 200: "#91F7A7", 300: "#58F584", 400: "#55DA68", 600: "#109E50", 700: "#008049", 800: "#00593F"]),
    Ramp(name: "bowl", title: "Bowl", use: "Interactive and selected: links, the active tool, selection.",
         anchors: [200: "#C1BEFE", 300: "#9FA9FC", 500: "#5774FC", 800: "#322E92", 900: "#271863"]),
    Ramp(name: "plum", title: "Plum", use: "Depth: the skull's and bowl's shadows. Deep tints on black, glows, gradient ends.",
         anchors: [100: "#EAD6FD", 600: "#75289D", 800: "#52227B", 900: "#2B1866"]),
]

/// Fills the steps between measured colours: lightness spaced evenly by step, chroma and hue blended between the
/// neighbouring measured colours. Past the lightest and darkest ones the ramp runs on to near-white and near-black.
func build(_ ramp: Ramp) -> [(step: Int, hex: String, logo: Bool)] {
    let known = steps.enumerated().compactMap { i, s in ramp.anchors[s].map { (i, lch(fromHex: $0)) } }
    let first = known.first!, last = known.last!
    let lightest = LCH(l: 0.975, c: first.1.c * 0.45, h: first.1.h)
    let darkest = LCH(l: min(0.25, last.1.l - 0.06), c: last.1.c * 0.8, h: last.1.h)
    let points = (first.0 > 0 ? [(0, lightest)] : []) + known + (last.0 < steps.count - 1 ? [(steps.count - 1, darkest)] : [])
    return steps.enumerated().map { i, s in
        if let a = ramp.anchors[s] { return (s, a, true) }
        if let end = points.first(where: { $0.0 == i }) { return (s, hex(end.1), false) }
        let hi = points.first { $0.0 > i }!, lo = points.last { $0.0 < i }!
        let t = Double(i - lo.0) / Double(hi.0 - lo.0)
        var dh = hi.1.h - lo.1.h
        if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        return (s, hex(LCH(l: lo.1.l + (hi.1.l - lo.1.l) * t, c: lo.1.c + (hi.1.c - lo.1.c) * t, h: lo.1.h + dh * t)), false)
    }
}

// Black and its greys, named for where the Mac app already uses them.
let ink: [(step: Int, hex: String, use: String)] = [
    (1000, "#000000", "Primary. The window frame and full-bleed brand moments"), (950, "#0B0B0B", "Page behind floating panels"),
    (900, "#161616", "The canvas"), (850, "#1C1C1C", "Cards on the canvas"), (800, "#2C2C2C", "Toolbars and popovers"),
    (700, "#444444", "Dividers and strokes"), (600, "#5E5E5E", "Disabled text"), (500, "#7A7A7A", "Placeholder text"),
    (400, "#9A9A9A", "Captions and secondary text"), (300, "#BDBDBD", "Icons"), (200, "#DCDCDC", "Strong secondary text"),
    (100, "#F2F2F2", "Primary text on black"), (0, "#FFFFFF", "White"),
]

let highlights: [(name: String, title: String, hex: String, use: String)] = [
    ("bone", "Bone", "#FEC8F1", "The teeth. A warm white for text or fills that should feel part of the brand rather than plain white."),
    ("glint", "Glint", "#91D9D8", "The cyan catch-light on the bowl. Sparingly: shine on gradients, a sparkle, never text."),
]

// Not in the logo, but every interface needs them; chosen to sit at the same strength as the brand colours.
let utility: [(name: String, title: String, hex: String, use: String)] = [
    ("warning", "Warning", hex(LCH(l: 0.82, c: 0.16, h: 75)), "Warnings and unsaved changes."),
    ("danger", "Danger", hex(LCH(l: 0.68, c: 0.21, h: 25)), "Errors and deleting."),
]

struct Grad { let name, title, use: String; let angle: Int; let stops: [(String, Int)]; var radial = false }
let gradients = [
    Grad(name: "skull", title: "Skull", use: "The skull's shading, light from the top left.", angle: 160,
         stops: [("#FEC8F1", 0), ("#FF78D2", 38), ("#BA4AB4", 72), ("#75289D", 100)]),
    Grad(name: "leaf", title: "Leaf", use: "A leaf, bright tip to shaded fold.", angle: 160,
         stops: [("#C1F8DD", 0), ("#58F584", 34), ("#109E50", 72), ("#00593F", 100)]),
    Grad(name: "bowl", title: "Bowl", use: "The bowl, lavender rim to deep indigo base.", angle: 170,
         stops: [("#C1BEFE", 0), ("#5774FC", 40), ("#322E92", 80), ("#271863", 100)]),
    Grad(name: "bowl-glint", title: "Bowl glint", use: "The bowl's front with its cyan catch-light, for glossy surfaces.", angle: 110,
         stops: [("#322E92", 0), ("#5774FC", 55), ("#91D9D8", 100)]),
    Grad(name: "salad", title: "Salad", use: "The signature: all three in one sweep. Progress, launch, big brand moments.", angle: 90,
         stops: [("#58F584", 0), ("#5774FC", 55), ("#FF78D2", 100)]),
    Grad(name: "plum-glow", title: "Plum glow", use: "A soft glow on black behind the logo or a hero.", angle: 0,
         stops: [("#52227B", 0), ("#2B1866", 40), ("#000000", 100)], radial: true),
]

// Roles on black: which colour does which job.
let roles: [(name: String, token: String, use: String)] = [
    ("background", "ink-1000", "Behind everything"), ("canvas", "ink-900", "The working surface"), ("surface", "ink-850", "Cards"),
    ("raised", "ink-800", "Toolbars, menus, popovers"), ("border", "ink-700", "Dividers"),
    ("text", "ink-100", "Body text"), ("text-secondary", "ink-400", "Captions"), ("text-disabled", "ink-600", "Disabled"),
    ("accent", "skull-400", "The brand accent"), ("accent-strong", "skull-700", "Accent fills behind white text"),
    ("interactive", "bowl-500", "Links, the selected tool, selection"), ("focus", "skull-400", "Focus rings"),
    ("success", "leaf-400", "Saved, done"), ("info", "bowl-300", "Information on black"),
    ("warning", "warning", "Warnings"), ("danger", "danger", "Errors, deleting"),
]

// MARK: Output

let out = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func swatch(_ hex: String) -> [String: Any] {
    let onBlack = contrast(hex, "#000000"), onWhite = contrast(hex, "#FFFFFF")
    let v = lch(fromHex: hex)
    return ["hex": hex, "oklch": String(format: "oklch(%.3f %.3f %.1f)", v.l, v.c, v.h),
            "contrastOnBlack": (onBlack * 100).rounded() / 100, "textOn": onBlack >= onWhite ? "#000000" : "#FFFFFF"]
}

var tokens: [String: String] = [:]
var json: [String: Any] = ["source": "logo/source.png", "primary": "ink-1000", "generatedBy": "tools/palette.swift"]
json["ink"] = ink.map { var s = swatch($0.hex); s["step"] = $0.step; s["use"] = $0.use; tokens["ink-\($0.step)"] = $0.hex; return s }
json["ramps"] = ramps.map { r -> [String: Any] in
    ["name": r.name, "title": r.title, "use": r.use, "steps": build(r).map { s -> [String: Any] in
        var w = swatch(s.hex); w["step"] = s.step; w["fromLogo"] = s.logo; tokens["\(r.name)-\(s.step)"] = s.hex; return w }]
}
json["highlights"] = highlights.map { var s = swatch($0.hex); s["name"] = $0.name; s["title"] = $0.title; s["use"] = $0.use; tokens[$0.name] = $0.hex; return s }
json["utility"] = utility.map { var s = swatch($0.hex); s["name"] = $0.name; s["title"] = $0.title; s["use"] = $0.use; tokens[$0.name] = $0.hex; return s }
func css(_ g: Grad) -> String {
    let stops = g.stops.map { "\($0.0) \($0.1)%" }.joined(separator: ", ")
    return g.radial ? "radial-gradient(circle at 50% 40%, \(stops))" : "linear-gradient(\(g.angle)deg, \(stops))"
}
json["gradients"] = gradients.map { ["name": $0.name, "title": $0.title, "use": $0.use, "css": css($0), "angle": $0.angle, "radial": $0.radial,
                                     "stops": $0.stops.map { ["hex": $0.0, "at": $0.1] }] }
json["roles"] = roles.map { ["name": $0.name, "token": $0.token, "hex": tokens[$0.token]!, "use": $0.use] }
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("palette.json"))

let order = ink.map { "ink-\($0.step)" } + ramps.flatMap { r in steps.map { "\(r.name)-\($0)" } } + highlights.map(\.name) + utility.map(\.name)
var cssOut = "/* Skull Salad colours. Generated by brand/tools/palette.swift from the logo; edit that, not this. */\n:root {\n"
for name in order { cssOut += "  --\(name): \(tokens[name]!);\n" }
cssOut += "\n"
for g in gradients { cssOut += "  --gradient-\(g.name): \(css(g));\n" }
cssOut += "\n  /* Roles on black */\n"
for r in roles { cssOut += "  --color-\(r.name): var(--\(r.token));\n" }
cssOut += "}\n"
try! cssOut.write(to: out.appendingPathComponent("colors.css"), atomically: true, encoding: .utf8)

func camel(_ s: String) -> String {
    let parts = s.split(separator: "-")
    return parts.enumerated().map { $0 == 0 ? String($1) : $1.prefix(1).uppercased() + $1.dropFirst() }.joined()
}
func swiftColor(_ hex: String) -> String {
    let v = Int(hex.dropFirst(), radix: 16)!
    return String(format: "Color(.sRGB, red: %.4f, green: %.4f, blue: %.4f)", Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255)
}
var swift = "// Skull Salad colours. Generated by brand/tools/palette.swift from the logo; edit that, not this.\nimport SwiftUI\n\nenum BrandColor {\n"
for name in order { swift += "    static let \(name.replacingOccurrences(of: "-", with: "")) = \(swiftColor(tokens[name]!))\n" }
swift += "\n    // Roles on black\n"
for r in roles { swift += "    static let \(camel(r.name)) = \(r.token.replacingOccurrences(of: "-", with: ""))\n" }
swift += "\n    // Gradients: stops from the logo\n"
for g in gradients {
    let stops = g.stops.map { "Gradient.Stop(color: \(swiftColor($0.0)), location: \(Double($0.1) / 100))" }.joined(separator: ", ")
    swift += "    static let \(camel(g.name))Gradient = Gradient(stops: [\(stops)])\n"
}
swift += "}\n"
try! swift.write(to: out.appendingPathComponent("BrandColors.swift"), atomically: true, encoding: .utf8)

for r in ramps { print(r.name.padding(toLength: 6, withPad: " ", startingAt: 0), build(r).map { $0.logo ? "[\($0.hex)]" : $0.hex }.joined(separator: " ")) }
for u in utility { print(u.name, u.hex, String(format: "%.1f:1 on black", contrast(u.hex, "#000000"))) }
