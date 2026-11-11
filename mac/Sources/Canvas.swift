// The window: a slightly grey rounded canvas floating inside a thick black frame. The canvas shows Home
// (folders on the dotted field) or, once a folder is opened, its workbench.
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
    /// The breadcrumb starts just right of the window buttons.
    static let titleLeading: CGFloat = 84
}

struct CanvasScreen: View {
    private let initialHover: CGPoint?
    private let titlebar: CGFloat?
    @State private var folders: [Folder]
    @State private var open: Folder?
    @State private var anchor: UnitPoint = .center
    /// A note is being written in the open folder: Esc then finishes the note instead of leaving the folder.
    @State private var writing = false

    /// `folders` defaults to your saved projects; snapshots pass the placeholders so they always look the same.
    init(initialHover: CGPoint? = nil, titlebar: CGFloat? = nil, openFirst: Bool = false, folders: [Folder]? = nil) {
        self.initialHover = initialHover
        self.titlebar = titlebar
        let all = folders ?? Library.load()
        _folders = State(initialValue: all)
        _open = State(initialValue: openFirst ? all.first : nil)
    }

    var body: some View {
        GeometryReader { geo in
            let top = max(Screen.margin, titlebar ?? geo.safeAreaInsets.top)
            let roomy = top >= 24
            ZStack(alignment: .topLeading) {
                panel(breadcrumbInside: !roomy)
                    .padding(EdgeInsets(top: top, leading: Screen.margin, bottom: Screen.margin, trailing: Screen.margin))
                if roomy {
                    TitleBar(open: open, back: close)
                        .frame(height: top)
                        .padding(.leading, Screen.titleLeading)
                }
            }
        }
        .background(Screen.frame)
        .ignoresSafeArea()
        .onChange(of: folders) { _, now in Library.save(now) }
        .onPreferenceChange(WritingKey.self) { writing = $0 }
        .background {
            // Back to Home: Esc, ⌘[ or ⌘↑, as when leaving a folder in Finder.
            Group {
                Button("Back") { close() }.keyboardShortcut(.cancelAction)
                Button("Back") { close() }.keyboardShortcut("[", modifiers: .command)
                Button("Enclosing Folder") { close() }.keyboardShortcut(.upArrow, modifiers: .command)
            }
            .disabled(open == nil || writing)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    private func panel(breadcrumbInside: Bool) -> some View {
        ZStack {
            Screen.canvas
            ZStack {
                if let folder = open {
                    Workbench(folder: folder)
                        .transition(.scale(scale: 0.08, anchor: anchor).combined(with: .opacity))
                } else {
                    Home(folders: $folders, initialHover: initialHover) { folder, at in
                        anchor = at
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { open = folder }
                    }
                    .transition(.opacity)
                }
            }
            // The floating toolbar (Toolbar.swift) is hidden for now.
        }
        .overlay(alignment: .topLeading) {
            // In full screen there is no title band, so the breadcrumb floats on the canvas instead.
            if breadcrumbInside && open != nil {
                TitleBar(open: open, back: close)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Screen.cornerRadius, style: .continuous))
    }

    private func close() {
        guard open != nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { open = nil }
    }
}

/// "Skull Salad" on Home; inside a folder, a back button and "Skull Salad › Folder".
struct TitleBar: View {
    let open: Folder?
    let back: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if let folder = open {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.09)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Back to Skull Salad (⌘[)")
                .accessibilityLabel("Back")
                Button("Skull Salad", action: back)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                Text(folder.name)
                    .foregroundStyle(.white.opacity(0.92))
            } else {
                Text("Skull Salad")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.2), value: open)
    }
}
