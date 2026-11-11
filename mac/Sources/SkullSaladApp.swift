// Skull Salad for Mac: app entry point, window setup, and a headless snapshot mode used to check the
// rendering against the Figma frame ("MacBook Pro 14' - 1", node 1:6).
import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let value = { (flag: String) in args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            var hover: CGPoint?
            if let xy = value("--hover")?.split(separator: ",").compactMap({ Double($0) }), xy.count == 2 { hover = CGPoint(x: xy[0], y: xy[1]) }
            // --launch 1.5 freezes the launch screen 1.5 s in; add --exit-at 2 to catch its exit as well.
            let launch = value("--launch").flatMap(Double.init).map { (elapsed: $0, exitAt: value("--exit-at").flatMap(Double.init)) }
            Snapshot.write(to: args[i + 1], hover: hover, openFirst: args.contains("--open"), launch: launch)
            return
        }
        SkullSaladApp.main()
    }
}

struct SkullSaladApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Skull Salad") {
            CanvasScreen(launch: true)
                .frame(minWidth: 760, minHeight: 480)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Screen.width, height: Screen.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The design is the whole screen: open the first window filling the visible area.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.backgroundColor = .black
            window.isOpaque = true
            if let frame = window.screen?.visibleFrame { window.setFrame(frame, display: true) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Renders the canvas offscreen at the design's size, optionally with the pointer at a point or the launch screen
/// frozen at a moment.
enum Snapshot {
    @MainActor static func write(to path: String, hover: CGPoint?, openFirst: Bool, launch: (elapsed: Double, exitAt: Double?)? = nil) {
        let view = CanvasScreen(initialHover: hover, titlebar: Screen.snapshotTitlebar, openFirst: openFirst, launchFrame: launch)
            .frame(width: Screen.width, height: Screen.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot failed\n".utf8))
            exit(1)
        }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch {
            FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
            exit(1)
        }
    }
}
