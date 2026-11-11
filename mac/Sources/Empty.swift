// Home with no projects yet: a die-cut sticker on the canvas saying "GO MAKE SOMETHING f***ing GREAT", a pill below it that
// makes the first idea or book, three keycap stickers and the Skull Salad mark stuck around it.
import AppKit
import SwiftUI

enum Sticker {
    static let cream = hex(0xF2EEE6)
    static let ink = Color.black
    /// The black outline round the letters, the cream border round the sticker, and its thin black edge.
    static let outline: CGFloat = 3.5
    static let border: CGFloat = 11
    static let edge: CGFloat = 1.6
    /// The letters' hard shadow, like a block print.
    static let drop = CGSize(width: 4, height: 5)
}

struct EmptyHome: View {
    @Binding var choosing: Bool
    let add: (Folder.Kind) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.offscreen) private var offscreen
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                stuck(Keycap(color: hex(0x9FA9FC), symbol: "cursorarrow"), angle: -12, x: -262, y: -66, order: 1)
                stuck(Keycap(color: hex(0xFF78D2), symbol: "hand.point.up.left.fill"), angle: 8, x: 40, y: -138, order: 2)
                stuck(Keycap(color: Leaf.c300, symbol: "bolt.fill"), angle: -9, x: -268, y: 112, order: 3)
                stuck(MarkSticker(), angle: 10, x: 262, y: 18, order: 4)
                MainSticker(choosing: $choosing, add: add)
                    .scaleEffect(visible ? 1 : 0.92)
                    .rotationEffect(.degrees(visible ? -3 : -6))
                    .opacity(visible ? 1 : 0)
            }
            Spacer()
            Text("click the pill, or press ⌘N, to start your first idea or book")
                .font(.custom("BradleyHandITCTT-Bold", size: 17))
                .foregroundStyle(Sticker.cream.opacity(0.75))
                .opacity(visible ? 1 : 0)
                .padding(.bottom, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduced else { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = true }
        }
    }

    /// Snapshots and Reduce Motion skip the pop-in.
    private var visible: Bool { shown || offscreen || reduced }

    /// A small sticker slapped on around the main one, each a beat after the last.
    private func stuck(_ sticker: some View, angle: Double, x: CGFloat, y: CGFloat, order: Int) -> some View {
        sticker
            .rotationEffect(.degrees(visible ? angle : angle - 14))
            .scaleEffect(visible ? 1 : 0.7)
            .opacity(visible ? 1 : 0)
            .offset(x: x, y: y)
            .animation(reduced ? nil : .spring(response: 0.45, dampingFraction: 0.62).delay(0.08 * Double(order)), value: shown)
    }
}

/// The words cut out as a sticker, with the pill below.
private struct MainSticker: View {
    @Binding var choosing: Bool
    let add: (Folder.Kind) -> Void
    @State private var hover = false

    var body: some View {
        ZStack {
            // Die-cut: the whole artwork grown by the border, in cream with a thin black edge.
            Outlined(radius: Sticker.border + Sticker.edge) { art(.black) }
            Outlined(radius: Sticker.border) { art(Sticker.cream) }
            // The letters' block shadow and outline.
            Outlined(radius: Sticker.outline) { words(.black) }
                .offset(Sticker.drop)
            Outlined(radius: Sticker.outline) { words(.black) }
            words(nil)
            pill
        }
        .fixedSize()
    }

    /// Everything the die-cut follows (the words and their shadow), in one flat colour. The pill sits apart,
    /// just below it.
    private func art(_ fill: Color) -> some View {
        ZStack {
            words(fill).offset(Sticker.drop)
            words(fill)
        }
    }

    static let pillSize = CGSize(width: 236, height: 40)
    static let pillOffset = CGSize(width: -10, height: 34)

    /// "GO MAKE / SOMETHING / f***ing GREAT": white condensed capitals with "f***ing" in pink script.
    /// `fill` flattens it to one colour.
    private func words(_ fill: Color?) -> some View {
        let caps = Font.system(size: 64, weight: .black).width(.condensed)
        return VStack(alignment: .trailing, spacing: -13) {
            Text("GO MAKE")
                .font(caps)
                .foregroundStyle(fill ?? .white)
            Text("SOMETHING")
                .font(caps)
                .foregroundStyle(fill ?? .white)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("f***ing")
                    .font(.custom("SnellRoundhand-Black", size: 58))
                    .foregroundStyle(fill ?? Leaf.sticker)
                    .rotationEffect(.degrees(-6))
                    .offset(y: 6)
                Text("GREAT")
                    .font(caps)
                    .foregroundStyle(fill ?? .white)
            }
        }
        .tracking(-0.5)
        .fixedSize()
        // The script's swashes overhang its layout box; pad so every copy of the words keeps them whole.
        .padding(28)
    }

    private var pill: some View {
        ZStack(alignment: .bottomTrailing) {
            // Stand-ins for the words, so the pill lands in the same place as in the die-cut.
            words(.clear).offset(Sticker.drop).hidden()
            Button { choosing = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .heavy))
                    Text("new idea or book").font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Sticker.ink)
                .frame(width: Self.pillSize.width - 8, height: Self.pillSize.height - 8)
                .background(Capsule().fill(hover ? .white : Sticker.cream))
                .overlay(Capsule().strokeBorder(Sticker.ink, lineWidth: 2))
                .background(Capsule().fill(Sticker.ink).offset(x: 2.5, y: 3))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
            .newChooser(isPresented: $choosing, add: add)
            .help("New idea or book (⌘N)")
            .offset(x: Self.pillOffset.width - 4, y: Self.pillOffset.height - 4)
        }
    }
}

/// A chunky keycap: darker bevelled sides, a lighter top with a white-on-black icon, all in a cream die-cut.
private struct Keycap: View {
    let color: Color
    let symbol: String

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let top = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            outer.fill(color)
                .overlay(outer.fill(Color.black.opacity(0.22)))
            // Bevel creases from each corner of the top to the corners of the cap.
            Canvas { ctx, size in
                let inset: CGFloat = 9
                var creases = Path()
                for (a, b) in [(CGPoint(x: 0, y: 0), CGPoint(x: inset, y: inset - 2)),
                               (CGPoint(x: size.width, y: 0), CGPoint(x: size.width - inset, y: inset - 2)),
                               (CGPoint(x: 0, y: size.height), CGPoint(x: inset, y: size.height - inset - 2)),
                               (CGPoint(x: size.width, y: size.height), CGPoint(x: size.width - inset, y: size.height - inset - 2))] {
                    creases.move(to: a); creases.addLine(to: b)
                }
                ctx.stroke(creases, with: .color(.black), lineWidth: 1.4)
            }
            top.fill(color)
                .overlay(top.strokeBorder(Color.black, lineWidth: 1.6))
                .padding(9)
                .offset(y: -2)
            Outlined(radius: 1.2) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
            }
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
            .offset(y: -2)
        }
        .frame(width: 58, height: 58)
        .overlay(outer.strokeBorder(Color.black, lineWidth: 2.2))
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Sticker.cream))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.black, lineWidth: Sticker.edge))
        .accessibilityHidden(true)
    }
}

/// The Skull Salad mark, cut out with a cream border that follows its shape.
private struct MarkSticker: View {
    static let image: NSImage? = Bundle.main.url(forResource: "mark-128", withExtension: "png", subdirectory: "Loader").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let image = Self.image {
            let mark = Image(nsImage: image).resizable().interpolation(.high).frame(width: 96, height: 96)
            ZStack {
                Outlined(radius: 9 + Sticker.edge) { Color.black.frame(width: 96, height: 96).mask(mark) }
                Outlined(radius: 9) { silhouette(mark) }
                mark
            }
            .accessibilityHidden(true)
        }
    }

    /// The mark flattened to solid cream, keeping only its shape.
    private func silhouette(_ mark: some View) -> some View {
        Sticker.cream.frame(width: 96, height: 96).mask(mark)
    }
}

/// Copies of some artwork pushed out in every direction, flattened into one: a solid outline `radius` wide.
private struct Outlined<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // Enough directions and rings that copies of even a hairline swash overlap with no gaps between them.
        let directions = max(16, Int(radius * 4))
        ZStack {
            ForEach(0..<directions, id: \.self) { i in
                let a = Double(i) / Double(directions) * 2 * .pi
                ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { f in
                    content.offset(x: cos(a) * radius * f, y: sin(a) * radius * f)
                }
            }
        }
        .padding(radius)
        .drawingGroup()
        .padding(-radius)
        .allowsHitTesting(false)
    }
}
