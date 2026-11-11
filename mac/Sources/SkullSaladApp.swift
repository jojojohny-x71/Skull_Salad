// Skull Salad for Mac: app entry point, window setup, and a headless snapshot mode used to check the
// rendering against the Figma frame ("MacBook Pro 14' - 1", node 1:6).
import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            var hover: CGPoint?
            if let h = args.firstIndex(of: "--hover"), h + 1 < args.count {
                let xy = args[h + 1].split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 { hover = CGPoint(x: xy[0], y: xy[1]) }
            }
            Snapshot.write(to: args[i + 1], hover: hover)
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

/// Renders the canvas offscreen at the design's size, optionally with the pointer at a point.
enum Snapshot {
    @MainActor static func write(to path: String, hover: CGPoint?) {
        let view = CanvasScreen(initialHover: hover, titlebar: Screen.snapshotTitlebar)
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
