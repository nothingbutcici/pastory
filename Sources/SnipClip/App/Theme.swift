import AppKit

/// One place for the look: dark islands, lime accent, white type.
enum Theme {
    static let bg = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)          // #1C1C1E
    static let bgElevated = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)  // #2C2C2E
    static let lime = NSColor(srgbRed: 0.78, green: 0.96, blue: 0.36, alpha: 1)        // #C8F55B
    static let onLime = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.06, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let muted = NSColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1)       // #9A9AA0
    static let divider = NSColor(calibratedWhite: 1, alpha: 0.12)
    static let red = NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)         // #E5484D
    static let cornerRadius: CGFloat = 14

    // Shelf (dark, lavender accent)
    static let shelfBG = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1)   // #18181B
    static let shelfSide = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.133, alpha: 1) // #1E1E22
    static let shelfCard = NSColor(srgbRed: 0.137, green: 0.137, blue: 0.157, alpha: 1) // #232328
    static let shelfBorder = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.23, alpha: 1)  // #33333A
    static let shelfInk = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let shelfMuted = NSColor(srgbRed: 0.62, green: 0.62, blue: 0.66, alpha: 1)   // #9E9EA8
    static let cream = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.89, alpha: 1)        // #F2EDE3 content paper
    static let creamInk = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1)
    static let purple = NSColor(srgbRed: 0.71, green: 0.64, blue: 0.95, alpha: 1)       // #B5A3F2
    static let onPurple = NSColor(srgbRed: 0.12, green: 0.09, blue: 0.20, alpha: 1)
    // Kind tags (pastel fill, dark text)
    static let tagMP4 = NSColor(srgbRed: 0.95, green: 0.82, blue: 0.55, alpha: 1)       // amber
    static let tagGIF = NSColor(srgbRed: 0.96, green: 0.64, blue: 0.55, alpha: 1)       // coral
    static let tagImage = NSColor(srgbRed: 0.61, green: 0.80, blue: 0.97, alpha: 1)     // sky
    static let tagText = NSColor(srgbRed: 0.56, green: 0.85, blue: 0.81, alpha: 1)      // teal
    static let tagLink = NSColor(srgbRed: 0.79, green: 0.74, blue: 0.96, alpha: 1)      // lavender
    static let tagFiles = NSColor(srgbRed: 0.78, green: 0.78, blue: 0.82, alpha: 1)     // gray

    static func shadow() -> NSShadow {
        let s = NSShadow()
        s.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        s.shadowBlurRadius = 14
        s.shadowOffset = CGSize(width: 0, height: -3)
        return s
    }

    /// Product logo (Resources/Logo.png). Falls back to the source tree so self-tests find it too.
    static let logo: NSImage? = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Logo.png"), let img = NSImage(contentsOf: url) { return img }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Logo.png")
        return NSImage(contentsOf: dev)
    }()

    static func island(_ v: NSView, radius: CGFloat = cornerRadius) {
        v.wantsLayer = true
        v.layer?.backgroundColor = bg.cgColor
        v.layer?.cornerRadius = radius
        v.layer?.borderWidth = 0.5
        v.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        v.shadow = shadow()
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
