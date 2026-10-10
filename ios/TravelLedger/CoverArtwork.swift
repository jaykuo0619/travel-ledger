import LedgerCore
import SwiftUI

/*
 * Illustrated trip covers (ui/CoverArtwork.kt), drawn on the phone from the trip name (see CoverArt).
 * Scenes are authored in an 800×450 design space and scaled to fill, cropping the top and bottom on wide cards.
 */

private let W: CGFloat = 800
private let H: CGFloat = 450

/// SVG path data → SwiftUI Path.
func svgPath(_ d: String) -> Path {
    var path = Path()
    for c in SVGPath.parse(d) {
        switch c {
        case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
        case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
        case let .quad(c, p): path.addQuadCurve(to: CGPoint(x: p.x, y: p.y), control: CGPoint(x: c.x, y: c.y))
        case let .cubic(c1, c2, p):
            path.addCurve(to: CGPoint(x: p.x, y: p.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
        case .close: path.closeSubpath()
        }
    }
    return path
}

private func p(_ d: String) -> Path { svgPath(d) }
private func c(_ hex: UInt32, _ alpha: Double = 1) -> Color { Color(hex: hex, alpha: alpha) }
private let white = Color.white

private enum Shapes {
    static let maple = p("M0,-14 L3,-6 L9,-9 L7,-2 L14,0 L7,3 L9,9 L2,6 L1,14 L0,8 L-1,14 L-2,6 L-9,9 L-7,3 L-14,0 L-7,-2 L-9,-9 L-3,-6 Z")
    static let petal = p("M0,-9 C6,-9 8,-2 0,9 C-8,-2 -6,-9 0,-9 Z")
    static let plane = p("M21 16v-2l-8-5V3.5c0-.83-.67-1.5-1.5-1.5S10 2.67 10 3.5V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5l8 2.5z")

    // Landmarks: base at (0,0), drawing upward.
    static let seoulTower = p("M-2.5,-8 V-100 H2.5 V-8 Z M-8.5,-90 h17 v12 h-17 z M-5.5,-100 h11 v6 h-11 z M-1,-124 h2 v26 h-2 z M-13,0 L13,0 L7,-12 L-7,-12 Z")
    static let tokyoTower = p("M-30,0 L-8,-120 L-4,-200 L0,-240 L4,-200 L8,-120 L30,0 Z")
    static let tokyoBands = p("M-16,-75 L16,-75 L14,-65 L-14,-65 Z M-10,-122 L10,-122 L10,-114 L-10,-114 Z M-6,-170 L6,-170 L6,-162 L-6,-162 Z")
    static let fuji = p("M-200,0 L-20,-160 Q0,-178 20,-160 L200,0 Z")
    static let fujiSnow = p("M-58,-126 L-20,-160 Q0,-178 20,-160 L58,-126 L40,-116 L23,-127 L6,-112 L-11,-127 L-28,-114 Z")
    static let osakaCastle = p(
        "M-46,0 L46,0 L38,-34 L-38,-34 Z" +
            " M-30,-34 H30 V-58 H-30 Z M-44,-58 Q0,-74 44,-58 L34,-66 H-34 Z" +
            " M-22,-66 H22 V-86 H-22 Z M-34,-86 Q0,-100 34,-86 L24,-94 H-24 Z" +
            " M-14,-94 H14 V-110 H-14 Z M-24,-110 Q0,-124 24,-110 L14,-118 H-14 Z M-2,-118 H2 V-130 H-2 Z"
    )
    static let pagoda = p(
        "M-6,0 H6 V-150 H-6 Z" +
            " M-40,-20 Q0,-30 40,-20 L30,-30 H-30 Z M-34,-50 Q0,-60 34,-50 L25,-60 H-25 Z M-28,-80 Q0,-90 28,-80 L20,-90 H-20 Z" +
            " M-22,-110 Q0,-120 22,-110 L15,-120 H-15 Z M-16,-140 Q0,-150 16,-140 L10,-150 H-10 Z" +
            " M-24,0 H24 V-20 H-24 Z M-20,-30 H20 V-50 H-20 Z M-16,-60 H16 V-80 H-16 Z M-12,-90 H12 V-110 H-12 Z M-8,-120 H8 V-140 H-8 Z M-1.5,-150 H1.5 V-176 H-1.5 Z"
    )
    static let torii = p("M-36,0 H-28 V-70 H-36 Z M28,0 H36 V-70 H28 Z M-46,-70 H46 V-62 H-46 Z M-56,-84 Q0,-78 56,-84 L52,-94 Q0,-88 -52,-94 Z M-4,-62 H4 V-80 H-4 Z")
    static let taipei101 = p(
        "M-14,0 H14 V-30 H-14 Z" +
            (0 ..< 8).map { i -> String in let b = -30 - Double(i) * 22; return " M-12,\(b) L-16,\(b - 22) H16 L12,\(b) Z" }.joined() +
            " M-8,-206 H8 V-220 H-8 Z M-1.5,-220 H1.5 V-256 H-1.5 Z"
    )
    static let wat = p("M-40,0 H40 V-14 H-40 Z M-30,-14 H30 V-28 H-30 Z M-22,-28 Q-22,-70 0,-96 Q22,-70 22,-28 Z M-1.5,-96 H1.5 V-140 H-1.5 Z M-60,0 H-48 V-40 L-54,-60 L-60,-40 Z M48,0 H60 V-40 L54,-60 L48,-40 Z")
    static let marinaBay = p("M-60,0 H-38 V-150 H-60 Z M-11,0 H11 V-150 H-11 Z M38,0 H60 V-150 H38 Z M-76,-150 H84 Q88,-160 76,-162 H-70 Q-80,-160 -76,-150 Z")
    static let eiffel = p("M-46,0 Q-30,-40 -14,-100 L-6,-170 L-2,-236 H2 L6,-170 L14,-100 Q30,-40 46,0 H30 Q0,-56 -30,0 Z M-24,-70 H24 V-62 H-24 Z M-12,-138 H12 V-132 H-12 Z")
    static let bigBen = p("M-16,0 H16 V-150 H-16 Z M-20,-150 H20 V-160 H-20 Z M-14,-160 L0,-212 L14,-160 Z M-1,-212 H1 V-226 H-1 Z")
    static let skyline = p("M-90,0 V-80 H-60 V-120 H-36 V-60 H-10 V-170 L0,-186 L10,-170 V-90 H34 V-140 H60 V-70 H90 V0 Z")

    // Shared hill outlines (design space).
    static let farHills = p("M0,260 C80,215 140,225 210,245 C290,195 360,200 430,235 C510,190 600,200 680,240 C730,220 770,225 800,235 V450 H0 Z")
    static let midHills = p("M0,300 C70,265 150,270 230,295 C320,255 400,262 470,290 C560,250 650,262 800,285 V450 H0 Z")
    static let bump = p("M330,372 C400,340 450,300 510,290 C560,282 600,288 630,300 C670,315 710,335 760,352 C780,358 790,362 800,364 V450 H330 Z")
    static let nearHills = p("M0,350 C90,320 190,325 290,350 C380,372 470,360 560,370 C650,380 730,365 800,372 V450 H0 Z")
    static let ground = p("M0,405 C150,390 300,395 450,402 C600,410 700,398 800,402 V450 H0 Z")
}

/// Drawing helpers in the 800×450 design space.
private struct Scene {
    var g: GraphicsContext

    /// Draws [path] (authored around its own origin) at x,y with optional scale / rotation in degrees.
    func shape(_ path: Path, _ color: Color, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat = 1, _ rot: Double = 0) {
        var t = g
        t.translateBy(x: x, y: y)
        t.rotate(by: .degrees(rot))
        t.scaleBy(x: s, y: s)
        t.fill(path, with: .color(color))
    }

    func vgrad(_ stops: [(Double, Color)], from: CGFloat = 0, to: CGFloat = H) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.1, location: $0.0) }),
                        startPoint: CGPoint(x: 0, y: from), endPoint: CGPoint(x: 0, y: to))
    }

    func sky(_ stops: [(Double, Color)]) { g.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: vgrad(stops)) }
    func hill(_ path: Path, _ color: Color) { g.fill(path, with: .color(color)) }

    func circle(_ color: Color, _ r: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    func sun(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ core: Color, _ glow: Color) {
        let gr = r * 3
        g.fill(Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: 2 * gr, height: 2 * gr)),
               with: .radialGradient(Gradient(colors: [glow.opacity(0.85), glow.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: gr))
        circle(core, r, x, y)
    }

    func oval(_ color: Color, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
    }

    func rect(_ color: Color, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
    }

    func line(_ color: Color, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ width: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        g.stroke(path, with: .color(color), lineWidth: width)
    }

    func stroke(_ path: Path, _ color: Color, _ style: StrokeStyle) { g.stroke(path, with: .color(color), style: style) }

    func cloud(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ a: Double = 0.9) {
        let col = white.opacity(a)
        oval(col, x - 60 * s, y - 18 * s, 120 * s, 36 * s)
        oval(col, x - 5 * s, y - 32 * s, 76 * s, 40 * s)
        oval(col, x - 58 * s, y - 24 * s, 56 * s, 28 * s)
    }

    func tree(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ trunk: Color, _ blobs: [Color]) {
        rect(trunk, x - 4 * s, y - 70 * s, 8 * s, 70 * s)
        let offs: [(CGFloat, CGFloat, CGFloat)] = [(0, -82, 40), (-28, -65, 28), (28, -64, 30), (0, -108, 26)]
        for (i, o) in offs.enumerated() { circle(blobs[i % blobs.count], o.2 * s, x + o.0 * s, y + o.1 * s) }
    }

    func landmarks(_ list: [Landmark], _ x: CGFloat, _ y: CGFloat, _ color: Color, _ accent: Color, _ s: CGFloat = 1) {
        for lm in list {
            switch lm {
            case .fuji: break // drawn as part of the backdrop
            case .seoulTower: shape(Shapes.seoulTower, color, x, y, s * 1.1)
            case .tokyoTower: shape(Shapes.tokyoTower, accent, x, y, s); shape(Shapes.tokyoBands, white, x, y, s)
            case .osakaCastle: shape(Shapes.osakaCastle, color, x, y, s * 1.2)
            case .pagoda: shape(Shapes.pagoda, color, x, y, s * 1.2)
            case .torii: shape(Shapes.torii, accent, x, y, s * 1.2)
            case .taipei101: shape(Shapes.taipei101, color, x, y, s)
            case .bangkokTemple: shape(Shapes.wat, color, x, y, s * 1.2)
            case .marinaBay: shape(Shapes.marinaBay, color, x, y, s)
            case .eiffel: shape(Shapes.eiffel, color, x, y, s)
            case .bigBen: shape(Shapes.bigBen, color, x, y, s * 1.1)
            case .citySkyline: shape(Shapes.skyline, color, x, y, s * 1.2)
            }
        }
    }

    func fujiBackdrop(_ spec: CoverSpec, _ body: Color, _ x: CGFloat = 320, _ y: CGFloat = 330) {
        guard spec.landmarks.contains(.fuji) else { return }
        shape(Shapes.fuji, body, x, y)
        shape(Shapes.fujiSnow, white.opacity(0.92), x, y)
    }

    // MARK: Scenes

    func autumn(_ spec: CoverSpec) {
        sky([(0, c(0xFFE3B3)), (0.55, c(0xFFB070)), (1, c(0xF0784A))])
        sun(560, 170, 42, c(0xFFF3D1), c(0xFFE29A))
        hill(Shapes.farHills, c(0xF29A6B, 0.75))
        fujiBackdrop(spec, c(0xD0603F))
        hill(Shapes.midHills, c(0xE36E45))
        hill(Shapes.bump, c(0xB9472F))
        landmarks(spec.landmarks, 580, 296, c(0x7A2A1F), c(0x7A2A1F))
        hill(Shapes.nearHills, c(0x8E2F22))
        tree(100, 400, 1, c(0x4A1A14), [c(0xD9452B), c(0xC23A24), c(0xE8603A), c(0xF07A3C)])
        tree(730, 405, 0.8, c(0x4A1A14), [c(0xF0A13C), c(0xE8853A), c(0xD9682B), c(0xF0A13C)])
        hill(Shapes.ground, c(0x5E1E17))
        let leaves: [(CGFloat, CGFloat, Double)] = [(250, 120, 20), (330, 205, -30), (180, 210, 55), (690, 110, -15), (410, 150, 70), (470, 300, 10), (760, 250, -50)]
        let colors: [UInt32] = [0xE2452B, 0xF59E2C, 0xC8341F, 0xF07A3C, 0xFFC14D, 0xE2452B, 0xFFC14D]
        let sizes: [CGFloat] = [1.3, 0.9, 1, 1.1, 0.7, 0.8, 0.75]
        for (i, t) in leaves.enumerated() { shape(Shapes.maple, c(colors[i]), t.0, t.1, sizes[i], t.2) }
    }

    func sakura(_ spec: CoverSpec) {
        sky([(0, c(0xFFF0F4)), (0.6, c(0xFFD3E0)), (1, c(0xF7B6CB))])
        sun(620, 140, 36, c(0xFFFBF2), c(0xFFE6EE))
        hill(Shapes.farHills, c(0xF3C3D3))
        fujiBackdrop(spec, c(0xB9A3D6))
        hill(Shapes.midHills, c(0xBFD9A8))
        hill(Shapes.bump, c(0x9CC48A))
        landmarks(spec.landmarks, 580, 296, c(0x6D4C7D), c(0xE0533D))
        hill(Shapes.nearHills, c(0x7FB06F))
        tree(110, 400, 1.05, c(0x6B4A3A), [c(0xFFB7CC), c(0xFF9EBB), c(0xFFC9D7), c(0xFFDCE6)])
        tree(720, 405, 0.85, c(0x6B4A3A), [c(0xFF9EBB), c(0xFFC9D7), c(0xFFB7CC), c(0xFFDCE6)])
        hill(Shapes.ground, c(0x5F9658))
        let petals: [(CGFloat, CGFloat, Double)] = [(240, 120, 20), (330, 200, -40), (190, 230, 60), (680, 110, -10), (420, 160, 80), (470, 300, 15), (770, 250, -55), (520, 90, 30)]
        for (i, t) in petals.enumerated() { shape(Shapes.petal, i % 2 == 0 ? c(0xFF9EBB) : c(0xFFFFFF), t.0, t.1, 1.1, t.2) }
    }

    func snow(_ spec: CoverSpec) {
        sky([(0, c(0xB9DDF7)), (0.7, c(0xE4F3FF)), (1, c(0xF4FAFF))])
        hill(p("M0,280 L120,170 L200,230 L300,140 L420,250 L520,160 L640,250 L720,190 L800,240 V450 H0 Z"), c(0x9FB8D6))
        hill(p("M90,197 L120,170 L150,198 L135,192 L120,204 L105,192 Z M268,170 L300,140 L333,170 L316,164 L300,176 L284,164 Z M488,190 L520,160 L552,190 L536,184 L520,196 L504,184 Z"), white)
        fujiBackdrop(spec, c(0x8AA4C8))
        hill(Shapes.midHills, c(0xDDEBF7))
        hill(Shapes.bump, c(0xEFF6FC))
        landmarks(spec.landmarks, 580, 296, c(0x3E5675), c(0xD84A3A))
        hill(Shapes.nearHills, c(0xFFFFFF))
        let pine = p("M0,0 L-18,0 L-6,-18 L-14,-18 L-4,-34 L-10,-34 L0,-52 L10,-34 L4,-34 L14,-18 L6,-18 L18,0 Z")
        for (x, y) in [(80, 380), (120, 390), (690, 392), (740, 384)] as [(CGFloat, CGFloat)] { shape(pine, c(0x2F6B6B), x, y, 1.6) }
        hill(Shapes.ground, c(0xF5FAFF))
        let flakes: [(CGFloat, CGFloat)] = [(60, 60), (150, 120), (240, 40), (350, 100), (450, 50), (520, 130), (610, 70), (700, 140), (770, 50), (280, 200), (660, 220)]
        for (x, y) in flakes { circle(white.opacity(0.9), 4, x, y) }
    }

    func beach() {
        sky([(0, c(0x3FA9F5)), (1, c(0xBDEBFF))])
        sun(640, 90, 38, c(0xFFF9DD), c(0xFFF2B0))
        cloud(170, 85, 1); cloud(430, 55, 0.7)
        g.fill(Path(CGRect(x: 0, y: 215, width: W, height: H - 215)),
               with: vgrad([(0, c(0x1E88C8)), (0.5, c(0x22B8C8)), (1, c(0x6FE0D2))], from: 215, to: H))
        hill(p("M330,222 C360,190 420,186 460,210 C470,216 480,220 490,222 Z"), c(0x2E8B57))
        hill(p("M560,222 C580,205 615,203 640,222 Z"), c(0x3AA36A))
        let wave = StrokeStyle(lineWidth: 2.4, lineCap: .round)
        for (x, y) in [(60, 260), (520, 280), (250, 300), (640, 330)] as [(Double, Double)] {
            stroke(p("M\(x),\(y) q15,-6 30,0 t30,0"), white.opacity(0.55), wave)
        }
        stroke(p("M300,120 q8,-8 16,0 q8,-8 16,0 M345,140 q6,-6 12,0 q6,-6 12,0"), c(0x355C7D), wave)
        g.fill(p("M0,330 C160,318 300,345 430,370 C560,395 700,385 800,372 V450 H0 Z"),
               with: vgrad([(0, c(0xFFF2D2)), (1, c(0xF2D7A2))], from: 320, to: H))
        stroke(p("M0,330 C160,318 300,345 430,370 C560,395 700,385 800,372"), white.opacity(0.8), StrokeStyle(lineWidth: 5))
        // palm
        stroke(p("M120,400 C130,340 150,270 190,210"), c(0x8A5A2B), StrokeStyle(lineWidth: 12, lineCap: .round))
        hill(p("M190,210 C230,190 270,200 295,230 C260,215 230,220 190,210 Z M190,210 C220,230 240,260 245,295 C225,265 210,240 190,210 Z" +
            " M190,210 C160,185 120,185 90,205 C125,200 155,203 190,210 Z M190,210 C165,230 145,260 138,290 C158,260 172,235 190,210 Z" +
            " M190,210 C200,170 235,150 265,155 C232,165 210,185 190,210 Z"), c(0x1F9D55))
        circle(c(0x6B4423), 7, 186, 218); circle(c(0x6B4423), 6, 196, 222)
        // umbrella
        line(white, 600, 390, 592, 320, 4)
        hill(p("M540,328 Q592,270 644,312 Z"), c(0xFF6B6B))
        hill(p("M540,328 Q560,300 592,292 L592,320 Z"), c(0xFFD166))
    }

    func food(_ spec: CoverSpec) {
        sky([(0, c(0x2A2F72)), (0.5, c(0x7A5AB8)), (0.82, c(0xF29BB2)), (1, c(0xFFC9A8))])
        for (x, y) in [(90, 60), (210, 35), (420, 50), (610, 30), (740, 75), (330, 95)] as [(CGFloat, CGFloat)] { circle(white.opacity(0.75), 1.6, x, y) }
        circle(c(0xFFF4D6), 22, 650, 120)
        fujiBackdrop(spec, c(0x7E66B6))
        landmarks(spec.landmarks, 590, 362, c(0x3A2F6B), c(0xE8432B))
        hill(p("M0,315 H70 V290 H110 V330 H160 V300 H200 V340 H270 V310 H315 V335 H380 V295 H432 V325 H500 V345 H555 V450 H0 Z" +
            " M630,300 H680 V330 H738 V305 H800 V450 H630 Z"), c(0x2B2350))
        let windows: [(CGFloat, CGFloat)] = [(75, 305), (90, 320), (172, 318), (290, 330), (395, 312), (410, 340), (645, 318), (750, 325), (215, 360), (455, 350), (700, 350)]
        for (x, y) in windows { rect(c(0xFFD27A, 0.85), x, y, 6, 6) }
        rect(c(0x1C1738), 0, 420, W, 30)
        // lanterns, kept low enough to survive the card crop
        stroke(p("M0,70 Q200,110 400,82 Q600,58 800,92"), c(0x1C1738, 0.6), StrokeStyle(lineWidth: 2))
        for (x, y, s) in [(120, 96, 1), (270, 96, 0.85), (470, 76, 0.85), (720, 86, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
            let body = Path(roundedRect: CGRect(x: x - 16 * s, y: y, width: 32 * s, height: 42 * s), cornerRadius: 15 * s)
            g.fill(body, with: .linearGradient(Gradient(colors: [c(0xC8261E), c(0xF0503A), c(0xC8261E)]),
                                               startPoint: CGPoint(x: x - 16 * s, y: 0), endPoint: CGPoint(x: x + 16 * s, y: 0)))
            rect(c(0x2B1E1E), x - 12 * s, y - 2 * s, 24 * s, 5 * s)
            rect(c(0x2B1E1E), x - 12 * s, y + 40 * s, 24 * s, 5 * s)
        }
        // ramen bowl
        hill(p("M116,366 H184 Q182,398 150,402 Q118,398 116,366 Z"), c(0xF7F1E8))
        line(c(0xC8261E), 116, 366, 184, 366, 4)
        stroke(p("M140,358 q4,-8 0,-14 M152,356 q4,-8 0,-14 M164,358 q4,-8 0,-14"), white.opacity(0.85), StrokeStyle(lineWidth: 2.4, lineCap: .round))
        stroke(p("M168,348 L190,328 M174,350 L196,332"), c(0xE5C38A), StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    func city(_ spec: CoverSpec) {
        sky([(0, c(0x6BB7F2)), (0.7, c(0xBFE4FF)), (1, c(0xE6F5FF))])
        sun(150, 110, 34, c(0xFFFBE6), c(0xFFF1B8))
        cloud(560, 90, 0.9); cloud(300, 60, 0.6, 0.8)
        fujiBackdrop(spec, c(0x8FA9D8))
        landmarks(spec.landmarks, 590, 372, c(0x34558F), c(0xE8432B))
        hill(p("M0,330 H60 V300 H110 V340 H170 V310 H220 V350 H300 V320 H350 V345 H420 V305 H470 V335 H540 V355 H560 V450 H0 Z M640,330 H700 V310 H760 V340 H800 V450 H640 Z"), c(0x5F86C4))
        rect(c(0x4A6FAE), 0, 410, W, 40)
        shape(Shapes.plane, white, 660, 170, 2.2, 45)
    }

    func generic() {
        sky([(0, c(0x8FC8F5)), (0.6, c(0xCDE8FF)), (1, c(0xFFE9D6))])
        sun(610, 130, 36, c(0xFFFBE8), c(0xFFE9B8))
        cloud(200, 90, 1); cloud(480, 70, 0.7, 0.85)
        hill(Shapes.farHills, c(0xB7D7C8))
        hill(Shapes.midHills, c(0x8FC1A4))
        hill(Shapes.nearHills, c(0x6BA587))
        hill(Shapes.ground, c(0x4F8B6E))
        stroke(p("M120,250 C220,180 330,160 450,170"), white.opacity(0.85), StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 10]))
        shape(Shapes.plane, white, 470, 140, 2.6, 70)
    }
}

/// The illustrated cover for [spec], scaled to fill and centre-cropped.
struct CoverArtwork: View {
    let spec: CoverSpec

    init(spec: CoverSpec) { self.spec = spec }

    init(name: String, startDate: Int64?, theme: String? = nil) {
        spec = CoverArt.pick(name: name, startDay: startDate, theme: theme)
    }

    var body: some View {
        Canvas { context, size in
            let s = max(size.width / W, size.height / H)
            var g = context
            g.translateBy(x: (size.width - W * s) / 2, y: (size.height - H * s) / 2)
            g.scaleBy(x: s, y: s)
            let scene = Scene(g: g)
            switch spec.theme {
            case .autumn: scene.autumn(spec)
            case .sakura: scene.sakura(spec)
            case .snow: scene.snow(spec)
            case .beach: scene.beach()
            case .food: scene.food(spec)
            case .city: scene.city(spec)
            case .generic: scene.generic()
            }
        }
        .clipped()
    }
}
