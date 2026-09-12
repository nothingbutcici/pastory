import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One-shot capture through ScreenCaptureKit. The image keeps the display's own
/// color space (Display P3 on most Macs) so nothing is re-encoded to sRGB.
enum Screenshotter {
    static func capture(_ target: CaptureTarget, snapshot: ShareableSnapshot) async throws -> CGImage {
        let filter: SCContentFilter
        switch target {
        case .display(let d), .region(let d, _):
            filter = SCContentFilter(display: d, excludingWindows: snapshot.ownWindows)
        case .window(let w):
            filter = SCContentFilter(desktopIndependentWindow: w)
        }
        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.captureResolution = .best
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.scalesToFit = false
        let scale = Self.pixelScale(filter, screen: screen(for: target, snapshot: snapshot))
        let pointSize: CGSize
        switch target {
        case .region(_, let r):
            cfg.sourceRect = r
            pointSize = r.size
        case .display, .window:
            pointSize = filter.contentRect.size
        }
        cfg.width = Int((pointSize.width * scale).rounded())
        cfg.height = Int((pointSize.height * scale).rounded())
        if let screen = screen(for: target, snapshot: snapshot),
           let name = screen.colorSpace?.cgColorSpace?.name {
            cfg.colorSpaceName = name
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Whole display, excluding just the given windows (the picker's masks), fetched fresh.
    /// Other Pastory windows, the shelf included, stay in the picture. Region / window shots are crops of this.
    static func captureDisplay(_ display: SCDisplay, excluding ids: Set<CGWindowID>, screen: NSScreen?, colorSpaceName: CFString?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let own = content.windows.filter { ids.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: own)
        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.captureResolution = .best
        cfg.showsCursor = false
        cfg.scalesToFit = false
        let scale = pixelScale(filter, screen: screen)
        cfg.width = Int((filter.contentRect.width * scale).rounded())
        cfg.height = Int((filter.contentRect.height * scale).rounded())
        if let colorSpaceName { cfg.colorSpaceName = colorSpaceName }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Pixels per point for the output size. The screen's backing scale is what the user sees;
    /// `pointPixelScale` alone has come back as 1 on some displays and produced half-resolution pictures.
    static func pixelScale(_ filter: SCContentFilter, screen: NSScreen?) -> CGFloat {
        max(CGFloat(filter.pointPixelScale), screen?.backingScaleFactor ?? 1, 1)
    }

    static func screen(for target: CaptureTarget, snapshot: ShareableSnapshot) -> NSScreen? {
        switch target {
        case .display(let d), .region(let d, _):
            return snapshot.screen(for: d)
        case .window(let w):
            let r = CoordinateSpace.cocoaRect(fromCG: w.frame)
            return NSScreen.screens.max { $0.frame.intersection(r).area < $1.frame.intersection(r).area }
        }
    }

    /// PNG with the image's ICC profile embedded.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func tiffData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func image(fromPNG data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Downscale for shelf thumbnails; keeps the color space.
    static func thumbnail(_ image: CGImage, maxPixels: Int) -> CGImage? {
        let w = image.width, h = image.height
        let k = min(1, CGFloat(maxPixels) / CGFloat(max(w, h)))
        if k >= 1 { return image }
        let tw = max(1, Int(CGFloat(w) * k)), th = max(1, Int(CGFloat(h) * k))
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
