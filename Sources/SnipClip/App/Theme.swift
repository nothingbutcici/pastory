import AppKit

/// One place for the look: dark islands, lime accent, white type.
enum Theme {
    static let bg = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)          // #1C1C1E
    static let bgElevated = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)  // #2C2C2E
    static let lime = NSColor(srgbRed: 0.78, green: 0.96, blue: 0.36, alpha: 1)        // #C8F55B
    static let onLime = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.06, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let muted = NSColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1)       // #9A9AA0
    static let divider = NSColor(calibratedWhite: 1, alpha: 0.22)
    static let red = NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)         // #E5484D
    static let cornerRadius: CGFloat = 14

    // Shelf (near-black, lavender accent)
    static let shelfBG = NSColor(srgbRed: 0.090, green: 0.090, blue: 0.094, alpha: 1)   // #171718
    static let shelfSide = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.114, alpha: 1) // #1C1C1D
    static let shelfCard = NSColor(srgbRed: 0.137, green: 0.137, blue: 0.141, alpha: 1) // #232324
    static let shelfBorder = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.21, alpha: 1)  // #333336
    static let shelfInk = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let shelfMuted = NSColor(srgbRed: 0.62, green: 0.62, blue: 0.64, alpha: 1)   // #9E9EA3
    static let shelfGrid = NSColor(calibratedWhite: 1, alpha: 0.045)
    static let cream = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.89, alpha: 1)        // #F2EDE3 content paper
    static let creamInk = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1)
    static let purple = NSColor(srgbRed: 0.71, green: 0.64, blue: 0.95, alpha: 1)       // #B5A3F2
    static let yellow = NSColor(srgbRed: 0.97, green: 0.84, blue: 0.45, alpha: 1)       // #F7D673 mascot yellow
    static let paleYellow = NSColor(srgbRed: 0.99, green: 0.95, blue: 0.80, alpha: 1)   // #FCF2CC 「已复制」
    static let paleGreen = NSColor(srgbRed: 0.72, green: 0.89, blue: 0.70, alpha: 1)    // #B8E3B3 「已复制」
    static let onPurple = NSColor(srgbRed: 0.12, green: 0.09, blue: 0.20, alpha: 1)
    // Kind tags: low-saturation outline colours; the label itself stays gray
    static let tagMP4 = NSColor(srgbRed: 0.78, green: 0.64, blue: 0.54, alpha: 1)       // dusty peach
    static let tagGIF = NSColor(srgbRed: 0.78, green: 0.60, blue: 0.68, alpha: 1)       // dusty rose
    static let tagImage = NSColor(srgbRed: 0.76, green: 0.72, blue: 0.56, alpha: 1)     // dusty sand
    static let tagText = NSColor(srgbRed: 0.58, green: 0.66, blue: 0.76, alpha: 1)      // dusty blue
    static let tagLink = NSColor(srgbRed: 0.68, green: 0.63, blue: 0.80, alpha: 1)      // dusty lavender
    static let tagFiles = NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)     // gray

    static func shadow() -> NSShadow {
        let s = NSShadow()
        s.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        s.shadowBlurRadius = 14
        s.shadowOffset = CGSize(width: 0, height: -3)
        return s
    }

    /// Product logo (Resources/Logo.png). Falls back to the source tree so self-tests find it too.
    static let logo: NSImage? = resource("Logo.png")
    /// The mascot on the shelf sidebar.
    static let mascot: NSImage? = resource("Mascot.png")
    /// Menu bar glyph: the logo's clip strokes as a template image.
    static let menuIcon: NSImage? = {
        guard let img = resource("MenuIcon@2x.png") ?? resource("MenuIcon.png") else { return nil }
        img.size = CGSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    private static func resource(_ name: String) -> NSImage? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), let img = NSImage(contentsOf: url) { return img }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/\(name)")
        return NSImage(contentsOf: dev)
    }

    static let gridStep: CGFloat = 28
    static let gridLine = NSColor(calibratedWhite: 1, alpha: 0.05)

    /// Dark rounded island: shadow + border on the layer, background + grid painted by `drawIsland`.
    static func island(_ v: NSView, radius: CGFloat = cornerRadius) {
        v.wantsLayer = true
        v.layer?.cornerRadius = radius
        v.layer?.borderWidth = 0.5
        v.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        v.shadow = shadow()
    }

    /// Paint the island ground: fill + faint graph-paper grid, clipped to `path`.
    static func drawIsland(_ path: NSBezierPath, fill: NSColor = bg) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        fill.setFill()
        path.bounds.fill()
        drawGrid(in: path.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawGrid(in r: CGRect) {
        let g = NSBezierPath()
        var x = r.minX; while x <= r.maxX { g.move(to: CGPoint(x: x, y: r.minY)); g.line(to: CGPoint(x: x, y: r.maxY)); x += gridStep }
        var y = r.minY; while y <= r.maxY { g.move(to: CGPoint(x: r.minX, y: y)); g.line(to: CGPoint(x: r.maxX, y: y)); y += gridStep }
        g.lineWidth = 1
        gridLine.setStroke()
        g.stroke()
    }

    static func divider(height: CGFloat = 24) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = divider.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
}
