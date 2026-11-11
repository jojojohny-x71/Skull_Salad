// The tool tray docked along the bottom edge of a folder, like the tray on a drawing desk: tools stand up out of
// it on the left (the one in your hand rises higher), and on the right sit the settings for what you're using:
// the face, weight, size and ink of the selected note (or of the next one), or the highlighter's colours.
import SwiftUI

enum Tool: CaseIterable {
    case select, text, highlight

    var name: String {
        switch self {
        case .select: "Select (V)"
        case .text: "Write (T)"
        case .highlight: "Highlighter (H)"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .select: "v"
        case .text: "t"
        case .highlight: "h"
        }
    }
}

struct ToolTray: View {
    @Binding var tool: Tool
    /// The selected note's style, or the style the next note will be written in.
    @Binding var style: NoteStyle
    @Binding var highlight: String
    /// Turns the single-key shortcuts off while a note is being written.
    let typing: Bool
    /// Deletes whatever's selected; nil when nothing is.
    var delete: (() -> Void)?

    /// The band along the bottom; tools stand taller and rise out of it.
    static let band: CGFloat = 58
    static let height: CGFloat = 86

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(Tool.allCases, id: \.self) { t in
                    Button { tool = t } label: {
                        Group {
                            switch t {
                            case .select: SelectPuck(active: tool == t)
                            case .text: Marker(active: tool == t)
                            case .highlight: Highlighter(ink: StyleControls.color(highlight), active: tool == t)
                            }
                        }
                        .frame(width: 50, height: Self.height, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .keyboardShortcut(t.key, modifiers: [])
                    .disabled(typing)
                    .help(t.name)
                    .accessibilityLabel(t.name)
                    .accessibilityAddTraits(tool == t ? .isSelected : [])
                }
            }
            .padding(.leading, 28)
            Spacer(minLength: 24)
            Group {
                if tool == .highlight {
                    InkDots(inks: Stroke.inks, chosen: $highlight, size: 20)
                } else {
                    StyleControls(style: $style)
                }
            }
            .frame(height: Self.band)
            .padding(.trailing, 20)
            if let delete {
                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.white.opacity(0.75))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Delete (⌫)")
                .frame(height: Self.band)
                .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .frame(height: Self.height, alignment: .bottom)
        .background(alignment: .bottom) { tray.frame(height: Self.band) }
        // Tools stand taller than the tray, but their feet stay hidden inside it.
        .mask(alignment: .bottom) { Rectangle().frame(height: Self.height + 30) }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: tool)
    }

    /// Dark, slightly glossy, with a lit rim along the top and a soft shadow up onto the mat.
    private var tray: some View {
        LinearGradient(colors: [Color(white: 0.17), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
            .shadow(color: .black.opacity(0.5), radius: 16, y: -4)
    }
}

/// Face, weight, size and ink, each shown the way it'll look.
private struct StyleControls: View {
    @Binding var style: NoteStyle

    static func color(_ ink: String) -> Color { NoteStyle.color(ink) }

    var body: some View {
        HStack(spacing: 14) {
            group {
                ForEach(NoteStyle.Face.allCases, id: \.self) { face in
                    chip(selected: style.face == face, help: face.name) { style.face = face } label: {
                        Text("Aa").font(style.font(face, weight: .medium, size: face == .hand ? 21 : 19))
                    }
                }
            }
            group {
                ForEach(NoteStyle.Weight.allCases, id: \.self) { weight in
                    chip(selected: style.weight == weight, help: weight.name) { style.weight = weight } label: {
                        Text("Aa").font(style.font(weight: weight, size: style.face == .hand ? 21 : 19))
                    }
                }
            }
            group {
                chip(selected: false, help: "Smaller") { step(-1) } label: { Image(systemName: "minus").font(.system(size: 11, weight: .bold)) }
                Text("\(Int(style.size))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26)
                chip(selected: false, help: "Bigger") { step(1) } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
            }
            InkDots(inks: NoteStyle.inks, chosen: $style.ink, size: 18)
        }
    }

    private func step(_ by: Int) {
        let sizes = NoteStyle.sizes
        let i = sizes.firstIndex(where: { $0 >= style.size }) ?? sizes.count - 1
        style.size = sizes[min(max(0, i + by), sizes.count - 1)]
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.35)))
    }

    private func chip<Label: View>(selected: Bool, help: String, _ action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                .frame(minWidth: 30, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(selected ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of ink swatches; the chosen one wears a white ring.
private struct InkDots: View {
    let inks: [String]
    @Binding var chosen: String
    let size: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            ForEach(inks, id: \.self) { ink in
                Button { chosen = ink } label: {
                    Circle()
                        .fill(NoteStyle.color(ink))
                        .frame(width: size, height: size)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.white.opacity(chosen == ink ? 0.9 : 0), lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Ink #\(ink)")
                .accessibilityAddTraits(chosen == ink ? .isSelected : [])
            }
        }
    }
}

/// The select tool: a round black puck with a white arrow, like the menu button on the reference tray.
private struct SelectPuck: View {
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.04)], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 2, endRadius: 30))
                .overlay(Circle().strokeBorder(Color.white.opacity(active ? 0.5 : 0.12), lineWidth: active ? 1.5 : 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            Image(systemName: "cursorarrow")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.7))
        }
        .frame(width: 40, height: 40)
        .offset(y: active ? -22 : -9)
    }
}

/// The writing tool: a felt-tip marker standing in the tray, cap off.
private struct Marker: View {
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chisel felt tip.
            ChiselTip()
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.78)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 12, height: 14)
            // The collar the tip sits in.
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.6), Color(white: 0.3)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 20, height: 8)
            // Barrel, with the ink band and a soft highlight down one side.
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.3), Color(white: 0.16), Color(white: 0.08)],
                                         startPoint: .leading, endPoint: .trailing))
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.98), Color(white: 0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 7)
                    .padding(.top, 6)
            }
            .frame(width: 30, height: 64)
        }
        .shadow(color: .black.opacity(0.45), radius: 3, x: 1, y: 2)
        .offset(y: active ? 0 : 26)
    }
}

/// The highlighter: a fat translucent barrel in its ink, a wide chisel tip and a dark grip.
private struct Highlighter: View {
    let ink: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChiselTip()
                .fill(LinearGradient(colors: [ink, ink.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 18, height: 12)
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.4), Color(white: 0.18)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 26, height: 7)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [ink.opacity(0.7), ink, ink.opacity(0.85), ink.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                // A glossy strip down the barrel.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 5)
                    .offset(x: -8)
                    .padding(.vertical, 6)
            }
            .frame(width: 36, height: 64)
        }
        .shadow(color: .black.opacity(0.45), radius: 3, x: 1, y: 2)
        .offset(y: active ? 0 : 26)
    }
}

private struct ChiselTip: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.35))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.4, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The vertical toolbar on the right of a folder: a black pill of four tools, the chosen one in a white circle,
/// its name beside it on hover. A placeholder for now: picking a tool only moves the highlight.
struct SideToolbar: View {
    private enum Item: String, CaseIterable {
        case select = "Select", pencil = "Pencil", fill = "Fill", eraser = "Eraser"

        var symbol: String {
            switch self {
            case .select: "location.north.fill"
            case .pencil: "pencil"
            case .fill: "paint.bucket.classic"
            case .eraser: "eraser.fill"
            }
        }
    }

    @State private var chosen: Item = .select
    @State private var hovered: Item?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Item.allCases, id: \.self) { item in
                Button { chosen = item } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        // The select arrow points up and to the left, like a pointer.
                        .rotationEffect(.degrees(item == .select ? -45 : 0))
                        .foregroundStyle(chosen == item ? Color.black : Color.white.opacity(hovered == item ? 1 : 0.86))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white).opacity(chosen == item ? 1 : 0))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
                .overlay(alignment: .leading) {
                    // The tool's name in a small pill to the left, on hover.
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(white: 0.1)))
                        .fixedSize()
                        .offset(x: -14)
                        .alignmentGuide(.leading) { $0[.trailing] }
                        .opacity(hovered == item ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(chosen == item ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(Color(white: 0.1)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.15), value: chosen)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
