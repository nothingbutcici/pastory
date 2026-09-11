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
        let k = min(1, min((vf.width * 0.8 - 80) / natural.width, (vf.height * 0.8 - 160) / natural.height))
        let canvasSize = CGSize(width: max(320, (natural.width * k).rounded()), height: max(180, (natural.height * k).rounded()))
        let pad: CGFloat = 40
        let barH: CGFloat = 56 + 60   // toolbar + room for the sub bar
        let rect = CGRect(x: 0, y: 0, width: max(canvasSize.width + pad * 2, 900), height: canvasSize.height + pad + 44 + barH)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "编辑图片"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.shelfBG
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let content = GridBackdropView(frame: rect)
        canvas = AnnotateView(frame: CGRect(x: ((rect.width - canvasSize.width) / 2).rounded(), y: barH + 20, width: canvasSize.width, height: canvasSize.height), image: image)
        canvas.delegate = self
        content.addSubview(canvas)
        toolbar = AnnotateToolbar(canvas: canvas, doneTitle: "保存")
        let ts = toolbar.fittingSize
        toolbar.frame = CGRect(x: ((rect.width - ts.width) / 2).rounded(), y: barH - ts.height + 4, width: ts.width, height: ts.height)
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
