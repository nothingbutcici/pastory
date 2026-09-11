import AppKit

enum AnnotateTool: CaseIterable {
    case rect, ellipse, arrow, pen, text, mosaic, badge

    var symbol: String {
        switch self {
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .mosaic: return "mosaic"
        case .badge: return "1.circle"
        }
    }
    var tip: String {
        switch self {
        case .rect: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .badge: return "序号"
        }
    }
}

enum StrokeSize: Int, CaseIterable {
    case thin = 2, medium = 4, thick = 7
    var fontSize: CGFloat {
        switch self {
        case .thin: return 14
        case .medium: return 18
        case .thick: return 26
        }
    }
    var badgeRadius: CGFloat {
        switch self {
        case .thin: return 11
        case .medium: return 14
        case .thick: return 18
        }
    }
}

/// One drawn thing, in canvas points (origin top-left).
struct Annotation {
    var tool: AnnotateTool
    var color: NSColor
    var size: StrokeSize
    /// rect / ellipse / arrow / mosaic: [start, end]. pen: the whole path. text / badge: [anchor].
    var points: [CGPoint]
    var text: String = ""
    var number: Int = 0

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

enum AnnotatePalette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.96, green: 0.26, blue: 0.21, alpha: 1),   // red
        NSColor(srgbRed: 1.00, green: 0.72, blue: 0.00, alpha: 1),   // yellow
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),   // green
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1),   // blue
        NSColor(srgbRed: 0.56, green: 0.42, blue: 1.00, alpha: 1),   // purple
        .white,
        .black,
    ]
}
