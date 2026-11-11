// The canvas: a slightly grey rounded panel floating inside a thick black window frame, with a 10-point
// dot grid revealed through a soft radial mask, and the floating toolbar near its bottom edge.
import AppKit
import SwiftUI

enum Screen {
    /// The whole window, as the Figma frame "MacBook Pro 14' - 1".
    static let width: CGFloat = 1512
    static let height: CGFloat = 982
    /// Black frame around the canvas on the left, right and bottom (and all round in full screen).
    /// The top band is at least the title bar's height, so the window buttons sit on black.
    static let margin: CGFloat = 12
    static let cornerRadius: CGFloat = 12
    /// The frame is black; the canvas is a shade lighter so it reads as floating inside it.
    static let frame = Color.black
    static let canvas = Color(.displayP3, red: 22 / 255, green: 22 / 255, blue: 22 / 255)
    /// The toolbar's bottom edge sits 44.4 pt above the bottom of the canvas.
    static let toolbarBottom: CGFloat = 44.4
    /// Title bar height used for offscreen snapshots, where there is no real window.
    static let snapshotTitlebar: CGFloat = 28
}

struct CanvasScreen: View {
    private let initialHover: CGPoint?
    private let titlebar: CGFloat?

    init(initialHover: CGPoint? = nil, titlebar: CGFloat? = nil) {
        self.initialHover = initialHover
        self.titlebar = titlebar
    }

    var body: some View {
        GeometryReader { geo in
            let top = max(Screen.margin, titlebar ?? geo.safeAreaInsets.top)
            CanvasPanel(initialHover: initialHover)
                .padding(EdgeInsets(top: top, leading: Screen.margin, bottom: Screen.margin, trailing: Screen.margin))
        }
        .background(Screen.frame)
        .ignoresSafeArea()
    }
}

struct CanvasPanel: View {
    @State private var pointer: CGPoint?
    @State private var glow: Double

    init(initialHover: CGPoint? = nil) {
        _pointer = State(initialValue: initialHover)
        _glow = State(initialValue: initialHover == nil ? 0 : 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Screen.canvas
            Image(nsImage: DotTile.image)
                .resizable(resizingMode: .tile)
                .mask(DotMask(pointer: pointer, glow: glow))
            FloatingToolbar()
                .padding(.bottom, Screen.toolbarBottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: Screen.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
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

/// The 10 × 10 pt tile from the design: a 2 × 2 pt dot of #A0A0A0 at 81% opacity, centred.
enum DotTile {
    static let image: NSImage = NSImage(size: NSSize(width: 10, height: 10), flipped: true) { _ in
        NSColor(srgbRed: 160 / 255, green: 160 / 255, blue: 160 / 255, alpha: 207 / 255).setFill()
        NSRect(x: 4, y: 4, width: 2, height: 2).fill()
        return true
    }
}

/// The design's mask at 50%: a radial fade, solid in the middle and clear at an ellipse 0.79× the canvas.
/// Hovering adds a soft pool of visibility that follows the pointer.
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
