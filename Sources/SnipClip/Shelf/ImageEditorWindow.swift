import AppKit

/// The screenshot annotator, hosted in a window, for a picture already on the shelf.
/// 保存 writes the flattened image back to the same card and copies it.
@MainActor
final class ImageEditorWindow: NSObject, NSWindowDelegate, AnnotateDelegate {
    private static var open: [String: ImageEditorWindow] = [:]
    private let item: ClipItem
    private let window: NSWindow
    private var canvas: AnnotateView!
    private var toolbar: AnnotateToolbar!

    static func open(_ item: ClipItem) {
        if let w = open[item.id] { w.window.makeKeyAndOrderFront(nil); return }
        guard let png = ClipStore.shared.png(of: item), let cg = Screenshotter.image(fromPNG: png) else { NSSound.beep(); return }
        let e = ImageEditorWindow(item: item, image: cg)
        open[item.id] = e
        ShelfPanelController.shared.hide()
        NSApp.activate(ignoringOtherApps: true)
        e.window.makeKeyAndOrderFront(nil)
    }

    /// Self-test only.
    static func debugView(_ item: ClipItem) -> NSView? {
        guard let png = ClipStore.shared.png(of: item), let cg = Screenshotter.image(fromPNG: png) else { return nil }
        let e = ImageEditorWindow(item: item, image: cg)
        open[item.id] = e
        return e.window.contentView
    }

    private init(item: ClipItem, image: CGImage) {
        self.item = item
        let vf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        // Fit into 80% of the screen; small pictures are scaled up uniformly so the long edge is at least 360 pt.
        let fit = min((vf.width * 0.8 - 80) / natural.width, (vf.height * 0.8 - 200) / natural.height)
        let k = min(fit, max(1, 360 / max(natural.width, natural.height)))
        let canvasSize = CGSize(width: (natural.width * k).rounded(), height: (natural.height * k).rounded())
        let pad: CGFloat = 40
        let barH: CGFloat = 56 + 84   // toolbar + room for the sub bar under it
        let rect = CGRect(x: 0, y: 0, width: max(canvasSize.width + pad * 2, 900), height: canvasSize.height + pad + 44 + barH)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "编辑图片"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.brown
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let content = GridBackdropView(frame: rect)
        let canvasFrame = CGRect(x: ((rect.width - canvasSize.width) / 2).rounded(), y: barH + 20, width: canvasSize.width, height: canvasSize.height)
        // A paper mat + shadow behind the picture, so a dark image still reads against the desk.
        let border = CanvasFrameView(frame: canvasFrame.insetBy(dx: -6, dy: -6))
        content.addSubview(border)
        canvas = AnnotateView(frame: canvasFrame, image: image)
        canvas.delegate = self
        content.addSubview(canvas)
        toolbar = AnnotateToolbar(canvas: canvas, doneTitle: "保存")
        let ts = toolbar.fittingSize
        toolbar.frame = CGRect(x: ((rect.width - ts.width) / 2).rounded(), y: barH - ts.height - 4, width: ts.width, height: ts.height)
        content.addSubview(toolbar)
        window.contentView = content
        toolbar.didLayout()
        window.makeFirstResponder(canvas)
    }

    // MARK: AnnotateDelegate

    func annotateDidFinish(_ image: CGImage) {
        if let png = Screenshotter.pngData(image) {
            ClipStore.shared.updateImage(item.id, png: png)
            if let updated = ClipStore.shared.items.first(where: { $0.id == item.id }) { ClipStore.shared.copyToPasteboard(updated) }
        }
        window.close()
    }
    func annotateDidCancel() { window.close() }
    func annotateRequestOCR(_ image: CGImage) {
        let anchor = window.convertToScreen(canvas.frame)
        OCRPanelController.shared.show(near: anchor, image: image) { text in
            let it = ClipStore.shared.insertText(text, rtf: nil, source: CaptureCoordinator.source)
            PasteboardWriter.writeText(text, rtf: nil, itemID: it?.id ?? "")
            OCRPanelController.shared.close()
        }
    }
    func annotateRequestRecord() {}

    func windowWillClose(_ notification: Notification) {
        OCRPanelController.shared.close()
        Self.open[item.id] = nil
        ShelfPanelController.shared.show()
    }
}

/// Paper mat with a soft shadow; marks where the canvas ends.
final class CanvasFrameView: NSView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = 0
        layer?.cornerRadius = 2
        shadow = NSShadow()
        shadow?.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.6)
        shadow?.shadowBlurRadius = 18
        shadow?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.backgroundColor = Theme.paper.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}
