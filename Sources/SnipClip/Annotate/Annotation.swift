import AppKit

enum AnnotateTool: CaseIterable {
    case rect, ellipse, arrow, line, pen, text, mosaic

    var tip: String {
        switch self {
        case .rect: return "矩形  R"
        case .ellipse: return "椭圆  O"
        case .arrow: return "箭头  A"
        case .line: return "直线  L"
        case .pen: return "画笔  P"
        case .text: return "文字  T"
        case .mosaic: return "马赛克  M"
        }
    }
    /// Single-key shortcut (Excalidraw-style).
    var key: Character {
        switch self {
        case .rect: return "r"
        case .ellipse: return "o"
        case .arrow: return "a"
        case .line: return "l"
        case .pen: return "p"
        case .text: return "t"
        case .mosaic: return "m"
        }
    }
}

/// One size control for everything: stroke width for shapes, font size for text.
enum StrokeSize: Int, CaseIterable {
    case s = 1, m = 2, l = 3
    var label: String { ["S", "M", "L"][rawValue - 1] }
    var lineWidth: CGFloat { [2.6, 4.2, 6.5][rawValue - 1] }
    var fontSize: CGFloat { [18, 24, 34][rawValue - 1] }
    /// Mosaic cell size in canvas points.
    var mosaicBlock: CGFloat { [8, 12, 18][rawValue - 1] }
    /// Diameter of the dot shown in the size picker.
    var dotDiameter: CGFloat { [5, 8, 11][rawValue - 1] }
}

enum HandFont {
    /// 翩翩体 covers Latin too, close to Excalidraw's Xiaolai/Virgil feel. Falls back to the system font.
    static func font(size: CGFloat) -> NSFont {
        NSFont(name: "HanziPenSC-W5", size: size) ?? NSFont(name: "HannotateSC-W5", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
}

/// One drawn thing, in canvas points (origin top-left).
struct Annotation: Identifiable {
    let id = UUID()
    var tool: AnnotateTool
    var color: NSColor
    var size: StrokeSize
    /// rect / ellipse / arrow / line / mosaic: [start, end]. pen: the whole path. text: [anchor].
    var points: [CGPoint]
    var text: String = ""
    /// Fixes the hand-drawn jitter so redraws and the export look identical.
    var seed: UInt64 = .random(in: 1...UInt64.max)

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: HandFont.font(size: size.fontSize), .foregroundColor: color]
    }

    /// Bounding box in canvas points, used for selection and hit testing.
    var bounds: CGRect {
        switch tool {
        case .pen:
            guard let f = points.first else { return .zero }
            var r = CGRect(origin: f, size: .zero)
            for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
            return r
        case .text:
            guard let p = points.first else { return .zero }
            let s = (text as NSString).size(withAttributes: textAttributes)
            return CGRect(origin: p, size: s)
        default:
            return rect
        }
    }

    mutating func translate(_ d: CGPoint) {
        points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
    }

    /// Hit test near the stroke (so you can still start a new shape inside an old rectangle);
    /// mosaic and text hit anywhere inside.
    func hit(_ p: CGPoint) -> Bool {
        let slop: CGFloat = 8
        switch tool {
        case .arrow, .line:
            guard points.count >= 2 else { return false }
            return Self.distance(p, toSegment: points[0], points[points.count - 1]) <= slop
        case .pen:
            for i in 1..<max(1, points.count) where Self.distance(p, toSegment: points[i - 1], points[i]) <= slop { return true }
            return false
        case .rect:
            let r = rect
            return r.insetBy(dx: -slop, dy: -slop).contains(p) && !r.insetBy(dx: slop, dy: slop).contains(p)
        case .ellipse:
            let r = rect
            let a = max(1, r.width / 2), b = max(1, r.height / 2)
            let dx = (p.x - r.midX) / a, dy = (p.y - r.midY) / b
            let d = sqrt(dx * dx + dy * dy)
            return abs(d - 1) * min(a, b) <= slop
        case .mosaic, .text:
            return bounds.insetBy(dx: -slop, dy: -slop).contains(p)
        }
    }

    /// Draggable control points: both ends for lines, four corners for boxes, none for pen/text.
    var handles: [CGPoint] {
        switch tool {
        case .arrow, .line:
            guard points.count >= 2 else { return [] }
            return [points[0], points[points.count - 1]]
        case .rect, .ellipse, .mosaic:
            let r = rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        case .pen, .text:
            return []
        }
    }

    /// Move handle `i` to `p`; the opposite side stays put.
    mutating func setHandle(_ i: Int, to p: CGPoint) {
        switch tool {
        case .arrow, .line:
            if i == 0 { points[0] = p } else { points[points.count - 1] = p }
        case .rect, .ellipse, .mosaic:
            let h = handles
            guard h.count == 4 else { return }
            let opposite = h[3 - i]
            points = [opposite, p]
        default:
            break
        }
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t: CGFloat = 0
        if len2 > 0 { t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) }
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

enum AnnotatePalette {
    /// Low-saturation set; purple first and default.
    static let colors: [NSColor] = [
        Theme.purple,                                                 // purple (default)
        NSColor(srgbRed: 0.80, green: 0.40, blue: 0.38, alpha: 1),   // dusty red
        NSColor(srgbRed: 0.87, green: 0.62, blue: 0.36, alpha: 1),   // dusty orange
        NSColor(srgbRed: 0.45, green: 0.68, blue: 0.47, alpha: 1),   // dusty green
        NSColor(srgbRed: 0.38, green: 0.55, blue: 0.82, alpha: 1),   // dusty blue
        NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1),   // ink
        .white,
    ]
    static let accent = Theme.purple
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }
}
