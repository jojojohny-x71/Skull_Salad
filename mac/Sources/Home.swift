// Home: the dotted canvas with your projects laid out on an invisible grid that reflows to fit the window.
// Click selects; double-click or Return opens; drag to rearrange. The + tile at the end makes a new idea or book.
import AppKit
import SwiftUI

struct Folder: Identifiable, Equatable, Codable {
    /// An idea is for brainstorming and moodboards; a book is for notes you want to remember and summarise.
    enum Kind: String, Codable { case idea, book }

    var id = UUID()
    var name: String
    var kind: Kind
    var date: Date
}

enum Library {
    /// One placeholder of each kind, for snapshots.
    static let placeholders = [Folder(name: "Untitled", kind: .idea, date: .now), Folder(name: "Untitled", kind: .book, date: .now)]
    private static let key = "projects"

    /// Your projects, in the order you left them; none on a first launch.
    static func load() -> [Folder] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let folders = try? JSONDecoder().decode([Folder].self, from: data) else { return [] }
        return folders
    }

    static func save(_ folders: [Folder]) {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// "Untitled", then "Untitled 2", "Untitled 3"…, as Finder names new folders.
    static func newName(among folders: [Folder]) -> String {
        let names = Set(folders.map(\.name))
        guard names.contains("Untitled") else { return "Untitled" }
        var n = 2
        while names.contains("Untitled \(n)") { n += 1 }
        return "Untitled \(n)"
    }
}

/// The invisible grid: every project gets the same slot, rows wrap to fit the width, and the whole grid sits
/// centred until it's taller than the window, when it starts at the top and scrolls.
struct ProjectGrid {
    static let slot = CGSize(width: 156, height: 176)
    static let gap = CGSize(width: 64, height: 56)
    static let margin: CGFloat = 72

    let columns: Int
    let origin: CGPoint
    let height: CGFloat

    init(count: Int, in size: CGSize) {
        let fit = Int((size.width - Self.margin * 2 + Self.gap.width) / (Self.slot.width + Self.gap.width))
        columns = max(1, min(count, fit))
        let rows = (count + columns - 1) / columns
        let width = CGFloat(columns) * Self.slot.width + CGFloat(columns - 1) * Self.gap.width
        let tall = CGFloat(rows) * Self.slot.height + CGFloat(max(rows - 1, 0)) * Self.gap.height
        let top = max(Self.margin, (size.height - tall) / 2)
        origin = CGPoint(x: (size.width - width) / 2, y: top)
        height = top + tall + Self.margin
    }

    func center(_ i: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(i % columns) * (Self.slot.width + Self.gap.width) + Self.slot.width / 2,
                y: origin.y + CGFloat(i / columns) * (Self.slot.height + Self.gap.height) + Self.slot.height / 2)
    }

    /// The slot nearest a point, among the first `count`.
    func nearest(to p: CGPoint, count: Int) -> Int {
        func distance(_ i: Int) -> CGFloat { hypot(center(i).x - p.x, center(i).y - p.y) }
        return (0..<count).min(by: { distance($0) < distance($1) }) ?? 0
    }
}

struct Home: View {
    @Binding var folders: [Folder]
    var initialHover: CGPoint?
    var onOpen: (Folder, UnitPoint) -> Void
    @State private var pointer: CGPoint?
    @State private var glow: Double
    @State private var selected: Folder.ID?
    @State private var dragging: Dragging?
    @State private var choosing = false
    @State private var deleting: Folder?
    @State private var renaming: Folder?
    @State private var newName = ""
    @Environment(\.offscreen) private var offscreen

    /// The project under the pointer: where it was grabbed, and where its centre is now.
    private struct Dragging {
        let id: Folder.ID
        let grab: CGSize
        var center: CGPoint
    }

    private static let settle = Animation.spring(response: 0.38, dampingFraction: 0.82)

    init(folders: Binding<[Folder]>, initialHover: CGPoint? = nil, onOpen: @escaping (Folder, UnitPoint) -> Void) {
        _folders = folders
        self.initialHover = initialHover
        self.onOpen = onOpen
        _pointer = State(initialValue: initialHover)
        _glow = State(initialValue: initialHover == nil ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geo in
            let grid = ProjectGrid(count: folders.count + 1, in: geo.size)
            ZStack {
                DotField(pointer: pointer, glow: glow)
                if folders.isEmpty {
                    EmptyHome(choosing: $choosing, add: add)
                        .transition(.opacity)
                } else {
                    Scrolling(enabled: !offscreen) {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { selected = nil }
                            ForEach(Array(folders.enumerated()), id: \.element.id) { i, folder in
                                let lifted = dragging?.id == folder.id
                                FolderView(folder: folder, selected: selected == folder.id, lifted: lifted)
                                    .onTapGesture(count: 2) { open(folder, at: grid.center(i), in: geo.size) }
                                    .simultaneousGesture(TapGesture().onEnded { selected = folder.id })
                                    .gesture(drag(folder, from: grid.center(i), on: grid))
                                    .contextMenu {
                                        Button("Open") { open(folder, at: grid.center(i), in: geo.size) }
                                        Button("Rename…") { newName = folder.name; renaming = folder }
                                        Divider()
                                        Button("Delete…", role: .destructive) { deleting = folder }
                                    }
                                    .position(lifted ? dragging?.center ?? grid.center(i) : grid.center(i))
                                    .animation(lifted ? nil : Self.settle, value: grid.center(i))
                                    .zIndex(lifted ? 1 : 0)
                                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                            }
                            NewTile(choosing: $choosing, add: add)
                                .position(grid.center(folders.count))
                                .animation(Self.settle, value: grid.center(folders.count))
                        }
                        .frame(width: geo.size.width, height: max(geo.size.height, grid.height))
                        .coordinateSpace(name: "grid")
                    }
                }
                prompts
                QuoteSkull(folders: folders)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 26)
                    .padding(.bottom, 22)
                // Return or ⌘↓ opens the selected project, as in Finder; ⌘N makes a new one; ⌘⌫ deletes.
                Group {
                    Button("Open") { openSelected(on: grid, in: geo.size) }.keyboardShortcut(.defaultAction)
                        .disabled(selected == nil)
                    Button("Open") { openSelected(on: grid, in: geo.size) }.keyboardShortcut(.downArrow, modifiers: .command)
                        .disabled(selected == nil)
                    Button("New") { choosing = true }.keyboardShortcut("n", modifiers: .command)
                    Button("Delete") { deleting = folders.first { $0.id == selected } }.keyboardShortcut(.delete, modifiers: .command)
                        .disabled(selected == nil)
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            }
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

    /// Picks the project up 1:1 with the pointer; the others slide aside to show where it will land.
    private func drag(_ folder: Folder, from center: CGPoint, on grid: ProjectGrid) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { value in
                if dragging?.id != folder.id {
                    let grab = CGSize(width: value.startLocation.x - center.x, height: value.startLocation.y - center.y)
                    dragging = Dragging(id: folder.id, grab: grab, center: center)
                    selected = folder.id
                }
                guard let grab = dragging?.grab else { return }
                let now = CGPoint(x: value.location.x - grab.width, y: value.location.y - grab.height)
                dragging?.center = now
                guard let from = folders.firstIndex(where: { $0.id == folder.id }) else { return }
                let to = grid.nearest(to: now, count: folders.count)
                if to != from {
                    withAnimation(Self.settle) {
                        folders.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { dragging = nil }
            }
    }

    private func add(_ kind: Folder.Kind) {
        let folder = Folder(name: Library.newName(among: folders), kind: kind, date: .now)
        withAnimation(Self.settle) { folders.append(folder) }
        selected = folder.id
    }

    /// The delete confirmation and the rename prompt, kept off the main body so it type-checks quickly.
    private var prompts: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let folder = deleting { delete(folder) } }
            } message: {
                Text("This \(deleting?.kind == .book ? "book" : "idea") and everything in it will be gone. This can't be undone.")
            }
            .alert("Rename \(renaming?.kind == .book ? "book" : "idea")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Call one “Quotes” and the skull will say what you write in it.")
            }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = renaming, !name.isEmpty, let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i].name = name }
        renaming = nil
    }

    private func delete(_ folder: Folder) {
        withAnimation(Self.settle) { folders.removeAll { $0.id == folder.id } }
        if selected == folder.id { selected = nil }
        deleting = nil
    }

    private func openSelected(on grid: ProjectGrid, in size: CGSize) {
        guard let id = selected, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        open(folders[i], at: grid.center(i), in: size)
    }

    /// The workbench grows out of the project, so pass where it sits.
    private func open(_ folder: Folder, at center: CGPoint, in size: CGSize) {
        selected = folder.id
        onOpen(folder, UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)))
    }
}

/// A vertical scroll view, or just its content when rendering offscreen (ImageRenderer can't draw scroll views).
struct Scrolling<Content: View>: View {
    let enabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if enabled { ScrollView(.vertical) { content } } else { content }
    }
}

/// True while rendering a snapshot, where AppKit-backed views don't draw.
private struct OffscreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var offscreen: Bool {
        get { self[OffscreenKey.self] }
        set { self[OffscreenKey.self] = newValue }
    }
}

// MARK: - New

/// The last slot in the grid: a dashed + tile that asks whether the new project is an idea or a book.
private struct NewTile: View {
    @Binding var choosing: Bool
    let add: (Folder.Kind) -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button { choosing = true } label: {
            shape
                .fill(Color.white.opacity(hover ? 0.05 : 0.02))
                .overlay(shape.strokeBorder(Color.white.opacity(hover ? 0.38 : 0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                        Text("New").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(hover ? 0.85 : 0.5))
                }
                .frame(width: ProjectGrid.slot.width, height: ProjectGrid.slot.height)
                .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .newChooser(isPresented: $choosing, add: add)
        .help("New idea or book (⌘N)")
        .accessibilityLabel("New project")
    }
}

extension View {
    /// The Idea or Book popover, from whichever button makes new projects.
    func newChooser(isPresented: Binding<Bool>, add: @escaping (Folder.Kind) -> Void) -> some View {
        popover(isPresented: isPresented, arrowEdge: .trailing) {
            NewChooser { kind in
                isPresented.wrappedValue = false
                add(kind)
            }
        }
    }
}

/// Idea or book, each shown as its own thumbnail.
private struct NewChooser: View {
    let pick: (Folder.Kind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Choice(kind: .idea, title: "Idea", detail: "Brainstorm and moodboard", pick: pick)
            Choice(kind: .book, title: "Book", detail: "Notes to remember", pick: pick)
        }
        .padding(10)
    }

    private struct Choice: View {
        let kind: Folder.Kind
        let title: String
        let detail: String
        let pick: (Folder.Kind) -> Void
        @State private var hover = false

        var body: some View {
            Button { pick(kind) } label: {
                VStack(spacing: 10) {
                    Thumbnail(folder: Folder(name: title, kind: kind, date: .now), open: hover)
                        .scaleEffect(0.5)
                        .frame(width: ProjectGrid.slot.width / 2, height: ProjectGrid.slot.height / 2)
                    VStack(spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 148)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hover ? 0.08 : 0.03)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
            .accessibilityLabel("New \(title.lowercased())")
        }
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

// MARK: - Thumbnails

/// A project on Home. Hovering peeks inside; while it's being dragged it lifts off the canvas.
struct FolderView: View {
    let folder: Folder
    let selected: Bool
    var lifted = false
    @State private var hover = false

    var body: some View {
        Thumbnail(folder: folder, open: hover || lifted)
            .scaleEffect(lifted ? 1.05 : 1)
            // The render has its own shadow; picked up, it throws a bigger, softer one.
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 22, y: 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected && !lifted ? 0.35 : 0), lineWidth: 1.5)
                    .padding(-12)
            )
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: lifted)
            .onHover { hover = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(folder.name), \(folder.kind == .idea ? "idea" : "book")")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-click to open, or drag to rearrange")
    }
}

/// The drawing for each kind of project, at the grid's slot size: a stack of paper for an idea, a spiral
/// notebook for a book, rendered as real objects (Objects.swift).
struct Thumbnail: View {
    let folder: Folder
    let open: Bool

    var body: some View {
        ObjectThumbnail(folder: folder, open: open)
    }
}

/// Brand colours used by the empty-state stickers (brand/colors): leaf-300 and skull-400.
enum Leaf {
    static let c300 = hex(0x58F584)
    static let sticker = hex(0xFF78D2)
}
