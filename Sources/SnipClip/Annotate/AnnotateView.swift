import AppKit
import Carbon.HIToolbox

@MainActor
protocol AnnotateDelegate: AnyObject {
    func annotateDidFinish(_ image: CGImage)
    func annotateDidCancel()
    func annotateRequestOCR(_ image: CGImage)
}

/// The frozen capture with vector annotations on top. Flipped: y grows downward, like the image.
final class AnnotateView: NSView, NSTextFieldDelegate {
    let image: CGImage
    private let nsImage: NSImage
    weak var delegate: AnnotateDelegate?
    var onStateChange: (() -> Void)?

    var tool: AnnotateTool = .rect { didSet { commitTextEditor(); onStateChange?() } }
    var color: NSColor = AnnotatePalette.colors[0] { didSet { onStateChange?() } }
    var size: StrokeSize = .medium { didSet { onStateChange?() } }
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true; onStateChange?() } }
    private var draft: Annotation?
    private var badgeCount = 0
    private var editor: NSTextField?
    private var editorAnchor: CGPoint = .zero

    init(frame: CGRect, image: CGImage) {
        self.image = image
        nsImage = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair) }

    var canUndo: Bool { !annotations.isEmpty }
    /// Self-test only.
    func debugSet(_ list: [Annotation]) { annotations = list; badgeCount = list.filter { $0.tool == .badge }.count }
    func undo() {
        commitTextEditor()
        guard let last = annotations.popLast() else { return }
        if last.tool == .badge { badgeCount = max(0, badgeCount - 1) }
    }

    /// Flattened result.
    func renderedImage() -> CGImage {
        commitTextEditor()
        return AnnotationRenderer.render(image, annotations: annotations, canvasSize: bounds.size) ?? image
    }

    func finish() { delegate?.annotateDidFinish(renderedImage()) }
    func cancel() { delegate?.annotateDidCancel() }
    func requestOCR() { commitTextEditor(); delegate?.annotateRequestOCR(image) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ppp = CGFloat(image.width) / bounds.width
        for a in annotations { AnnotationRenderer.draw(a, in: ctx, source: image, pixelsPerPoint: ppp) }
        if let draft { AnnotationRenderer.draw(draft, in: ctx, source: image, pixelsPerPoint: ppp) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, tool != .text, tool != .badge, draft == nil { finish(); return }
        switch tool {
        case .text:
            commitTextEditor()
            beginTextEditor(at: p)
        case .badge:
            badgeCount += 1
            annotations.append(Annotation(tool: .badge, color: color, size: size, points: [p], number: badgeCount))
        default:
            commitTextEditor()
            draft = Annotation(tool: tool, color: color, size: size, points: [p, p])
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var d = draft else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(0, p.x), bounds.width); p.y = min(max(0, p.y), bounds.height)
        if d.tool == .pen { d.points.append(p) } else { d.points[1] = p }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = draft else { return }
        draft = nil
        let r = d.rect
        let big = d.tool == .pen ? d.points.count > 1 : (r.width > 2 || r.height > 2)
        if big { annotations.append(d) } else { needsDisplay = true }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: finish()
        case kVK_Escape: cancel()
        case kVK_ANSI_Z where cmd: undo()
        case kVK_Delete where !cmd: undo()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { cancel() }

    // MARK: Text tool

    private func beginTextEditor(at p: CGPoint) {
        let tf = NSTextField(frame: CGRect(x: p.x, y: p.y, width: max(120, bounds.width - p.x), height: size.fontSize + 10))
        tf.font = NSFont.systemFont(ofSize: size.fontSize, weight: .semibold)
        tf.textColor = color
        tf.isBordered = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor(calibratedWhite: color.isLight ? 0 : 1, alpha: 0.25)
        tf.focusRingType = .none
        tf.placeholderString = "输入文字，⏎ 确认"
        tf.delegate = self
        tf.target = self
        tf.action = #selector(editorReturn)
        addSubview(tf)
        editor = tf
        editorAnchor = p
        window?.makeFirstResponder(tf)
    }

    @objc private func editorReturn() { commitTextEditor() }

    func commitTextEditor() {
        guard let tf = editor else { return }
        editor = nil
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)
        if !text.isEmpty {
            // NSTextField draws its text ~2pt in from the frame; match it so the committed text does not jump.
            annotations.append(Annotation(tool: .text, color: color, size: size,
                                          points: [CGPoint(x: editorAnchor.x + 2, y: editorAnchor.y + 3)], text: text))
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            editor?.stringValue = ""
            commitTextEditor()
            return true
        }
        return false
    }
}
