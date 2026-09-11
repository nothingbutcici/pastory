import AppKit

/// Draws annotations into a y-down CGContext measured in canvas points.
/// Used live by AnnotateView and offline by `render` (which scales up to image pixels).
enum AnnotationRenderer {
    /// Composite annotations onto the capture. Output keeps the capture's size and color space.
    static func render(_ image: CGImage, annotations: [Annotation], canvasSize: CGSize) -> CGImage? {
        guard !annotations.isEmpty else { return image }
        let w = image.width, h = image.height
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let scale = CGFloat(w) / canvasSize.width
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        for a in annotations { draw(a, in: ctx, source: image, pixelsPerPoint: scale) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func draw(_ a: Annotation, in ctx: CGContext, source: CGImage, pixelsPerPoint: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(CGFloat(a.size.rawValue))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch a.tool {
        case .rect:
            ctx.stroke(a.rect)
        case .ellipse:
            ctx.strokeEllipse(in: a.rect)
        case .arrow:
            guard a.points.count >= 2 else { return }
            drawArrow(from: a.points[0], to: a.points[a.points.count - 1], width: CGFloat(a.size.rawValue), in: ctx)
        case .pen:
            guard a.points.count > 1 else { return }
            ctx.beginPath()
            ctx.move(to: a.points[0])
            for p in a.points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        case .text:
            guard let p = a.points.first, !a.text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: a.size.fontSize, weight: .semibold),
                .foregroundColor: a.color,
                .strokeColor: a.color.isLight ? NSColor.black.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.6),
                .strokeWidth: -2.0,
            ]
            (a.text as NSString).draw(at: p, withAttributes: attrs)
        case .mosaic:
            pixelate(a.rect, source: source, pixelsPerPoint: pixelsPerPoint, in: ctx)
        case .badge:
            guard let p = a.points.first else { return }
            let r = a.size.badgeRadius
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: r * 1.15, weight: .bold),
                .foregroundColor: a.color.isLight ? NSColor.black : NSColor.white,
            ]
            let s = "\(a.number)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
        }
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, width: CGFloat, in ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let head = min(len * 0.5, 10 + width * 3)
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        let half = head * 0.45
        let left = CGPoint(x: base.x - uy * half, y: base.y + ux * half)
        let right = CGPoint(x: base.x + uy * half, y: base.y - ux * half)
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: b.x - ux * head * 0.6, y: b.y - uy * head * 0.6))
        ctx.strokePath()
        ctx.beginPath()
        ctx.move(to: b); ctx.addLine(to: left); ctx.addLine(to: right); ctx.closePath()
        ctx.fillPath()
    }

    /// Block-average the region: shrink to a few cells, blow back up without interpolation.
    private static func pixelate(_ rect: CGRect, source: CGImage, pixelsPerPoint: CGFloat, in ctx: CGContext) {
        let px = CGRect(x: rect.minX * pixelsPerPoint, y: rect.minY * pixelsPerPoint,
                        width: rect.width * pixelsPerPoint, height: rect.height * pixelsPerPoint).integral
        guard px.width >= 1, px.height >= 1, let crop = source.cropping(to: px) else { return }
        let block = max(6, 12 * pixelsPerPoint)
        let cw = max(1, Int(px.width / block)), ch = max(1, Int(px.height / block))
        guard let small = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        guard let tiny = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        // The context is y-down; flip locally so the image is upright.
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(tiny, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }
}
