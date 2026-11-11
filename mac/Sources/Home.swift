// Home: the dotted canvas with your idea folders on it. Click selects a folder; double-click or Return
// opens it into its workbench.
import AppKit
import SwiftUI

struct Folder: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var date: Date
}

enum Library {
    /// A single placeholder folder until real ideas exist.
    static let folders = [Folder(name: "Untitled", date: .now)]
}

struct Home: View {
    var initialHover: CGPoint?
    var onOpen: (Folder, UnitPoint) -> Void
    @State private var pointer: CGPoint?
    @State private var glow: Double
    @State private var selected: Folder.ID?
    @State private var frames: [Folder.ID: CGRect] = [:]

    init(initialHover: CGPoint? = nil, onOpen: @escaping (Folder, UnitPoint) -> Void) {
        self.initialHover = initialHover
        self.onOpen = onOpen
        _pointer = State(initialValue: initialHover)
        _glow = State(initialValue: initialHover == nil ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DotField(pointer: pointer, glow: glow)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = nil }
                HStack(spacing: 44) {
                    ForEach(Library.folders) { folder in
                        FolderView(folder: folder, selected: selected == folder.id)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: FolderFrames.self, value: [folder.id: g.frame(in: .named("home"))])
                            })
                            .onTapGesture(count: 2) { open(folder, in: geo.size) }
                            .simultaneousGesture(TapGesture().onEnded { selected = folder.id })
                    }
                }
                // Return or ⌘↓ opens the selected folder, as in Finder.
                Group {
                    Button("Open") { openSelected(in: geo.size) }.keyboardShortcut(.defaultAction)
                    Button("Open") { openSelected(in: geo.size) }.keyboardShortcut(.downArrow, modifiers: .command)
                }
                .disabled(selected == nil)
                .opacity(0)
                .frame(width: 0, height: 0)
            }
            .coordinateSpace(name: "home")
            .onPreferenceChange(FolderFrames.self) { frames = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    pointer = p
                    if glow < 1 { withAnimation(.easeOut(duration: 0.25)) { glow = 1 } }
                case .ended:
                    withAnimation(.easeOut(duration: 0.5)) { glow = 0 }
                }
            }
        }
    }

    private func openSelected(in size: CGSize) {
        guard let id = selected, let folder = Library.folders.first(where: { $0.id == id }) else { return }
        open(folder, in: size)
    }

    /// The workbench grows out of the folder, so pass where the folder sits.
    private func open(_ folder: Folder, in size: CGSize) {
        selected = folder.id
        let r = frames[folder.id] ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        onOpen(folder, UnitPoint(x: r.midX / max(size.width, 1), y: r.midY / max(size.height, 1)))
    }
}

private struct FolderFrames: PreferenceKey {
    static var defaultValue: [Folder.ID: CGRect] = [:]
    static func reduce(value: inout [Folder.ID: CGRect], nextValue: () -> [Folder.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Dots

/// The design's dot grid seen through its radial mask, with a pool of brighter dots under the pointer.
struct DotField: View {
    var pointer: CGPoint?
    var glow: Double

    var body: some View {
        Image(nsImage: DotTile.image)
            .resizable(resizingMode: .tile)
            .mask(DotMask(pointer: pointer, glow: glow))
    }
}

/// The 10 × 10 pt tile from the design: a 2 × 2 pt dot of #A0A0A0 at 81% opacity, centred.
enum DotTile {
    static let image: NSImage = NSImage(size: NSSize(width: 10, height: 10), flipped: true) { _ in
        NSColor(srgbRed: 160 / 255, green: 160 / 255, blue: 160 / 255, alpha: 207 / 255).setFill()
        NSRect(x: 4, y: 4, width: 2, height: 2).fill()
        return true
    }
}

/// The design's mask at 50%: a radial fade, solid in the middle and clear at an ellipse 0.79× the canvas.
struct DotMask: View {
    var pointer: CGPoint?
    var glow: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(EllipticalGradient(colors: [.black, .black.opacity(0)], center: .center,
                                         startRadiusFraction: 0, endRadiusFraction: 0.789))
                .opacity(0.5)
            if let p = pointer {
                Circle()
                    .fill(RadialGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .black.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 190))
                    .frame(width: 380, height: 380)
                    .position(p)
                    .opacity(glow)
            }
        }
    }
}

// MARK: - Folder

/// A black-and-white glass folder: a back panel, two sheets of paper peeking out, and a frosted front.
struct FolderView: View {
    let folder: Folder
    let selected: Bool
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .frame(height: 158)

            Paper(tint: 0.92)
                .frame(width: 150, height: 110)
                .rotationEffect(.degrees(-5))
                .offset(x: -16, y: hover ? -42 : -30)
            Paper(tint: 0.8)
                .frame(width: 138, height: 104)
                .rotationEffect(.degrees(4))
                .offset(x: 28, y: hover ? -36 : -28)

            ZStack(alignment: .bottomLeading) {
                FolderFront().fill(.ultraThinMaterial)
                FolderFront().fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                FolderFront().stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(folder.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(16)
            }
            .frame(height: 112)
            .rotation3DEffect(.degrees(hover ? -9 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
        }
        .frame(width: 220, height: 172)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.35 : 0), lineWidth: 1.5)
                .padding(-8)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-click to open")
    }
}

/// The folder front: lower on the left, with a raised tab on the right.
struct FolderFront: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 272, sy = r.height / 144
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(0, 42))
        path.addQuadCurve(to: p(18, 24), control: p(0, 24))
        path.addLine(to: p(92, 24))
        path.addCurve(to: p(134, 0), control1: p(112, 24), control2: p(112, 0))
        path.addLine(to: p(254, 0))
        path.addQuadCurve(to: p(272, 18), control: p(272, 0))
        path.addLine(to: p(272, 126))
        path.addQuadCurve(to: p(254, 144), control: p(272, 144))
        path.addLine(to: p(18, 144))
        path.addQuadCurve(to: p(0, 126), control: p(0, 144))
        path.closeSubpath()
        return path
    }
}

/// A sheet of paper with a few faint ruled lines.
struct Paper: View {
    let tint: Double
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(white: tint))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(Color.black.opacity(0.12)).frame(width: [92, 70, 84, 52][i], height: 2)
                    }
                }
                .padding(14)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}
