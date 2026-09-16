import AppKit

/// Excalidraw-flavoured drawing: every stroke is flattened to points, nudged by smooth
/// low-frequency noise and drawn twice, so shapes look hand-drawn but stay legible.
/// Contexts are y-down and measured in canvas points; `render` scales that up to image pixels.
enum AnnotationRenderer {
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
        ctx.setLineWidth(a.size.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var rng = Seeded(a.seed)
        switch a.tool {
        case .rect:
            let r = a.rect
            let radius = min(12, min(r.width, r.height) * 0.2)
            sketch(NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius), closed: true, size: a.size, rng: &rng, in: ctx)
        case .ellipse:
            sketch(NSBezierPath(ovalIn: a.rect), closed: true, size: a.size, rng: &rng, in: ctx)
        case .line, .arrow:
            guard a.points.count >= 2 else { return }
            let p0 = a.points[0], p1 = a.points[a.points.count - 1]
            let path = NSBezierPath()
            path.move(to: p0); path.line(to: p1)
            sketch(path, closed: false, size: a.size, rng: &rng, in: ctx)
            if a.tool == .arrow { arrowHead(from: p0, to: p1, size: a.size, rng: &rng, in: ctx) }
        case .pen:
            guard a.points.count > 1 else { return }
            ctx.addPath(smoothPath(a.points))
            ctx.strokePath()
        case .text:
            guard let p = a.points.first, !a.text.isEmpty else { return }
            (a.text as NSString).draw(at: p, withAttributes: a.textAttributes)
        case .mosaic:
            pixelate(a.rect, block: a.size.mosaicBlock, source: source, pixelsPerPoint: pixelsPerPoint, in: ctx)
        }
    }

    // MARK: Hand-drawn strokes

    /// Two jittered passes over the flattened path.
    private static func sketch(_ path: NSBezierPath, closed: Bool, size: StrokeSize, rng: inout Seeded, in ctx: CGContext) {
        path.flatness = 0.3
        let pts = flatten(path)
        guard pts.count > 1 else { return }
        let amp = 0.9 + size.lineWidth * 0.25
        for pass in 0..<2 {
            let f1 = closed ? CGFloat(Int.random(in: 2...3, using: &rng)) : CGFloat(Int.random(in: 1...2, using: &rng))
            let f2 = closed ? CGFloat(Int.random(in: 5...7, using: &rng)) : CGFloat(Int.random(in: 3...5, using: &rng))
            let ph1 = CGFloat.random(in: 0...(2 * .pi), using: &rng), ph2 = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let ph3 = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let scaleAmp = pass == 0 ? amp : amp * 0.8
            let out = CGMutablePath()
            for (i, p) in pts.enumerated() {
                let t = CGFloat(i) / CGFloat(pts.count - 1)
                var n = sin(2 * .pi * f1 * t + ph1) * 0.6 + sin(2 * .pi * f2 * t + ph2) * 0.4
                var m = cos(2 * .pi * f1 * t + ph3) * 0.5
                if !closed { let taper = sin(t * .pi); n *= taper; m *= taper }
                let q = CGPoint(x: p.x + n * scaleAmp, y: p.y + m * scaleAmp)
                if i == 0 { out.move(to: q) } else { out.addLine(to: q) }
            }
            if closed { out.closeSubpath() }
            ctx.addPath(out)
            ctx.strokePath()
        }
    }

    private static func flatten(_ path: NSBezierPath) -> [CGPoint] {
        let flat = path.flattened
        var pts: [CGPoint] = []
        var buf = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<flat.elementCount {
            let el = flat.element(at: i, associatedPoints: &buf)
            switch el {
            case .moveTo, .lineTo: pts.append(buf[0])
            case .closePath: if let f = pts.first { pts.append(f) }
            default: break
            }
        }
        // Densify long segments so the noise has something to bend.
        var dense: [CGPoint] = []
        for i in 0..<pts.count {
            let p = pts[i]
            if i > 0 {
                let q = pts[i - 1]
                let d = hypot(p.x - q.x, p.y - q.y)
                let n = Int(d / 6)
                if n > 1 { for k in 1..<n { let t = CGFloat(k) / CGFloat(n); dense.append(CGPoint(x: q.x + (p.x - q.x) * t, y: q.y + (p.y - q.y) * t)) } }
            }
            dense.append(p)
        }
        return dense
    }

    /// Open V head, like Excalidraw's default arrow.
    private static func arrowHead(from a: CGPoint, to b: CGPoint, size: StrokeSize, rng: inout Seeded, in ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let head = min(len * 0.6, 12 + size.lineWidth * 3.5)
        let ang: CGFloat = 0.42
        for s in [CGFloat(1), -1] {
            let vx = ux * cos(ang) - s * uy * sin(ang), vy = s * ux * sin(ang) + uy * cos(ang)
            let p = CGPoint(x: b.x - vx * head, y: b.y - vy * head)
            let path = NSBezierPath()
            path.move(to: p); path.line(to: b)
            sketch(path, closed: false, size: size, rng: &rng, in: ctx)
        }
    }

    /// Quadratic curve through midpoints: smooth freehand without over-rounding.
    private static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: pts[0])
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    /// Block-average the region: shrink to a few cells, blow back up without interpolation.
    private static func pixelate(_ rect: CGRect, block blockPoints: CGFloat, source: CGImage, pixelsPerPoint: CGFloat, in ctx: CGContext) {
        let px = CGRect(x: rect.minX * pixelsPerPoint, y: rect.minY * pixelsPerPoint,
                        width: rect.width * pixelsPerPoint, height: rect.height * pixelsPerPoint).integral
        guard px.width >= 1, px.height >= 1, let crop = source.cropping(to: px) else { return }
        let block = max(4, blockPoints * pixelsPerPoint)
        let cw = max(1, Int(px.width / block)), ch = max(1, Int(px.height / block))
        guard let small = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        guard let tiny = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(tiny, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static let handleRadius: CGFloat = 4.5
    static let deleteRadius: CGFloat = 10

    /// Where the delete button sits for a selected annotation: just outside its top-right corner.
    static func deleteCenter(_ a: Annotation) -> CGPoint {
        let r = a.bounds.insetBy(dx: -8, dy: -8)
        return CGPoint(x: r.maxX + 6, y: r.minY - 6)
    }
    static func deleteRect(_ a: Annotation) -> CGRect {
        let c = deleteCenter(a)
        return CGRect(x: c.x - deleteRadius, y: c.y - deleteRadius, width: 2 * deleteRadius, height: 2 * deleteRadius)
    }

    /// Selection chrome (live view only): dashed box for boxes/text/pen, handles, and a delete bubble.
    static func drawSelection(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(Theme.paperBlueDeep.cgColor)
        ctx.setLineWidth(1)
        if a.tool != .arrow && a.tool != .line {
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(a.bounds.insetBy(dx: -8, dy: -8))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.setFillColor(Theme.paper.cgColor)
        ctx.setStrokeColor(Theme.ink.cgColor)
        ctx.setLineWidth(1.2)
        for p in a.handles {
            let d = CGRect(x: p.x - handleRadius, y: p.y - handleRadius, width: 2 * handleRadius, height: 2 * handleRadius)
            ctx.fillEllipse(in: d)
            ctx.strokeEllipse(in: d)
        }
        // Delete button: paper disc, ink ×, soft shadow.
        let c = deleteCenter(a)
        let d = deleteRect(a)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor(calibratedWhite: 0, alpha: 0.3).cgColor)
        ctx.setFillColor(Theme.paper.cgColor)
        ctx.fillEllipse(in: d)
        ctx.restoreGState()
        ctx.setStrokeColor(Theme.ink.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: d.insetBy(dx: 0.5, dy: 0.5))
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        let k: CGFloat = 3.4
        ctx.move(to: CGPoint(x: c.x - k, y: c.y - k)); ctx.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        ctx.move(to: CGPoint(x: c.x + k, y: c.y - k)); ctx.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// Tiny deterministic generator (SplitMix64) so a shape's wobble never changes between frames.
struct Seeded: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
