// The skull in the corner of Home, saying a quote in a speech bubble. The quotes are the notes you write in a
// project called "Quotes"; until there is one, it says a few lines of its own. Click it for the next quote; it
// also moves on by itself every couple of minutes.
import AppKit
import SwiftUI

struct QuoteSkull: View {
    let folders: [Folder]
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var index = Int.random(in: 0..<1000)
    @State private var hop = false

    static let skull: NSImage? = Bundle.main.url(forResource: "05-skull", withExtension: "png", subdirectory: "Loader").flatMap(NSImage.init(contentsOf:))

    /// Said until you make a project called "Quotes".
    static let ownLines = [
        "Make it exist first. Make it good later.",
        "Start ugly. Tidy up never.",
        "Tiny steps still count.",
        "Messy pages are working pages.",
        "You don't need permission to start.",
        "One idea at a time. Toss the rest in the salad.",
        "Ship the sketch.",
    ]

    /// Every note in every project named "Quotes", in the order they were written.
    @MainActor private var yours: [String] {
        folders
            .filter { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Quotes") == .orderedSame }
            .flatMap { NotesStore.shared.notes(in: $0.id) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let mine = yours
        let lines = mine.isEmpty ? Self.ownLines : mine
        let quote = lines[index % lines.count]
        HStack(alignment: .bottom, spacing: 4) {
            Button(action: next) {
                Group {
                    if let skull = Self.skull {
                        Image(nsImage: skull).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Text("💀").font(.system(size: 44))
                    }
                }
                .frame(width: 64, height: 58)
                .rotationEffect(.degrees(hop ? -8 : 0), anchor: .bottom)
                .offset(y: hop ? -8 : 0)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Next quote")
            .accessibilityLabel("Next quote")

            Bubble(text: quote, hint: mine.isEmpty ? "Make a project called “Quotes” and I'll say yours." : nil)
                .id(quote)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                .padding(.bottom, 30)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: index)
        .task {
            // A fresh quote every couple of minutes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                next()
            }
        }
    }

    private func next() {
        index += 1
        guard !reduced else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { hop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hop = false }
        }
    }
}

/// A cream comic speech bubble with an ink outline, its tail pointing down-left at the skull.
private struct Bubble: View {
    let text: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.custom("Caveat", size: 23).weight(.semibold))
                .foregroundStyle(Color(white: 0.08))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 360, alignment: .leading)
        .background(BubbleShape().fill(Sticker.cream))
        .overlay(BubbleShape().stroke(Color.black, lineWidth: 1.5))
        .background(BubbleShape().fill(Color.black).offset(x: 2.5, y: 3))
        .fixedSize()
    }
}

/// A rounded box with a little tail off its bottom-left corner.
private struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        let box = Path(roundedRect: r, cornerRadius: 14, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: r.minX + 14, y: r.maxY - 1))
        tail.addQuadCurve(to: CGPoint(x: r.minX - 10, y: r.maxY + 12), control: CGPoint(x: r.minX + 8, y: r.maxY + 8))
        tail.addQuadCurve(to: CGPoint(x: r.minX + 30, y: r.maxY - 1), control: CGPoint(x: r.minX + 14, y: r.maxY + 10))
        tail.closeSubpath()
        // One outline round both, so the stroke doesn't cross where the tail meets the box.
        return box.union(tail)
    }
}
