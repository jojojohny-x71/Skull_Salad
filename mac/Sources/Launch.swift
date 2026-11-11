// The launch screen: the loader assembles on the dotted canvas, makes one big toss while the app gets ready, then
// bursts away as Home fades in underneath. A click, Return, Space or Esc skips it.
import SwiftUI

enum Launch {
    /// Loading steps (seconds after launch, progress). There is no real work to wait for yet, so these are timed for
    /// the loader to assemble and make one big toss before it leaves; swap them for real work when there is some.
    static let steps: [(at: Double, progress: Double)] = [(0.5, 0.18), (0.8, 0.31), (1.05, 0.46), (1.3, 0.63), (1.55, 0.78), (1.8, 1)]
    static let labels: [(from: Double, text: String)] = [(0.72, "Laying out the workbench"), (0.34, "Tossing your ideas"), (0, "Opening the sketchbook")]
    /// Once shown, stay at least this long so the assembly never gets cut off halfway.
    static let minimum = 0.7
    /// Hold a full bar for a moment before leaving, so it registers.
    static let hold = 0.26

    static func progress(at t: Double) -> Double { steps.last(where: { $0.at <= t })?.progress ?? 0 }
    static func label(for progress: Double) -> String { labels.first(where: { progress >= $0.from })!.text }
}

struct LaunchScreen: View {
    /// Fades out as Home fades in, so the dots never double up.
    var dots: Double
    /// Called as the loader starts to leave, so Home can come in underneath it.
    var onReveal: () -> Void
    /// Called once the loader has gone.
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var start = Date.now
    @State private var exitAt: Double?
    @State private var progress = 0.0
    @State private var finishing = false

    var body: some View {
        TimelineView(.animation) { context in
            LoaderView(elapsed: context.date.timeIntervalSince(start), exitAt: exitAt, progress: progress,
                       label: Launch.label(for: progress), reduced: reduced)
                // Its motion comes from the clock; don't let Home's fade-in animate its poses too.
                .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotField(pointer: nil, glow: 0).opacity(dots))
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
        .task { await load() }
    }

    private var elapsed: Double { Date.now.timeIntervalSince(start) }

    private func load() async {
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
        exitAt = elapsed
        onReveal()
        try? await Task.sleep(for: .seconds(Loader.exitLength))
        onDone()
    }
}

/// One frozen frame of the launch, for offscreen snapshots.
struct LaunchFrame: View {
    var elapsed: Double
    var exitAt: Double?

    var body: some View {
        let progress = exitAt == nil ? Launch.progress(at: elapsed) : 1
        LoaderView(elapsed: elapsed, exitAt: exitAt, progress: progress, label: Launch.label(for: progress))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DotField(pointer: nil, glow: 0))
    }
}
