// The floating toolbar. A placeholder for the tools still to come: same size, spacing and colours as the
// bar in the Figma frame, filled with stand-in tools that select, hover and press like real ones.
import SwiftUI

enum Bar {
    static let width: CGFloat = 681.5
    static let height: CGFloat = 47.5
    static let radius: CGFloat = 12
    static let fill = Color(.displayP3, red: 44 / 255, green: 44 / 255, blue: 44 / 255)
    static let line = Color(.displayP3, red: 68 / 255, green: 68 / 255, blue: 68 / 255)
    static let blue = Color(.displayP3, red: 63 / 255, green: 138 / 255, blue: 226 / 255)
    static let blueIcon = Color(.displayP3, red: 0.53, green: 0.68, blue: 0.8)
    static let icon = Color.white
    static let muted = Color(white: 0.82)
}

struct FloatingToolbar: View {
    @State private var tool = "move"
    @State private var mode = "draw"

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ToolButton(id: "move", tool: $tool, help: "Move") { Image(systemName: "cursorarrow") }
                Chevron()
            }
            .padding(.leading, 8)
            BarDivider().padding(.leading, 7.5)

            HStack(spacing: 0) {
                DrawTool(id: "pen", kind: .pen, tool: $tool)
                DrawTool(id: "marker", kind: .marker, tool: $tool)
                DrawTool(id: "pencil", kind: .pencil, tool: $tool)
            }
            .padding(.leading, 8.25)
            BarDivider().padding(.leading, 9.75)

            HStack(spacing: 7) {
                HStack(spacing: 0) { ToolButton(id: "frame", tool: $tool, help: "Frame") { Image(systemName: "number") }; Chevron() }
                HStack(spacing: 0) { ToolButton(id: "shape", tool: $tool, help: "Shapes") { Image(systemName: "square") }; Chevron() }
                HStack(spacing: 0) { ToolButton(id: "text", tool: $tool, help: "Text") { Text("T").font(.system(size: 19, weight: .light)) }; Chevron() }
                HStack(spacing: 0) { ToolButton(id: "code", tool: $tool, help: "Code") { Image(systemName: "curlybraces") }; Chevron() }
                ToolButton(id: "comment", tool: $tool, help: "Comment") { Image(systemName: "bubble.left") }
                ToolButton(id: "more", tool: $tool, help: "More tools") { Image(systemName: "square.on.circle") }
            }
            .padding(.leading, 7.5)
            BarDivider().padding(.leading, 9)

            ModeSwitch(mode: $mode).padding(.leading, 7)
            Spacer(minLength: 0)
        }
        .font(.system(size: 16, weight: .light))
        .foregroundStyle(Bar.icon)
        .frame(width: Bar.width, height: Bar.height)
        .background(Bar.fill)
        .clipShape(RoundedRectangle(cornerRadius: Bar.radius, style: .continuous))
        // One shadow for the whole bar, not one per tool inside it.
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 12)
    }
}

/// Feedback on press, not release.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ToolButton<Label: View>: View {
    let id: String
    @Binding var tool: String
    let help: String
    @ViewBuilder let label: () -> Label
    @State private var hover = false

    var body: some View {
        let on = tool == id
        Button { tool = id } label: {
            label()
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(on ? Bar.blue : Color.white.opacity(hover ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .frame(width: 18, height: 32)
    }
}

struct BarDivider: View {
    var body: some View { Rectangle().fill(Bar.line).frame(width: 1, height: Bar.height) }
}

/// The segmented group at the right end of the bar.
struct ModeSwitch: View {
    @Binding var mode: String
    private let modes = [("draw", "scribble.variable", "Draw"), ("layout", "rectangle.and.pencil.and.ellipsis", "Layout"),
                         ("parts", "diamond", "Parts"), ("code", "chevron.left.forwardslash.chevron.right", "Code")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.0) { id, symbol, help in
                Button { mode = id } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(mode == id ? Bar.blueIcon : Bar.muted)
                        .frame(width: 29, height: 26)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(mode == id ? Bar.fill : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help(help)
                .accessibilityLabel(help)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Bar.line))
    }
}

// MARK: - Drawing tools that stand up out of the bar

struct DrawTool: View {
    enum Kind { case pen, marker, pencil }
    let id: String
    let kind: Kind
    @Binding var tool: String
    @State private var hover = false

    var body: some View {
        let lift: CGFloat = tool == id ? 6 : hover ? 3 : 0
        Button { tool = id } label: {
            ZStack(alignment: .bottom) {
                Color.clear
                Group {
                    switch kind {
                    case .pen: PenShape()
                    case .marker: MarkerShape()
                    case .pencil: PencilShape()
                    }
                }
                .frame(width: 24, height: 44)
                .offset(y: 2.5 - lift)
            }
            .frame(width: 47.5, height: Bar.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: lift)
        .onHover { hover = $0 }
        .help(kind == .pen ? "Pen" : kind == .marker ? "Marker" : "Pencil")
    }
}

private let metal = LinearGradient(colors: [Color(white: 0.55), Color(white: 0.95), Color(white: 0.62)], startPoint: .leading, endPoint: .trailing)
private let barrel = LinearGradient(colors: [Color(white: 0.42), Color(white: 0.8), Color(white: 0.38)], startPoint: .leading, endPoint: .trailing)

/// White band at the base, like the barrel ends in the design.
private struct Band: View {
    var body: some View {
        VStack(spacing: 0) { Spacer(minLength: 0); Rectangle().fill(Color(white: 0.96)).frame(height: 7) }
    }
}

struct PenShape: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(barrel).frame(width: 20).padding(.top, 24)
            Rectangle().fill(Color(white: 0.22)).frame(width: 18, height: 5).padding(.top, 20)
            Path { p in
                p.move(to: CGPoint(x: 12, y: 0))
                p.addCurve(to: CGPoint(x: 4, y: 14), control1: CGPoint(x: 9, y: 4), control2: CGPoint(x: 4, y: 9))
                p.addLine(to: CGPoint(x: 6, y: 20))
                p.addLine(to: CGPoint(x: 18, y: 20))
                p.addLine(to: CGPoint(x: 20, y: 14))
                p.addCurve(to: CGPoint(x: 12, y: 0), control1: CGPoint(x: 20, y: 9), control2: CGPoint(x: 15, y: 4))
            }
            .fill(metal)
            Path { p in p.move(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 12, y: 11)) }
                .stroke(Color(white: 0.25), lineWidth: 1)
            Circle().fill(Color(white: 0.25)).frame(width: 4, height: 4).padding(.top, 10)
            Band().frame(width: 20)
        }
        .frame(width: 24, height: 44)
    }
}

struct MarkerShape: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(barrel).frame(width: 22).padding(.top, 8)
            Path { p in
                p.move(to: CGPoint(x: 2, y: 10))
                p.addLine(to: CGPoint(x: 2, y: 3))
                p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 5, y: 0), control2: CGPoint(x: 9, y: 6))
                p.addCurve(to: CGPoint(x: 22, y: 2), control1: CGPoint(x: 15, y: 0), control2: CGPoint(x: 19, y: 5))
                p.addLine(to: CGPoint(x: 22, y: 10))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
            Band().frame(width: 22)
        }
        .frame(width: 24, height: 44)
    }
}

struct PencilShape: View {
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.5))
                Rectangle().fill(Color(white: 0.85))
                Rectangle().fill(Color(white: 0.45))
            }
            .frame(width: 18)
            .padding(.top, 16)
            Path { p in
                p.move(to: CGPoint(x: 12, y: 0))
                p.addLine(to: CGPoint(x: 3, y: 17))
                p.addLine(to: CGPoint(x: 21, y: 17))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.78)], startPoint: .leading, endPoint: .trailing))
            Path { p in
                p.move(to: CGPoint(x: 12, y: 0))
                p.addLine(to: CGPoint(x: 9.3, y: 5))
                p.addLine(to: CGPoint(x: 14.7, y: 5))
                p.closeSubpath()
            }
            .fill(Color(white: 0.3))
            Band().frame(width: 18)
        }
        .frame(width: 24, height: 44)
    }
}
