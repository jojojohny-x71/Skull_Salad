// The workbench inside a folder: a self-healing cutting mat in black and white that never ends downwards. It is
// always exactly as wide as the window (no sideways scrolling) and grows as you scroll down. The ruler along the
// top stays pinned; the rulers down each side scroll with the mat and keep counting inches. Inside them the
// half-inch grid is only just visible. Notes are written on it and highlighted, with the tools in a tray docked
// along the bottom edge.
import AppKit
import SwiftUI

enum Mat {
    /// One "inch" on the mat.
    static let inch: CGFloat = 64
    /// Width of the ruler band between the canvas edge and the grid.
    static let band: CGFloat = 40
    /// The mat is drawn, and grows, in sections this tall.
    static let section: CGFloat = inch * 8
    static let grid = Color.white.opacity(0.045)
    static let gridInch = Color.white.opacity(0.075)
    static let frame = Color.white.opacity(0.12)
    static let tick = Color.white.opacity(0.2)
    static let number = Color.white.opacity(0.3)

    /// Ruler tick lengths: longest on the inch, then the half, quarter and eighth.
    static func tickLength(_ eighth: Int) -> CGFloat { eighth % 8 == 0 ? 12 : eighth % 4 == 0 ? 8 : eighth % 2 == 0 ? 5 : 3 }
}

struct Workbench: View {
    let folder: Folder
    /// How many sections exist so far; more are added whenever the last one scrolls into view.
    @State private var sections = 3
    @State private var tool: Tool = .select
    @State private var notes: [Note] = []
    @State private var selected: Note.ID?
    @State private var editing: Note.ID?
    /// The note being dragged, and where it started.
    @State private var moving: (id: Note.ID, from: CGPoint)?
    @State private var strokes: [Stroke] = []
    @State private var selectedStroke: Stroke.ID?
    /// The highlighter sweep in progress, in grid space.
    @State private var sweep: [CGPoint]?
    @State private var highlight = UserDefaults.standard.string(forKey: "highlightInk") ?? Stroke.inks[0]
    /// What the next note will be written in.
    @State private var nextStyle = NoteStyle.last
    @FocusState private var focus: Note.ID?
    @Environment(\.offscreen) private var offscreen

    var body: some View {
        GeometryReader { geo in
            Scrolling(enabled: !offscreen) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<sections, id: \.self) { i in
                        MatSection(index: i)
                            .frame(height: Mat.section)
                            .onAppear { if i >= sections - 1 { sections += 3 } }
                    }
                }
                .padding(.top, Mat.band)
                .frame(width: geo.size.width)
                .overlay(alignment: .topLeading) { writing(width: geo.size.width) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .overlay(alignment: .top) {
                TopRuler().frame(height: Mat.band)
            }
            .overlay(alignment: .bottom) {
                ToolTray(tool: $tool, style: style, highlight: $highlight, typing: editing != nil,
                         delete: selected != nil || selectedStroke != nil ? deleteSelected : nil)
            }
            .overlay(alignment: .trailing) {
                // Pinned on the right, just inside the side ruler, centred in the space above the tray.
                SideToolbar()
                    .padding(.trailing, Mat.band + 16)
                    .padding(.bottom, ToolTray.band)
            }
        }
        .background {
            // ⌫ deletes the selected note or stroke, unless you're writing in a note.
            Button("Delete") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled((selected == nil && selectedStroke == nil) || editing != nil)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            notes = NotesStore.shared.notes(in: folder.id)
            strokes = NotesStore.shared.strokes(in: folder.id)
            let deepest = max(notes.map(\.y).max() ?? 0, strokes.flatMap(\.points).map(\.y).max() ?? 0)
            sections = max(sections, Int(((deepest + 1500) / Mat.section).rounded(.up)))
        }
        .onChange(of: notes) { _, now in
            if moving == nil { NotesStore.shared.set(now, in: folder.id) }
        }
        .onChange(of: strokes) { _, now in NotesStore.shared.set(now, in: folder.id) }
        .onChange(of: highlight) { _, now in UserDefaults.standard.set(now, forKey: "highlightInk") }
        .onChange(of: tool) { _, now in if now == .highlight { finish() } }
        .onChange(of: editing) { _, id in
            // Focus the editor once it exists.
            DispatchQueue.main.async { focus = id }
        }
        .onChange(of: focus) { _, now in
            if now == nil, editing != nil { finish() }
        }
        .preference(key: WritingKey.self, value: editing != nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(folder.name) workbench")
    }

    /// The style the tray shows: the selected note's, or the one the next note will be written in. Changing it
    /// restyles that note, and new notes follow whatever you used last.
    private var style: Binding<NoteStyle> {
        Binding {
            selected.flatMap { id in notes.first { $0.id == id }?.style } ?? nextStyle
        } set: { new in
            if let id = selected, let i = notes.firstIndex(where: { $0.id == id }) { notes[i].style = new }
            nextStyle = new
            NoteStyle.last = new
        }
    }

    /// Notes and highlighter strokes, laid over the whole length of the mat, in the same space as its grid.
    private func writing(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in tapMat(at: p, width: width) }
                .gesture(tool == .highlight ? sweeping : nil)
                .onContinuousHover { phase in
                    if case .active = phase { (tool == .text ? NSCursor.iBeam : tool == .highlight ? NSCursor.crosshair : NSCursor.arrow).set() }
                }
            // Highlighter goes under the writing, so the ink stays crisp on top of it.
            Canvas { ctx, _ in
                ctx.translateBy(x: Mat.band, y: Mat.band)
                for stroke in strokes { draw(stroke, in: &ctx, selected: stroke.id == selectedStroke) }
                if let sweep { draw(Stroke(points: sweep, ink: highlight), in: &ctx, selected: false) }
            }
            .allowsHitTesting(false)
            ForEach($notes) { $note in
                let id = note.id
                NoteView(note: $note, selected: selected == id, editing: editing == id, focus: $focus, finish: finish)
                    .offset(x: Mat.band + note.x, y: Mat.band + note.y)
                    .gesture(editing == id ? nil : drag(id, width: width))
                    .onTapGesture(count: 2) { if editing != id { edit(id) } }
                    .simultaneousGesture(TapGesture().onEnded {
                        guard editing != id else { return }
                        selectedStroke = nil
                        if tool == .text { edit(id) } else { finish(); selected = id }
                    })
                    // With the highlighter in hand, sweeps go straight across notes.
                    .allowsHitTesting(tool != .highlight)
            }
        }
    }

    private func draw(_ stroke: Stroke, in ctx: inout GraphicsContext, selected: Bool) {
        let path = stroke.path
        var ink = ctx
        ink.blendMode = .screen
        ink.stroke(path, with: .color(NoteStyle.color(stroke.ink).opacity(0.72)),
                   style: StrokeStyle(lineWidth: Stroke.width, lineCap: .butt, lineJoin: .round))
        if selected {
            let outline = path.strokedPath(StrokeStyle(lineWidth: Stroke.width + 6, lineCap: .butt, lineJoin: .round))
            ctx.stroke(outline, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// A highlighter sweep: follows the pointer, and settles straight if it was nearly straight.
    private var sweeping: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let p = CGPoint(x: value.location.x - Mat.band, y: value.location.y - Mat.band)
                if sweep == nil {
                    selected = nil
                    selectedStroke = nil
                    sweep = [CGPoint(x: value.startLocation.x - Mat.band, y: value.startLocation.y - Mat.band)]
                }
                if let last = sweep?.last, hypot(p.x - last.x, p.y - last.y) > 2 { sweep?.append(p) }
            }
            .onEnded { _ in
                if let points = sweep, points.count > 1 {
                    strokes.append(Stroke(points: Stroke.settle(points), ink: highlight))
                }
                sweep = nil
            }
    }

    /// Notes move 1:1 with the pointer and stay on the grid.
    private func drag(_ id: Note.ID, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
                if moving?.id != id {
                    finish()
                    moving = (id, CGPoint(x: notes[i].x, y: notes[i].y))
                    selected = id
                }
                guard let from = moving?.from else { return }
                notes[i].x = min(max(0, from.x + value.translation.width), max(0, width - Mat.band * 2 - 24))
                notes[i].y = max(0, from.y + value.translation.height)
            }
            .onEnded { _ in
                moving = nil
                NotesStore.shared.set(notes, in: folder.id)
            }
    }

    /// Clicking the bare mat ends any writing; with the marker it starts a new note right where you clicked.
    private func tapMat(at p: CGPoint, width: CGFloat) {
        if editing != nil { finish(); return }
        guard tool == .text else {
            selected = nil
            // In select mode, a click on a highlighter stroke picks it.
            let grid = CGPoint(x: p.x - Mat.band, y: p.y - Mat.band)
            selectedStroke = tool == .select ? strokes.last(where: { $0.contains(grid) })?.id : nil
            return
        }
        let gridWidth = width - Mat.band * 2
        // Put the first line's middle on the click.
        let x = min(max(0, p.x - Mat.band - NoteView.inset.leading), max(0, gridWidth - 24))
        let y = max(0, p.y - Mat.band - nextStyle.size * 0.65)
        let note = Note(text: "", x: x, y: y, style: nextStyle)
        selectedStroke = nil
        notes.append(note)
        selected = note.id
        editing = note.id
        // One note at a time, then back to selecting, as in most drawing apps.
        tool = .select
    }

    private func edit(_ id: Note.ID) {
        if editing != nil, editing != id { finish() }
        selected = id
        editing = id
    }

    /// Stops writing; a note left empty is thrown away.
    private func finish() {
        guard let id = editing else { return }
        editing = nil
        focus = nil
        if let i = notes.firstIndex(where: { $0.id == id }), notes[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.remove(at: i)
            if selected == id { selected = nil }
        }
    }

    private func deleteSelected() {
        if let id = selectedStroke {
            strokes.removeAll { $0.id == id }
            selectedStroke = nil
        } else if let id = selected {
            notes.removeAll { $0.id == id }
            selected = nil
        }
    }
}

/// True while a note is being written, so the window's own shortcuts (Esc to go back) stand aside.
struct WritingKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// One section of the mat: its slice of the grid and the side rulers, numbered from the top of the mat.
private struct MatSection: View {
    let index: Int

    var body: some View {
        Canvas { ctx, size in
            let top = CGFloat(index) * Mat.section
            let left = Mat.band, right = size.width - Mat.band
            guard right > left else { return }

            // Grid: half-inch lines, with every inch a touch stronger.
            var half = Path(), whole = Path()
            var k = 1
            var x = left + Mat.inch / 2
            while x < right - 0.5 {
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                if k % 2 == 0 { whole.addPath(line) } else { half.addPath(line) }
                x += Mat.inch / 2; k += 1
            }
            var n = Int((top / (Mat.inch / 2)).rounded(.up))
            while CGFloat(n) * Mat.inch / 2 < top + size.height {
                let y = CGFloat(n) * Mat.inch / 2 - top
                if n > 0 {
                    var line = Path(); line.move(to: CGPoint(x: left, y: y)); line.addLine(to: CGPoint(x: right, y: y))
                    if n % 2 == 0 { whole.addPath(line) } else { half.addPath(line) }
                }
                n += 1
            }
            ctx.stroke(half, with: .color(Mat.grid), lineWidth: 1)
            ctx.stroke(whole, with: .color(Mat.gridInch), lineWidth: 1)
            var edges = Path()
            edges.move(to: CGPoint(x: left, y: 0)); edges.addLine(to: CGPoint(x: left, y: size.height))
            edges.move(to: CGPoint(x: right, y: 0)); edges.addLine(to: CGPoint(x: right, y: size.height))
            ctx.stroke(edges, with: .color(Mat.frame), lineWidth: 1)

            // Side rulers: eighth-inch ticks in from each edge, numbered every inch from the top of the mat.
            var ticks = Path()
            var e = Int((top / (Mat.inch / 8)).rounded(.up))
            while CGFloat(e) * Mat.inch / 8 < top + size.height {
                let y = CGFloat(e) * Mat.inch / 8 - top
                let len = Mat.tickLength(e)
                ticks.move(to: CGPoint(x: 8, y: y)); ticks.addLine(to: CGPoint(x: 8 + len, y: y))
                ticks.move(to: CGPoint(x: size.width - 8, y: y)); ticks.addLine(to: CGPoint(x: size.width - 8 - len, y: y))
                if e % 8 == 0, e > 0 {
                    let label = Text("\(e / 8)").font(.system(size: 10, weight: .medium)).foregroundStyle(Mat.number)
                    ctx.draw(label, at: CGPoint(x: 29, y: y))
                    ctx.draw(label, at: CGPoint(x: size.width - 29, y: y))
                }
                e += 1
            }
            ctx.stroke(ticks, with: .color(Mat.tick), lineWidth: 1)
        }
    }
}

/// The ruler across the top, pinned while the mat scrolls beneath it.
private struct TopRuler: View {
    var body: some View {
        Canvas { ctx, size in
            let left = Mat.band, right = size.width - Mat.band
            guard right > left else { return }
            var ticks = Path()
            var e = 0
            var x = left
            while x <= right + 0.5 {
                let len = Mat.tickLength(e)
                ticks.move(to: CGPoint(x: x, y: 8)); ticks.addLine(to: CGPoint(x: x, y: 8 + len))
                if e % 8 == 0, e > 0, x < right - 4 {
                    ctx.draw(Text("\(e / 8)").font(.system(size: 10, weight: .medium)).foregroundStyle(Mat.number), at: CGPoint(x: x, y: 29))
                }
                x += Mat.inch / 8; e += 1
            }
            ctx.stroke(ticks, with: .color(Mat.tick), lineWidth: 1)
            var edge = Path()
            edge.move(to: CGPoint(x: left, y: size.height - 0.5)); edge.addLine(to: CGPoint(x: right, y: size.height - 0.5))
            ctx.stroke(edge, with: .color(Mat.frame), lineWidth: 1)
            ctx.draw(Text("inch").font(.system(size: 9, weight: .medium)).foregroundStyle(Mat.number),
                     at: CGPoint(x: Mat.band / 2 + 2, y: Mat.band / 2 + 4))
        }
        .background(Screen.canvas)
        .allowsHitTesting(false)
    }
}
