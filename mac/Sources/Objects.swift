// The project thumbnails as real objects. Each one is modelled as a small 3D scene (curled sheets of grainy paper
// held by a steel paper clip; a card-covered notebook bound with a glossy plastic coil), lit like a desk under a
// softbox, and rendered with soft cast shadows and contact shading. What's printed on them is drawn into their
// textures, so the name takes on the paper's grain and the light.
import AppKit
import CoreImage
import SceneKit
import SwiftUI

enum Objects {
    /// The render covers the grid slot plus a margin for shadows to fall into.
    static let margin: CGFloat = 46
    static var canvas: CGSize { CGSize(width: ProjectGrid.slot.width + margin * 2, height: ProjectGrid.slot.height + margin * 2) }
    /// Texture resolution, in pixels per point.
    static let texel: CGFloat = 4

    struct Key: Hashable {
        let kind: Folder.Kind
        let name: String
        let date: String
        let open: Bool
        let scale: CGFloat
    }

    static func key(_ folder: Folder, open: Bool, scale: CGFloat) -> Key {
        Key(kind: folder.kind, name: folder.name, date: folder.date.formatted(.dateTime.year().month().day()), open: open, scale: scale)
    }

    /// Renders one object. The printing is drawn here on the main actor; the scene renders on a background queue.
    @MainActor static func render(_ folder: Folder, open: Bool, scale: CGFloat) async -> NSImage? {
        let print = Prints.make(folder)
        return await withCheckedContinuation { done in
            queue.async { done.resume(returning: renderScene(kind: folder.kind, print: print, open: open, scale: scale)) }
        }
    }

    /// The same, all at once, for snapshots.
    @MainActor static func renderNow(_ folder: Folder, open: Bool, scale: CGFloat) -> NSImage? {
        let print = Prints.make(folder)
        return queue.sync { renderScene(kind: folder.kind, print: print, open: open, scale: scale) }
    }

    private static let queue = DispatchQueue(label: "skullsalad.objects", qos: .userInitiated)
    private static var renderer: SCNRenderer?

    private static func renderScene(kind: Folder.Kind, print: CGImage?, open: Bool, scale: CGFloat) -> NSImage? {
        if renderer == nil {
            renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer?.autoenablesDefaultLighting = false
        }
        guard let renderer else { return nil }
        let scene = Stage.scene()
        let object = kind == .idea ? PaperStack.node(print: print, open: open) : SpiralBook.node(print: print, open: open)
        scene.rootNode.addChildNode(object)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        image.size = canvas
        return image
    }
}

/// Rendered objects, kept while the app runs; views ask for one and redraw when it's ready.
@MainActor
final class ObjectCache: ObservableObject {
    static let shared = ObjectCache()
    private var images: [Objects.Key: NSImage] = [:]
    private var pending: Set<Objects.Key> = []

    func image(_ folder: Folder, open: Bool, scale: CGFloat, now: Bool = false) -> NSImage? {
        let key = Objects.key(folder, open: open, scale: scale)
        if let image = images[key] { return image }
        if now {
            let image = Objects.renderNow(folder, open: open, scale: scale)
            images[key] = image
            return image
        }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        Task {
            let image = await Objects.render(folder, open: open, scale: scale)
            pending.remove(key)
            images[key] = image
            objectWillChange.send()
        }
        return nil
    }
}

/// A project drawn as its real object, with a crossfade to its "peeking" pose on hover.
struct ObjectThumbnail: View {
    let folder: Folder
    let open: Bool
    @ObservedObject private var cache = ObjectCache.shared
    @Environment(\.displayScale) private var scale
    @Environment(\.offscreen) private var offscreen

    var body: some View {
        let closed = cache.image(folder, open: false, scale: scale, now: offscreen)
        // Render the open pose in the background as soon as the closed one is up, so the first hover is instant.
        let peek = closed == nil ? nil : cache.image(folder, open: true, scale: scale, now: offscreen && open)
        ZStack {
            // The closed pose stays solid underneath while the open one fades in over it, so nothing behind
            // ever shows through mid-fade.
            if let closed {
                Image(nsImage: closed).resizable()
            }
            if let peek {
                Image(nsImage: peek).resizable().opacity(open ? 1 : 0)
            }
        }
        .frame(width: Objects.canvas.width, height: Objects.canvas.height)
        .padding(-Objects.margin)
        .frame(width: ProjectGrid.slot.width, height: ProjectGrid.slot.height)
        .animation(.easeOut(duration: 0.2), value: open)
        .animation(.easeOut(duration: 0.25), value: closed == nil)
    }
}

// MARK: - Stage

/// The desk, the light and the camera shared by every object.
private enum Stage {
    static func scene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Textures.studio
        scene.lightingEnvironment.intensity = 0.9

        // A desk that only shows the shadows falling on it.
        let desk = SCNNode(geometry: SCNPlane(width: 2000, height: 2000))
        let catcher = SCNMaterial()
        catcher.lightingModel = .shadowOnly
        desk.geometry?.materials = [catcher]
        scene.rootNode.addChildNode(desk)

        // Key light: a soft lamp up on the top left, low enough that every edge and curl throws a shadow.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1250
        key.color = NSColor(calibratedRed: 1, green: 0.965, blue: 0.92, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowRadius = 16
        key.shadowSampleCount = 48
        key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.shadowColor = NSColor(white: 0, alpha: 0.58)
        key.orthographicScale = 160
        key.zNear = 1
        key.zFar = 2000
        key.shadowBias = 0.4
        key.automaticallyAdjustsShadowProjection = false
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-330, 400, 420)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        // A little cool fill so the shadow side isn't dead.
        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 110
        fill.color = NSColor(calibratedRed: 0.9, green: 0.94, blue: 1, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        // Nearly straight down, nudged a few degrees so the edges and thickness show.
        let camera = SCNCamera()
        camera.fieldOfView = 12
        camera.projectionDirection = .vertical
        camera.zNear = 100
        camera.zFar = 6000
        let distance = Objects.canvas.height / 2 / tan(6 * .pi / 180)
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(distance * 0.05, -distance * 0.07, distance)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }
}

// MARK: - Idea: a paper stack

private enum PaperStack {
    static let sheet = CGSize(width: 120, height: 150)
    static let gap: CGFloat = 1.0

    /// The loose sheets under the top one, bottom first: offset, turn (degrees), the paper, and how much it curls.
    /// Placed by hand, like a real bundle: edges stepping out on every side, graph and lined paper showing at the
    /// bottom and left, a photo poking out at the top and right.
    private static let sheets: [(x: CGFloat, y: CGFloat, turn: CGFloat, paper: Paper, curl: CGFloat, seed: Int)] = [
        (-1, -13, -0.6, .plain, 0.1, 13),
        (1.5, -12.5, 0.4, .aged, 0.1, 14),
        (-3, -12, -1.5, .kraft, 0.2, 1),
        (0.5, -11, 0.2, .plain, 0.2, 15),
        (6, -9, 3.2, .graph, 0.4, 2),
        (-10, -4, -4.2, .aged, 0.5, 3),
        (9, 3, 2.6, .plain, 0.5, 4),
        (8, 10, 1.8, .photo, 0.2, 5),
        (-7, -8.5, -2.8, .graph, 0.6, 6),
        (-11, 3, -1.4, .lined, 0.6, 7),
        (4, -6, 1.9, .legal, 0.7, 8),
        (10, -2, 3.8, .plain, 0.6, 9),
        (-5, 6, -2.2, .aged, 0.8, 10),
        (2, -3.5, 0.9, .plain, 0.8, 11),
        (-2, 2, -1.1, .plain, 0.9, 12),
    ]

    static func node(print: CGImage?, open: Bool) -> SCNNode {
        let stack = SCNNode()
        for (i, s) in sheets.enumerated() {
            let size = s.paper == .photo ? CGSize(width: sheet.width - 8, height: sheet.height - 6) : sheet
            // Deeper sheets get less light, as they do in a real stack.
            let depth = 0.86 + 0.14 * CGFloat(i) / CGFloat(sheets.count)
            let node = SCNNode(geometry: Paper.sheet(size, curl: s.curl, seed: s.seed, material: s.paper.material(size, seed: s.seed, shade: depth)))
            node.position = SCNVector3(s.x, s.y, CGFloat(i + 1) * gap)
            node.eulerAngles.z = s.turn * .pi / 180
            stack.addChildNode(node)
        }
        let top = SCNNode(geometry: Paper.sheet(sheet, curl: 1.2, seed: 7, material: Paper.dots.material(sheet, seed: 7, print: print)))
        let z = CGFloat(sheets.count + 1) * gap
        top.position = SCNVector3(0, 0, open ? z + 3.5 : z)
        top.eulerAngles.z = (open ? -2.2 : -0.5) * .pi / 180
        if open { top.position.y += 3 }
        top.addChildNode(PaperClip.node(at: CGPoint(x: -sheet.width / 2 + 16, y: sheet.height / 2), under: gap * 3 + (open ? 3.5 : 0)))
        stack.addChildNode(top)
        return stack
    }
}

/// Paper: what each kind looks like, and the gently curled sheet it's printed on.
private enum Paper {
    case plain, aged, dots, graph, lined, legal, kraft, photo

    var tone: NSColor {
        switch self {
        case .plain: NSColor(srgbRed: 0.925, green: 0.905, blue: 0.865, alpha: 1)
        case .aged: NSColor(srgbRed: 0.89, green: 0.86, blue: 0.80, alpha: 1)
        case .dots: NSColor(srgbRed: 0.94, green: 0.925, blue: 0.89, alpha: 1)
        case .graph: NSColor(srgbRed: 0.91, green: 0.895, blue: 0.86, alpha: 1)
        case .lined: NSColor(srgbRed: 0.95, green: 0.945, blue: 0.93, alpha: 1)
        case .legal: NSColor(srgbRed: 0.97, green: 0.91, blue: 0.62, alpha: 1)
        case .kraft: NSColor(srgbRed: 0.72, green: 0.58, blue: 0.42, alpha: 1)
        case .photo: .brown
        }
    }

    func material(_ size: CGSize, seed: Int, print: CGImage? = nil, shade: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        if self == .photo {
            m.diffuse.contents = Textures.photo(size)
            m.roughness.contents = 0.32
            m.metalness.contents = 0.0
        } else {
            m.diffuse.contents = Textures.paper(size, tone: tone, ruling: self, print: print, seed: seed)
            m.multiply.contents = NSColor(white: shade, alpha: 1)
            m.roughness.contents = 0.9
            m.metalness.contents = 0.0
            m.normal.contents = Textures.paperNormal
            m.normal.intensity = 0.14
            m.normal.contentsTransform = SCNMatrix4MakeScale(size.width / 64, size.height / 64, 1)
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
        }
        return m
    }

    /// A sheet as a fine mesh, bowed and curled a little at the corners the way paper lies, never quite flat.
    static func sheet(_ size: CGSize, curl: CGFloat, seed: Int, material: SCNMaterial) -> SCNGeometry {
        let nx = 28, ny = 34
        var rng = Seeded(seed)
        let lift = (rng.next(), rng.next(), rng.next(), rng.next())
        let wave = (rng.next() * 6.28, rng.next() * 6.28)
        func height(_ u: CGFloat, _ v: CGFloat) -> CGFloat {
            // Corners lift a touch, each by its own amount; a slow ripple runs across the middle.
            func corner(_ cu: CGFloat, _ cv: CGFloat, _ k: CGFloat) -> CGFloat {
                let d = max(0, 1 - hypot(u - cu, v - cv) / 0.45)
                return d * d * k
            }
            // The top-left corner stays down: that's where the clip holds the stack.
            let corners = corner(0, 0, lift.0 * 0.1) + corner(1, 0, lift.1) + corner(0, 1, lift.2) + corner(1, 1, lift.3)
            let ripple = sin(u * 5.5 + wave.0) * sin(v * 4.2 + wave.1) * 0.12
            return (corners * 2.6 + ripple) * curl
        }
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], indices: [UInt32] = []
        let e: CGFloat = 0.01
        for j in 0...ny {
            for i in 0...nx {
                let u = CGFloat(i) / CGFloat(nx), v = CGFloat(j) / CGFloat(ny)
                positions.append(SCNVector3((u - 0.5) * size.width, (0.5 - v) * size.height, height(u, v)))
                let dx = (height(u + e, v) - height(u - e, v)) / (2 * e * size.width)
                let dy = -(height(u, v + e) - height(u, v - e)) / (2 * e * size.height)
                let n = SIMD3<Double>(-Double(dx), -Double(dy), 1)
                let len = (n * n).sum().squareRoot()
                normals.append(SCNVector3(n.x / len, n.y / len, n.z / len))
                uvs.append(CGPoint(x: u, y: v))
            }
        }
        for j in 0..<ny {
            for i in 0..<nx {
                let a = UInt32(j * (nx + 1) + i), b = a + 1, c = a + UInt32(nx + 1), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }
}

/// A steel gem clip. Its inner loop lies on the top sheet; its outer loop runs underneath, and the bend between
/// them wraps over the paper's top edge.
private enum PaperClip {
    /// `edge` is the middle of the paper's top edge where the clip sits; `under` is how far below the sheet the
    /// outer loop runs.
    static func node(at edge: CGPoint, under: CGFloat) -> SCNNode {
        let s: CGFloat = 1.5, r: CGFloat = 0.42
        let front = r + 0.15, back = -under
        // The clip in its own flat units, y down from its top, with which side of the paper each stretch is on.
        var path: [(x: CGFloat, y: CGFloat, front: CGFloat)] = []
        func line(_ a: CGPoint, _ b: CGPoint, _ f: CGFloat, steps: Int = 10) {
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                path.append((a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, f))
            }
        }
        func arc(_ c: CGPoint, _ radius: CGFloat, from a0: CGFloat, to a1: CGFloat, _ f: (CGFloat) -> CGFloat, steps: Int = 18) {
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps), a = a0 + (a1 - a0) * t
                path.append((c.x + cos(a) * radius, c.y + sin(a) * radius, f(t)))
            }
        }
        line(CGPoint(x: 0, y: 9), CGPoint(x: 0, y: 31.5), 0)
        arc(CGPoint(x: 4.5, y: 31.5), 4.5, from: .pi, to: 0, { _ in 0 })
        line(CGPoint(x: 9, y: 31.5), CGPoint(x: 9, y: 4.6), 0)
        arc(CGPoint(x: 5.45, y: 4.6), 3.55, from: 0, to: -.pi, { t in t * t * (3 - 2 * t) })
        line(CGPoint(x: 1.9, y: 4.6), CGPoint(x: 1.9, y: 27), 1)
        arc(CGPoint(x: 4.5, y: 27), 2.6, from: .pi, to: 0, { _ in 1 })
        line(CGPoint(x: 7.1, y: 27), CGPoint(x: 7.1, y: 10.5), 1)

        // The paper's edge crosses the clip 6 units down from its top.
        let points = path.map { p in
            SIMD3<Float>(Float(edge.x + p.x * s), Float(edge.y + (6 - p.y) * s), Float(back + (front - back) * p.front))
        }
        let node = SCNNode(geometry: Tube.make(points, radius: Float(r * s), material: steel))
        return node
    }

    static var steel: SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(white: 0.86, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = 0.24
        return m
    }
}

// MARK: - Book: a spiral notebook

private enum SpiralBook {
    static let cover = CGSize(width: 136, height: 168)
    static let board: CGFloat = 1.3
    static let block: CGFloat = 7
    static var thickness: CGFloat { board * 2 + block }
    /// The cover's left edge, leaving room for the coil.
    static let left: CGFloat = -66
    static let holeInset: CGFloat = 5
    static let loops = 23
    static let pitch: CGFloat = 7.05
    static let firstHole: CGFloat = 6.5

    static func holes() -> [CGFloat] { (0..<loops).map { firstHole + CGFloat($0) * pitch } }

    static func node(print: CGImage?, open: Bool) -> SCNNode {
        let book = SCNNode()
        let cx = left + cover.width / 2

        // Back board, then the block of pages, each a hair out from the one above so the edges show.
        let back = SCNNode(geometry: box(cover, board, top: Textures.card(cover, print: nil, holes: holes()), side: card(0.5)))
        back.position = SCNVector3(cx + 2.2, -2.4, board / 2)
        book.addChildNode(back)
        let pagesSize = CGSize(width: cover.width - 3, height: cover.height - 3)
        let pages = SCNNode(geometry: box(pagesSize, block, top: Textures.page(pagesSize, holes: holes()), side: pageEdges))
        pages.position = SCNVector3(cx + 1.6, -1.6, board + block / 2)
        book.addChildNode(pages)

        // The front cover hinges on its left edge.
        let hinge = SCNNode()
        hinge.position = SCNVector3(left, 0, board + block)
        // Coated card, so the softbox shows as a faint sheen across it.
        let front = SCNNode(geometry: box(cover, board, top: Textures.card(cover, print: print, holes: holes()), side: card(0.55), sheen: 0.5))
        front.position = SCNVector3(cover.width / 2, 0, board / 2)
        hinge.addChildNode(front)
        hinge.eulerAngles.y = open ? -5 * .pi / 180 : 0
        book.addChildNode(hinge)

        book.addChildNode(coil())
        return book
    }

    /// A box with its own top face and a plain material round the rest.
    private static func box(_ size: CGSize, _ depth: CGFloat, top: NSImage, side: SCNMaterial, sheen: CGFloat = 0.82) -> SCNGeometry {
        let geometry = SCNBox(width: size.width, height: size.height, length: depth, chamferRadius: 0.35)
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = top
        face.roughness.contents = sheen
        face.normal.contents = Textures.paperNormal
        face.normal.intensity = 0.08
        face.normal.contentsTransform = SCNMatrix4MakeScale(size.width / 64, size.height / 64, 1)
        face.normal.wrapS = .repeat
        face.normal.wrapT = .repeat
        // SCNBox faces: front (+z), right, back, left, top (+y), bottom.
        geometry.materials = [face, side, side, side, side, side]
        return geometry
    }

    private static func card(_ white: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(white: white, alpha: 1)
        m.roughness.contents = 0.85
        return m
    }

    private static var pageEdges: SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = Textures.pageEdges
        m.roughness.contents = 0.9
        return m
    }

    /// The plastic coil: one helix round the spine, each loop passing down through a hole in the top cover and
    /// back up under the book. Its axis sits so the circle meets the cover exactly at the holes.
    private static func coil() -> SCNNode {
        let radius: CGFloat = 7
        let axisZ = thickness / 2
        let holeX = left + holeInset
        let axisX = holeX - sqrt(radius * radius - axisZ * axisZ)
        let atHole = atan2(thickness - axisZ, holeX - axisX)
        let top = cover.height / 2 - firstHole
        let perLoop: CGFloat = 48
        // Run from a little before the first hole to a little after the last, so both cut ends sit under the book.
        var points: [SIMD3<Float>] = []
        for k in stride(from: -0.42 * perLoop, through: (CGFloat(loops - 1) + 0.42) * perLoop, by: 1) {
            let t = k / perLoop
            let angle = atHole + t * 2 * .pi
            points.append(SIMD3<Float>(Float(axisX + cos(angle) * radius), Float(top - t * pitch), Float(axisZ + sin(angle) * radius)))
        }
        return SCNNode(geometry: Tube.make(points, radius: 1.3, material: plastic, sides: 16))
    }

    private static var plastic: SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.2, green: 0.70, blue: 0.30, alpha: 1)
        m.roughness.contents = 0.2
        m.metalness.contents = 0.0
        return m
    }
}

// MARK: - Geometry

/// A round tube swept along a path, for wire and coil.
private enum Tube {
    static func make(_ points: [SIMD3<Float>], radius: Float, material: SCNMaterial, sides: Int = 14) -> SCNGeometry {
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
        let first = simd_normalize(points[1] - points[0])
        var normal = simd_normalize(simd_cross(first, abs(first.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(1, 0, 0)))
        for (k, p) in points.enumerated() {
            let ahead = k + 1 < points.count ? points[k + 1] : p
            let behind = k > 0 ? points[k - 1] : p
            var t = ahead - behind
            if simd_length(t) < 1e-6 { t = first }
            t = simd_normalize(t)
            // Carry the frame along without twisting.
            normal = simd_normalize(normal - simd_dot(normal, t) * t)
            let binormal = simd_cross(t, normal)
            for s in 0..<sides {
                let a = Float(s) / Float(sides) * 2 * .pi
                let n = cos(a) * normal + sin(a) * binormal
                let v = p + n * radius
                positions.append(SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)))
                normals.append(SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z)))
            }
        }
        for k in 0..<(points.count - 1) {
            for s in 0..<sides {
                let a = UInt32(k * sides + s), b = UInt32(k * sides + (s + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                indices += [a, b, c, b, d, c]
            }
        }
        // Rounded ends.
        var elements = [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        for (end, dir) in [(points.first!, -first), (points.last!, simd_normalize(points[points.count - 1] - points[points.count - 2]))] {
            let base = UInt32(positions.count)
            let tip = end + dir * radius * 0.6
            positions.append(SCNVector3(CGFloat(tip.x), CGFloat(tip.y), CGFloat(tip.z)))
            normals.append(SCNVector3(CGFloat(dir.x), CGFloat(dir.y), CGFloat(dir.z)))
            let ring = end == points.first! ? 0 : (points.count - 1) * sides
            var cap: [UInt32] = []
            for s in 0..<sides { cap += [base, UInt32(ring + s), UInt32(ring + (s + 1) % sides)] }
            elements.append(SCNGeometryElement(indices: cap, primitiveType: .triangles))
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)], elements: elements)
        material.isDoubleSided = true
        geometry.materials = Array(repeating: material, count: elements.count)
        return geometry
    }
}

/// A small repeatable random source, so each sheet keeps its own curl from render to render.
private struct Seeded {
    private var state: UInt64
    init(_ seed: Int) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}

// MARK: - Textures

private enum Textures {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Paper fibres: noise streaked in a few directions, plus slow mottling, as a grey multiply layer.
    static let grain: CGImage = {
        let side: CGFloat = 512
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        var fibres = mono
        for angle in [0.3, 1.9, 2.6] {
            let streak = mono.applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 5, kCIInputAngleKey: angle])
            fibres = streak.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: fibres])
        }
        let mottle = mono.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])
        let mixed = fibres.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: mottle])
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.6, kCIInputBrightnessKey: 0.18])
        return context.createCGImage(mixed, from: CGRect(x: 0, y: 0, width: side, height: side))!
    }()

    /// A tiling bump map from the same fibres, so the light catches the paper's tooth.
    static let paperNormal: NSImage = {
        let side = 256
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.9])
        let image = context.createCGImage(noise, from: CGRect(x: 0, y: 0, width: side, height: side))!
        let rep = NSBitmapImageRep(cgImage: image)
        var height = [Double](repeating: 0, count: side * side)
        for y in 0..<side { for x in 0..<side { height[y * side + x] = Double(rep.colorAt(x: x, y: y)?.redComponent ?? 0.5) } }
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 3,
                                   hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<side {
            for x in 0..<side {
                func h(_ x: Int, _ y: Int) -> Double { height[((y + side) % side) * side + (x + side) % side] }
                let dx = (h(x + 1, y) - h(x - 1, y)) * 2, dy = (h(x, y + 1) - h(x, y - 1)) * 2
                let len = (dx * dx + dy * dy + 1).squareRoot()
                out.setColor(NSColor(deviceRed: (-dx / len) * 0.5 + 0.5, green: (-dy / len) * 0.5 + 0.5, blue: (1 / len) * 0.5 + 0.5, alpha: 1), atX: x, y: y)
            }
        }
        let result = NSImage(size: NSSize(width: side, height: side))
        result.addRepresentation(out)
        return result
    }()

    /// A photographer's studio as seen by shiny things: a big softbox up on the left, a strip light on the right,
    /// a pale ceiling and a dark floor.
    static let studio: NSImage = image(CGSize(width: 1024, height: 512)) { ctx, size in
        let colors = [NSColor(white: 0.55, alpha: 1).cgColor, NSColor(white: 0.22, alpha: 1).cgColor, NSColor(white: 0.06, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
        ctx.setFillColor(NSColor(white: 1, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: size.width * 0.28, y: size.height * 0.62, width: size.width * 0.16, height: size.height * 0.24),
                           cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)
        ctx.fill(CGRect(x: size.width * 0.78, y: size.height * 0.45, width: size.width * 0.03, height: size.height * 0.3))
        ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height * 0.94, width: size.width, height: size.height * 0.06))
    }

    /// A sheet's face: its tone, rulings, whatever's printed on it, and grain over everything.
    static func paper(_ size: CGSize, tone: NSColor, ruling: Paper, print: CGImage?, seed: Int) -> NSImage {
        image(CGSize(width: size.width * Objects.texel, height: size.height * Objects.texel)) { ctx, px in
            let k = Objects.texel
            ctx.setFillColor(tone.cgColor)
            ctx.fill(CGRect(origin: .zero, size: px))
            if ruling == .graph {
                ctx.setStrokeColor(NSColor(srgbRed: 0.2, green: 0.22, blue: 0.3, alpha: 0.26).cgColor)
                ctx.setLineWidth(0.45 * k)
                for x in stride(from: 4.5 * k, to: px.width, by: 4.5 * k) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: px.height)) }
                for y in stride(from: 4.5 * k, to: px.height, by: 4.5 * k) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: px.width, y: y)) }
                ctx.strokePath()
            }
            if ruling == .lined || ruling == .legal {
                // Faint blue rules and a red margin, like a sheet torn from a pad.
                ctx.setStrokeColor(NSColor(srgbRed: 0.35, green: 0.5, blue: 0.8, alpha: 0.45).cgColor)
                ctx.setLineWidth(0.45 * k)
                for y in stride(from: px.height - 16 * k, to: 6 * k, by: -6 * k) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: px.width, y: y)) }
                ctx.strokePath()
                ctx.setStrokeColor(NSColor(srgbRed: 0.85, green: 0.3, blue: 0.3, alpha: 0.5).cgColor)
                ctx.move(to: CGPoint(x: 14 * k, y: 0)); ctx.addLine(to: CGPoint(x: 14 * k, y: px.height))
                ctx.strokePath()
            }
            if let print {
                ctx.setBlendMode(.multiply)
                ctx.draw(print, in: CGRect(origin: .zero, size: px))
            }
            grainOver(ctx, px, seed: seed, strength: 0.38)
            // Edges a shade darker, as handled paper gets.
            let edge = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [NSColor(white: 0, alpha: 0).cgColor, NSColor(srgbRed: 0.35, green: 0.28, blue: 0.18, alpha: 0.10).cgColor] as CFArray,
                                  locations: [0.75, 1])!
            ctx.setBlendMode(.multiply)
            ctx.drawRadialGradient(edge, startCenter: CGPoint(x: px.width / 2, y: px.height / 2), startRadius: 0,
                                   endCenter: CGPoint(x: px.width / 2, y: px.height / 2), endRadius: hypot(px.width, px.height) / 2, options: [])
        }
    }

    /// A glossy print of a wooden table, with a dark border down one side.
    static func photo(_ size: CGSize) -> NSImage {
        let px = CGSize(width: size.width * 2, height: size.height * 2)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .transformed(by: CGAffineTransform(scaleX: 1.2, y: 26))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .applyingFilter("CITwirlDistortion", parameters: [kCIInputCenterKey: CIVector(x: px.width * 0.6, y: px.height * 0.4), kCIInputRadiusKey: px.width * 0.9, kCIInputAngleKey: 0.5])
            .applyingFilter("CIFalseColor", parameters: ["inputColor0": CIColor(red: 0.20, green: 0.11, blue: 0.05), "inputColor1": CIColor(red: 0.72, green: 0.48, blue: 0.27)])
        let wood = context.createCGImage(noise, from: CGRect(origin: .zero, size: px))!
        return image(px) { ctx, px in
            ctx.draw(wood, in: CGRect(origin: .zero, size: px))
            ctx.setFillColor(NSColor(white: 0.04, alpha: 0.95).cgColor)
            ctx.fill(CGRect(x: px.width - px.width * 0.07, y: 0, width: px.width * 0.07, height: px.height * 0.35))
            let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [NSColor(white: 0, alpha: 0.35).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: px.height), end: CGPoint(x: px.width * 0.6, y: 0), options: [])
        }
    }

    /// The notebook's card cover: smooth grey board with the print on it and the punched holes.
    static func card(_ size: CGSize, print: CGImage?, holes: [CGFloat]) -> NSImage {
        image(CGSize(width: size.width * Objects.texel, height: size.height * Objects.texel)) { ctx, px in
            let k = Objects.texel
            ctx.setFillColor(NSColor(srgbRed: 0.62, green: 0.62, blue: 0.615, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: px))
            grainOver(ctx, px, seed: 9, strength: 0.12)
            if let print { ctx.draw(print, in: CGRect(origin: .zero, size: px)) }
            punch(ctx, holes: holes, height: px.height, k: k)
        }
    }

    /// The first page: white with faint rules and the same holes.
    static func page(_ size: CGSize, holes: [CGFloat]) -> NSImage {
        image(CGSize(width: size.width * Objects.texel, height: size.height * Objects.texel)) { ctx, px in
            let k = Objects.texel
            ctx.setFillColor(NSColor(srgbRed: 0.96, green: 0.955, blue: 0.94, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: px))
            ctx.setStrokeColor(NSColor(srgbRed: 0.45, green: 0.55, blue: 0.75, alpha: 0.35).cgColor)
            ctx.setLineWidth(0.4 * k)
            for y in stride(from: 18 * k, to: px.height - 6 * k, by: 7 * k) { ctx.move(to: CGPoint(x: 12 * k, y: y)); ctx.addLine(to: CGPoint(x: px.width - 6 * k, y: y)) }
            ctx.strokePath()
            grainOver(ctx, px, seed: 11, strength: 0.4)
            punch(ctx, holes: holes, height: px.height, k: k)
        }
    }

    /// The edges of a block of pages: fine uneven lines.
    static let pageEdges: NSImage = image(CGSize(width: 64, height: 256)) { ctx, px in
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: px))
        var rng = Seeded(3)
        var y: CGFloat = 0
        while y < px.height {
            ctx.setFillColor(NSColor(white: 0.62 + rng.next() * 0.25, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: px.width, height: 0.8))
            y += 2.2 + rng.next() * 1.6
        }
    }

    private static func punch(_ ctx: CGContext, holes: [CGFloat], height: CGFloat, k: CGFloat) {
        for y in holes {
            let c = CGPoint(x: SpiralBook.holeInset * k, y: height - y * k)
            ctx.setBlendMode(.normal)
            ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 1.9 * k, y: c.y - 1.9 * k, width: 3.8 * k, height: 3.8 * k))
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.25).cgColor)
            ctx.setLineWidth(0.3 * k)
            ctx.strokeEllipse(in: CGRect(x: c.x - 1.9 * k, y: c.y - 2.0 * k, width: 3.8 * k, height: 3.8 * k))
        }
    }

    private static func grainOver(_ ctx: CGContext, _ px: CGSize, seed: Int, strength: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.setAlpha(strength)
        let tile = CGFloat(grain.width) / 2
        var y: CGFloat = -CGFloat(seed % 5) * 37
        while y < px.height {
            var x: CGFloat = -CGFloat(seed % 7) * 41
            while x < px.width {
                ctx.draw(grain, in: CGRect(x: x, y: y, width: tile, height: tile))
                x += tile
            }
            y += tile
        }
        ctx.restoreGState()
    }

    static func image(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> NSImage {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, CGSize(width: w, height: h))
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}

// MARK: - Printing

/// What's printed on each object, drawn with SwiftUI at texture resolution, on a clear background.
@MainActor
private enum Prints {
    static func make(_ folder: Folder) -> CGImage? {
        let renderer: ImageRenderer<AnyView>
        switch folder.kind {
        case .idea: renderer = ImageRenderer(content: AnyView(IdeaPrint(folder: folder)))
        case .book: renderer = ImageRenderer(content: AnyView(CoverPrint(folder: folder)))
        }
        renderer.scale = Objects.texel
        return renderer.cgImage
    }
}

/// The top sheet of an idea: a dot grid, a hand-lettered header, the name stamped in heavy ink with a sticker
/// behind it, a ring round "BY YOU", and a highlighted, typewritten form.
private struct IdeaPrint: View {
    let folder: Folder

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                var dots = Path()
                // Printed dot paper keeps a clean margin all round.
                for x in stride(from: 9.5, to: size.width - 8, by: 6) {
                    for y in stride(from: 9.5, to: size.height - 8, by: 6) {
                        dots.addEllipse(in: CGRect(x: x - 0.45, y: y - 0.45, width: 0.9, height: 0.9))
                    }
                }
                ctx.fill(dots, with: .color(Color(white: 0.12).opacity(0.75)))
            }
            VStack(spacing: 0) {
                VStack(spacing: 1.5) {
                    Text("SKULL SALAD · IDEA")
                        .font(.custom("ChalkboardSE-Regular", size: 5.6))
                        .tracking(1.6)
                    Capsule().frame(width: 74, height: 0.7)
                }
                .foregroundStyle(Color(white: 0.1))
                .padding(.top, 13)
                .padding(.leading, 12)
                Spacer(minLength: 0)
                Text(folder.name)
                    .font(.system(size: 21, weight: .black))
                    .tracking(-0.9)
                    .lineSpacing(-4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(Color(white: 0.09))
                    .mask(Image(nsImage: Ink.speckle).resizable(resizingMode: .tile))
                    .background(alignment: .topTrailing) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(Color(red: 0.80, green: 0.93, blue: 0.27))
                            .rotationEffect(.degrees(12))
                            .offset(x: 9, y: -11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                Text("BY YOU")
                    .font(.system(size: 5.6, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .overlay(Ellipse().stroke(lineWidth: 0.6))
                    .rotationEffect(.degrees(-4))
                    .foregroundStyle(Color(white: 0.1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    field("TYPE:", "IDEA", ink: Color(white: 0.1))
                        .background(alignment: .leading) {
                            Rectangle()
                                .fill(Color(red: 0.83, green: 0.95, blue: 0.36).opacity(0.9))
                                .frame(width: 58, height: 8.5)
                                .rotationEffect(.degrees(-0.8))
                                .offset(x: -2)
                        }
                    field("DATE:", folder.date.formatted(.dateTime.day().month(.abbreviated)).uppercased(), ink: Color(red: 0.2, green: 0.22, blue: 0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32)
                .padding(.bottom, 26)
            }
        }
        .frame(width: PaperStack.sheet.width, height: PaperStack.sheet.height)
    }

    private func field(_ label: String, _ value: String, ink: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 6.2, weight: .semibold)).foregroundStyle(Color(white: 0.1))
            Text(value).font(.custom("AmericanTypewriter", size: 6.4)).tracking(1.6).foregroundStyle(ink)
        }
    }
}

/// The notebook's cover, printed in white: the name set big, "(BOOK)", and the date.
private struct CoverPrint: View {
    let folder: Folder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(folder.name.uppercased())
                .font(.system(size: 19, weight: .medium))
                .tracking(-0.6)
                .lineSpacing(-3)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
            Spacer(minLength: 0)
            Text("(BOOK)")
                .font(.system(size: 7.5, weight: .medium))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(folder.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(Color(white: 0.985))
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 13)
        .frame(width: SpiralBook.cover.width, height: SpiralBook.cover.height)
    }
}

/// Ink that didn't quite take: a speckled mask for stamped type.
private enum Ink {
    static let speckle: NSImage = {
        let side = 96
        var generator = SystemRandomNumberGenerator()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 2,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<side {
            for x in 0..<side {
                let v = Double.random(in: 0...1, using: &generator)
                rep.setColor(NSColor(deviceWhite: 0, alpha: v < 0.1 ? v * 4 : 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        image.addRepresentation(rep)
        return image
    }()
}
