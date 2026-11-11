// The workbench inside a folder: a self-healing cutting mat in black and white. A ruler band runs round
// the edge (inch numbers, eighth-inch ticks); inside it the half-inch grid is only just visible.
import SwiftUI

enum Mat {
    /// One "inch" on the mat.
    static let inch: CGFloat = 64
    /// Width of the ruler band between the canvas edge and the grid.
    static let band: CGFloat = 40
    static let grid = Color.white.opacity(0.045)
    static let gridInch = Color.white.opacity(0.075)
    static let frame = Color.white.opacity(0.12)
    static let tick = Color.white.opacity(0.2)
    static let number = Color.white.opacity(0.3)
}

struct Workbench: View {
    let folder: Folder

    var body: some View {
        Canvas { ctx, size in
            let inner = CGRect(x: Mat.band, y: Mat.band, width: size.width - Mat.band * 2, height: size.height - Mat.band * 2)
            guard inner.width > 0, inner.height > 0 else { return }

            // Grid: half-inch lines, with every inch a touch stronger.
            var half = Path(), whole = Path()
            var i = 1
            var x = inner.minX + Mat.inch / 2
            while x < inner.maxX - 0.5 {
                var line = Path(); line.move(to: CGPoint(x: x, y: inner.minY)); line.addLine(to: CGPoint(x: x, y: inner.maxY))
                if i % 2 == 0 { whole.addPath(line) } else { half.addPath(line) }
                x += Mat.inch / 2; i += 1
            }
            i = 1
            var y = inner.minY + Mat.inch / 2
            while y < inner.maxY - 0.5 {
                var line = Path(); line.move(to: CGPoint(x: inner.minX, y: y)); line.addLine(to: CGPoint(x: inner.maxX, y: y))
                if i % 2 == 0 { whole.addPath(line) } else { half.addPath(line) }
                y += Mat.inch / 2; i += 1
            }
            ctx.stroke(half, with: .color(Mat.grid), lineWidth: 1)
            ctx.stroke(whole, with: .color(Mat.gridInch), lineWidth: 1)
            ctx.stroke(Path(inner), with: .color(Mat.frame), lineWidth: 1)

            // Ruler: eighth-inch ticks hanging in from each edge, numbered every inch.
            var ticks = Path()
            func tickLength(_ n: Int) -> CGFloat { n % 8 == 0 ? 12 : n % 4 == 0 ? 8 : n % 2 == 0 ? 5 : 3 }
            var n = 0
            x = inner.minX
            while x <= inner.maxX + 0.5 {
                let len = tickLength(n)
                ticks.move(to: CGPoint(x: x, y: 8)); ticks.addLine(to: CGPoint(x: x, y: 8 + len))
                ticks.move(to: CGPoint(x: x, y: size.height - 8)); ticks.addLine(to: CGPoint(x: x, y: size.height - 8 - len))
                if n % 8 == 0, n > 0, x < inner.maxX - 4 {
                    let label = Text("\(n / 8)").font(.system(size: 10, weight: .medium)).foregroundStyle(Mat.number)
                    ctx.draw(label, at: CGPoint(x: x, y: 29))
                    ctx.draw(label, at: CGPoint(x: x, y: size.height - 29))
                }
                x += Mat.inch / 8; n += 1
            }
            n = 0
            y = inner.minY
            while y <= inner.maxY + 0.5 {
                let len = tickLength(n)
                ticks.move(to: CGPoint(x: 8, y: y)); ticks.addLine(to: CGPoint(x: 8 + len, y: y))
                ticks.move(to: CGPoint(x: size.width - 8, y: y)); ticks.addLine(to: CGPoint(x: size.width - 8 - len, y: y))
                if n % 8 == 0, n > 0, y < inner.maxY - 4 {
                    let label = Text("\(n / 8)").font(.system(size: 10, weight: .medium)).foregroundStyle(Mat.number)
                    ctx.draw(label, at: CGPoint(x: 29, y: y))
                    ctx.draw(label, at: CGPoint(x: size.width - 29, y: y))
                }
                y += Mat.inch / 8; n += 1
            }
            ctx.stroke(ticks, with: .color(Mat.tick), lineWidth: 1)

            // Corner marks, like the printing on a real mat.
            ctx.draw(Text("inch").font(.system(size: 9, weight: .medium)).foregroundStyle(Mat.number),
                     at: CGPoint(x: Mat.band / 2 + 2, y: Mat.band / 2 + 4))
            ctx.draw(Text("SKULL SALAD · SELF-HEALING MAT").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(Mat.number),
                     at: CGPoint(x: inner.maxX - 10, y: inner.maxY - 12), anchor: .trailing)
        }
        .accessibilityLabel("\(folder.name) workbench")
    }
}
