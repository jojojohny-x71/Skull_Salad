// Skull Salad for Mac: app entry point, window setup, and a headless snapshot mode used to check the
// rendering against the Figma frame ("MacBook Pro 14' - 1", node 1:6).
import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        Handwriting.register()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let value = { (flag: String) in args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            var hover: CGPoint?
            if let xy = value("--hover")?.split(separator: ",").compactMap({ Double($0) }), xy.count == 2 { hover = CGPoint(x: xy[0], y: xy[1]) }
            // --launch 1.5 renders the splash card 1.5 s into its loader; add --exit-at 2 to catch its exit as well.
            let launch = value("--launch").flatMap(Double.init).map { (elapsed: $0, exitAt: value("--exit-at").flatMap(Double.init)) }
            // --empty renders Home with no projects.
            Snapshot.write(to: args[i + 1], hover: hover, openFirst: args.contains("--open"), empty: args.contains("--empty"), launch: launch)
            return
        }
        SkullSaladApp.main()
    }
}

struct SkullSaladApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Skull Salad") {
            CanvasScreen()
                .frame(minWidth: 760, minHeight: 480)
                .background(WindowReader { SplashController.shared.adopt($0) })
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Screen.width, height: Screen.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open like Discord: a small splash first; it fills the screen with the main window when it's done.
        SplashController.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Renders the canvas offscreen at the design's size, optionally with the pointer at a point; or the splash card
/// frozen at a moment.
enum Snapshot {
    @MainActor static func write(to path: String, hover: CGPoint?, openFirst: Bool, empty: Bool = false, launch: (elapsed: Double, exitAt: Double?)? = nil) {
        let canvas = CanvasScreen(initialHover: hover, titlebar: Screen.snapshotTitlebar, openFirst: openFirst, folders: empty ? [] : Library.placeholders)
            .frame(width: Screen.width, height: Screen.height)
        let view = Group {
            if let launch {
                SplashCard(elapsed: launch.elapsed, exitAt: launch.exitAt, progress: launch.exitAt == nil ? Launch.progress(at: launch.elapsed) : 1)
            } else {
                canvas
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.offscreen, true)
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
