import AppKit

enum AnnotateTool: CaseIterable {
    case rect, ellipse, arrow, line, pen, text, mosaic

    var tip: String {
        switch self {
        case .rect: return "矩形  R".l
        case .ellipse: return "椭圆  O".l
        case .arrow: return "箭头  A".l
        case .line: return "直线  L".l
        case .pen: return "画笔  P".l
        case .text: return "文字  T".l
        case .mosaic: return "马赛克  M".l
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
    /// User-sized text box. Height grows as needed so wrapping never hides any text.
    var textBoxSize: CGSize?
    /// Fixes the hand-drawn jitter so redraws and the export look identical.
    var seed: UInt64 = .random(in: 1...UInt64.max)

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: HandFont.font(size: size.fontSize), .foregroundColor: color, .paragraphStyle: paragraph]
    }

    var textLayout: AnnotationTextLayout {
        AnnotationTextLayout(text: text.isEmpty ? " " : text, attributes: textAttributes, width: textWidth)
    }

    private var textWidth: CGFloat {
        max(32, textBoxSize?.width ?? ceil((text as NSString).size(withAttributes: textAttributes).width))
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
            return CGRect(origin: p, size: CGSize(width: textWidth, height: max(textBoxSize?.height ?? 0, textLayout.height)))
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

    /// Endpoints for lines, corners for boxes, corners and edge midpoints for text.
    var handles: [CGPoint] {
        switch tool {
        case .arrow, .line:
            guard points.count >= 2 else { return [] }
            return [points[0], points[points.count - 1]]
        case .rect, .ellipse, .mosaic:
            let r = rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        case .text:
            let r = bounds
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY)]
        case .pen:
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
        case .text:
            guard (0..<8).contains(i) else { return }
            let r = bounds
            var left = r.minX, right = r.maxX, top = r.minY, bottom = r.maxY
            if [0, 2, 4].contains(i) { left = min(p.x, right - 32) }
            if [1, 3, 5].contains(i) { right = max(p.x, left + 32) }
            let minHeight = AnnotationTextLayout(text: text.isEmpty ? " " : text, attributes: textAttributes, width: right - left).height
            if [0, 1, 6].contains(i) { top = min(p.y, bottom - minHeight) }
            if [2, 3, 7].contains(i) { bottom = max(p.y, top + minHeight) }
            points = [CGPoint(x: left, y: top)]
            textBoxSize = CGSize(width: right - left, height: max(minHeight, bottom - top))
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
        NSColor(srgbRed: 0xE9 / 255, green: 0x63 / 255, blue: 0x1A / 255, alpha: 1),   // orange #E9631A
        NSColor(srgbRed: 0xC5 / 255, green: 0x6F / 255, blue: 0x8C / 255, alpha: 1),   // pink #C56F8C
        NSColor(srgbRed: 0xA9 / 255, green: 0xC2 / 255, blue: 0xE0 / 255, alpha: 1),   // sky #A9C2E0
        NSColor(srgbRed: 0x59 / 255, green: 0x38 / 255, blue: 0x2C / 255, alpha: 1),   // brown #59382C
        NSColor(srgbRed: 0x1E / 255, green: 0x15 / 255, blue: 0x1C / 255, alpha: 1),   // ink #1E151C
        NSColor(srgbRed: 0xEB / 255, green: 0xEB / 255, blue: 0xDF / 255, alpha: 1),   // chalk #EBEBDF
    ]
    static let accent = Theme.paperBlueDeep
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }
}
