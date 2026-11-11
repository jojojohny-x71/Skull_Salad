// The splash window, opened the way Discord opens: a small card in the middle of the screen plays the logo loader
// while the app gets ready, then the logo bursts away, the card fades, and the main window fades in behind it.
// The card follows the Figma frame "Frame 1" (node 17:20). A click, Return, Space or Esc skips it.
import AppKit
import SwiftUI

enum Splash {
    /// The Figma card (1260.6 × 1449.8, corner radius 124, logo 1017.4 wide) scaled to a 300-point-wide window.
    static let size = CGSize(width: 300, height: 345)
    static let radius: CGFloat = 29.5
    static let fill = Color(.sRGB, red: 0x22 / 255, green: 0x21 / 255, blue: 0x21 / 255)
    static let logo: CGFloat = 242
    /// The design centres the logo; it sits 10 points higher here to leave room for the status line.
    static let logoTop = (size.height - logo) / 2 - 10
    static let metaTop: CGFloat = 288
    /// The card fades in first, then the loader starts assembling on it.
    static let loaderDelay = 0.12
}

enum Launch {
    /// Loading steps (seconds after the loader starts, progress). There is no real work to wait for yet, so these
    /// are timed for the loader to assemble and make one big toss; swap them for real work when there is some.
    static let steps: [(at: Double, progress: Double)] = [(0.5, 0.18), (0.8, 0.31), (1.05, 0.46), (1.3, 0.63), (1.55, 0.78), (1.8, 1)]
    static let labels: [(from: Double, text: String)] = [(0.72, "Laying out the workbench"), (0.34, "Tossing your ideas"), (0, "Opening the sketchbook")]
    /// Once shown, stay at least this long so the assembly never gets cut off halfway.
    static let minimum = 0.7
    /// Hold a full bar for a moment before leaving, so it registers.
    static let hold = 0.26

    static func progress(at t: Double) -> Double { steps.last(where: { $0.at <= t })?.progress ?? 0 }
    static func label(for progress: Double) -> String { labels.first(where: { progress >= $0.from })!.text }
}

/// The card at one moment of the loader. `elapsed` and `exitAt` are in the loader's own time.
struct SplashCard: View {
    var elapsed: Double
    var exitAt: Double?
    var progress: Double
    var reduced = false

    var body: some View {
        let pose = LoaderPose(elapsed: elapsed, exitAt: exitAt, reduced: reduced)
        let label = Launch.label(for: progress)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Splash.radius, style: .continuous)
                .fill(Splash.fill)
                .overlay(RoundedRectangle(cornerRadius: Splash.radius, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
            LoaderView(elapsed: elapsed, exitAt: exitAt, progress: progress, label: label, size: Splash.logo, reduced: reduced, showsMeta: false)
                .padding(.top, Splash.logoTop)
            LoaderMeta(progress: progress, label: label, width: 132)
                .opacity(pose.meta)
                .offset(y: pose.metaY)
                .padding(.top, Splash.metaTop)
                .accessibilityHidden(true)
        }
        .frame(width: Splash.size.width, height: Splash.size.height)
    }
}

/// The live card in the splash window: runs the loading steps and hands over to the main window.
private struct SplashScreen: View {
    let controller: SplashController

    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var start = Date.now
    @State private var exitAt: Double?
    @State private var progress = 0.0
    @State private var finishing = false
    @State private var shown = false
    @State private var leaving = false

    var body: some View {
        TimelineView(.animation) { context in
            SplashCard(elapsed: context.date.timeIntervalSince(start) - Splash.loaderDelay, exitAt: exitAt, progress: progress, reduced: reduced)
                // Its motion comes from the clock; don't let the card's own fades animate the loader's poses too.
                .transaction { $0.animation = nil }
        }
        .scaleEffect(shown && !leaving ? 1 : 0.94)
        .opacity(shown && !leaving ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { Task { await finish() } }
        .background {
            Group {
                Button("Skip") { Task { await finish() } }.keyboardShortcut(.defaultAction)
                Button("Skip") { Task { await finish() } }.keyboardShortcut(.cancelAction)
                Button("Skip") { Task { await finish() } }.keyboardShortcut(.space, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .task {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.35)) { shown = true }
            await load()
        }
    }

    /// Seconds since the loader started, in its own time.
    private var elapsed: Double { Date.now.timeIntervalSince(start) - Splash.loaderDelay }

    private func load() async {
        try? await Task.sleep(for: .seconds(0.4))
        controller.cardDidAppear()
        for step in Launch.steps {
            try? await Task.sleep(for: .seconds(max(0, step.at - elapsed)))
            guard !finishing, !Task.isCancelled else { return }
            progress = step.progress
        }
        await finish()
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        if elapsed < Launch.minimum { try? await Task.sleep(for: .seconds(Launch.minimum - elapsed)) }
        progress = 1
        try? await Task.sleep(for: .seconds(Launch.hold))
        // The logo bursts away while the main window fades in behind the card, then the card itself goes.
        exitAt = elapsed
        controller.revealMain()
        try? await Task.sleep(for: .seconds(0.15))
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)) { leaving = true }
        try? await Task.sleep(for: .seconds(0.27))
        controller.closeSplash()
    }
}

/// Opens the splash window at launch and keeps the main window invisible until the splash hands over.
@MainActor
final class SplashController {
    static let shared = SplashController()

    private var splash: NSWindow?
    private var main: NSWindow?
    private var revealed = false

    func show() {
        let window = SplashWindow(contentRect: NSRect(origin: .zero, size: Splash.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: SplashScreen(controller: self))
        // Dead centre, as Discord does (center() would put it in the upper third).
        if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: screen.midX - Splash.size.width / 2, y: screen.midY - Splash.size.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        splash = window
    }

    /// The main window, as soon as it exists: fill the screen with it, and hide it until the splash is done.
    func adopt(_ window: NSWindow) {
        guard main == nil, window !== splash else { return }
        main = window
        window.backgroundColor = .black
        window.isOpaque = true
        if let frame = (window.screen ?? NSScreen.main)?.visibleFrame { window.setFrame(frame, display: false) }
        guard !revealed else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    /// The window's shadow follows the card's shape, so recompute it once the card has faded in.
    func cardDidAppear() { splash?.invalidateShadow() }

    func revealMain() {
        revealed = true
        guard let main else { return }
        main.ignoresMouseEvents = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            main.animator().alphaValue = 1
        }
    }

    func closeSplash() {
        splash?.orderOut(nil)
        splash = nil
        main?.makeKeyAndOrderFront(nil)
    }
}

/// A borderless window that can still take key presses, so Return, Space and Esc reach the skip buttons.
private final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Hands back the window a view lands in, as soon as it lands there.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Reader(onWindow) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        let onWindow: (NSWindow) -> Void
        init(_ onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
