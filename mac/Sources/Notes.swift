// Notes and highlighter strokes on a folder's mat: what they are, where each folder's are kept, and how a note
// looks (read-only, selected, or being written) in its own face, weight, size and ink.
import AppKit
import CoreText
import SwiftUI

/// The handwriting notes are written in by default: Caveat, bundled in Resources/Fonts (SIL Open Font License).
enum Handwriting {
    /// Makes the bundled font available to the app. Call once at launch.
    static func register() {
        guard let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// How a note is set: the same for the whole note.
struct NoteStyle: Equatable, Codable {
    enum Face: String, Codable, CaseIterable {
        case hand, type, plain
        var name: String { self == .hand ? "Handwriting" : self == .type ? "Typewriter" : "Plain" }
    }

    enum Weight: String, Codable, CaseIterable {
        case regular, medium, semibold, bold
        var name: String { rawValue.capitalized }
        var font: Font.Weight { self == .regular ? .regular : self == .medium ? .medium : self == .semibold ? .semibold : .bold }
    }

    var face: Face = .hand
    var weight: Weight = .medium
    var size: CGFloat = 28
    /// Ink, as a hex colour from `inks`.
    var ink: String = "F2F2F2"

    /// The sizes the − and + buttons step through.
    static let sizes: [CGFloat] = [14, 18, 22, 28, 36, 48, 64, 80, 96]
    /// White, grey, then the palette: skull pink, leaf green, bowl lavender, warning amber, danger red.
    static let inks = ["F2F2F2", "9A9A9A", "FF78D2", "58F584", "9FA9FC", "FFB334", "FF5352"]

    func font(_ face: Face? = nil, weight: Weight? = nil, size: CGFloat? = nil) -> Font {
        let w = (weight ?? self.weight).font, s = size ?? self.size
        switch face ?? self.face {
        case .hand: return .custom("Caveat", size: s).weight(w)
        case .type: return .custom("AmericanTypewriter", size: s * 0.72).weight(w)
        case .plain: return .system(size: s * 0.72, weight: w)
        }
    }

    var color: Color { Self.color(ink) }
    static func color(_ hexString: String) -> Color { hex(UInt32(hexString, radix: 16) ?? 0xF2F2F2) }

    /// Notes grow sideways as you type until about six inches wide (more for big type), then wrap.
    var maxWidth: CGFloat { max(380, size * 13) }

    /// The style the next note starts in: whatever you used last.
    static var last: NoteStyle {
        get { UserDefaults.standard.data(forKey: "noteStyle").flatMap { try? JSONDecoder().decode(NoteStyle.self, from: $0) } ?? NoteStyle() }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "noteStyle") } }
    }
}

struct Note: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    /// Top-left corner, in points from the top-left of the mat's grid.
    var x: CGFloat
    var y: CGFloat
    var style = NoteStyle()
}

extension Note {
    /// Notes saved before styles existed come back in the default style.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        style = try c.decodeIfPresent(NoteStyle.self, forKey: .style) ?? NoteStyle()
    }
}

/// A sweep of highlighter across the mat.
struct Stroke: Identifiable, Equatable, Codable {
    var id = UUID()
    /// Points in grid space, like a note's position.
    var points: [CGPoint]
    var ink: String

    static let width: CGFloat = 22
    /// Fluorescent yellow, green, pink, blue and orange.
    static let inks = ["FFF04A", "7CFF6B", "FF6FD8", "6FD3FF", "FFA94D"]

    /// The line through the points, smoothed into curves.
    var path: Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 2 else { points.dropFirst().forEach { p.addLine(to: $0) }; return p }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: points[i])
        }
        p.addLine(to: points[points.count - 1])
        return p
    }

    /// A sweep that's nearly straight becomes perfectly straight, the way you'd run a highlighter along a line.
    static func settle(_ points: [CGPoint]) -> [CGPoint] {
        guard let a = points.first, let b = points.last, points.count > 2 else { return points }
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 24 else { return points }
        // How far the sweep strays from the line between its ends.
        func off(_ p: CGPoint) -> CGFloat {
            let cross: CGFloat = (b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)
            return abs(cross) / length
        }
        let worst = points.map(off).max() ?? 0
        return worst < 7 ? [a, b] : points
    }

    func contains(_ p: CGPoint) -> Bool {
        path.strokedPath(StrokeStyle(lineWidth: Self.width + 6, lineCap: .round, lineJoin: .round)).contains(p)
    }
}

/// Every folder's notes and strokes, saved between launches.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    private var notes: [UUID: [Note]] = [:]
    private var strokes: [UUID: [Stroke]] = [:]

    func notes(in folder: Folder.ID) -> [Note] {
        if let found = notes[folder] { return found }
        let loaded: [Note] = load("notes", folder) ?? []
        notes[folder] = loaded
        return loaded
    }

    func set(_ list: [Note], in folder: Folder.ID) {
        notes[folder] = list
        save(list, "notes", folder)
    }

    func strokes(in folder: Folder.ID) -> [Stroke] {
        if let found = strokes[folder] { return found }
        let loaded: [Stroke] = load("strokes", folder) ?? []
        strokes[folder] = loaded
        return loaded
    }

    func set(_ list: [Stroke], in folder: Folder.ID) {
        strokes[folder] = list
        save(list, "strokes", folder)
    }

    private func load<T: Decodable>(_ kind: String, _ folder: Folder.ID) -> T? {
        UserDefaults.standard.data(forKey: "\(kind).\(folder.uuidString)").flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ kind: String, _ folder: Folder.ID) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "\(kind).\(folder.uuidString)") }
    }
}

/// One note on the mat. While it's being written it's an editor of exactly the same size and position, so
/// nothing jumps between writing and reading.
struct NoteView: View {
    @Binding var note: Note
    let selected: Bool
    let editing: Bool
    var focus: FocusState<Note.ID?>.Binding
    let finish: () -> Void

    /// The editor's own inset, matched by the read-only text.
    static let inset = EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)

    var body: some View {
        Hug(maxWidth: note.style.maxWidth) { sizedText }
            .frame(minWidth: 40, alignment: .leading)
            .background { outline }
            .contentShape(Rectangle())
            .accessibilityLabel(note.text.isEmpty ? "Empty note" : note.text)
    }

    /// Sized by the text itself (plus room for the next letter while writing), with the editor laid over it.
    private var sizedText: some View {
        Text(note.text.isEmpty ? " " : note.text + (editing ? "  " : ""))
            .font(note.style.font())
            .padding(Self.inset)
            .opacity(editing ? 0 : 1)
            .foregroundStyle(note.style.color)
            .overlay { if editing { editor } }
    }

    private var editor: some View {
        TextEditor(text: $note.text)
            .font(note.style.font())
            .foregroundStyle(note.style.color)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .textEditorStyle(.plain)
            .focused(focus, equals: note.id)
            .onExitCommand(perform: finish)
    }

    private var outline: some View {
        let opacity: Double = editing ? 0.22 : selected ? 0.4 : 0
        let dash: [CGFloat] = editing ? [4, 3] : []
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.white.opacity(opacity), style: StrokeStyle(lineWidth: 1, dash: dash))
            .padding(-4)
    }
}

/// Lays out its one child at the child's own size, but never wider than `maxWidth`: so text hugs what's
/// written and wraps once it reaches the limit.
struct Hug: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
