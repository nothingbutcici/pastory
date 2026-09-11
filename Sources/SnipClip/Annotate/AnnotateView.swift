import AppKit
import Carbon.HIToolbox

@MainActor
protocol AnnotateDelegate: AnyObject {
    func annotateDidFinish(_ image: CGImage)
    func annotateDidCancel()
    func annotateRequestOCR(_ image: CGImage)
}

/// The frozen capture with vector annotations on top. Flipped: y grows downward, like the image.
/// Excalidraw rules: drawing a shape selects it and drops you back into the select tool,
/// where you can drag things around; the pen stays active for multiple strokes.
final class AnnotateView: NSView, NSTextFieldDelegate {
    let image: CGImage
    private let nsImage: NSImage
    weak var delegate: AnnotateDelegate?
    var onStateChange: (() -> Void)?

    var tool: AnnotateTool = .rect { didSet { commitTextEditor(); if tool != .select { selectedID = nil }; window?.invalidateCursorRects(for: self); onStateChange?() } }
    var color: NSColor = AnnotatePalette.colors[1] { didSet { applyToSelected { $0.color = color } } }
    var size: StrokeSize = .m { didSet { applyToSelected { $0.size = size } } }
    var dashed = false { didSet { applyToSelected { $0.dashed = dashed } } }
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true; onStateChange?() } }
    private var draft: Annotation?
    private(set) var selectedID: UUID? { didSet { needsDisplay = true; onStateChange?() } }
    private var dragLast: CGPoint?
    private var editor: NSTextField?
    private var editorAnchor: CGPoint = .zero
    private var editingID: UUID?

    init(frame: CGRect, image: CGImage) {
        self.image = image
        nsImage = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        let c: NSCursor = tool == .select ? .arrow : (tool == .text ? .iBeam : .crosshair)
        addCursorRect(bounds, cursor: c)
    }

    var canUndo: Bool { !annotations.isEmpty }
    var hasSelection: Bool { selectedID != nil }

    func undo() {
        commitTextEditor()
        _ = annotations.popLast()
        selectedID = nil
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    private func applyToSelected(_ change: (inout Annotation) -> Void) {
        if let id = selectedID, let i = annotations.firstIndex(where: { $0.id == id }) { change(&annotations[i]) }
        onStateChange?()
    }

    /// Flattened result.
    func renderedImage() -> CGImage {
        commitTextEditor()
        return AnnotationRenderer.render(image, annotations: annotations, canvasSize: bounds.size) ?? image
    }

    func finish() { delegate?.annotateDidFinish(renderedImage()) }
    func cancel() { delegate?.annotateDidCancel() }
    func requestOCR() { commitTextEditor(); delegate?.annotateRequestOCR(image) }

    /// Self-test only.
    func debugSet(_ list: [Annotation], select: Int? = nil) {
        annotations = list
        if let select, list.indices.contains(select) { selectedID = list[select].id; tool = .select }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ppp = CGFloat(image.width) / bounds.width
        for a in annotations where a.id != editingID { AnnotationRenderer.draw(a, in: ctx, source: image, pixelsPerPoint: ppp) }
        if let draft { AnnotationRenderer.draw(draft, in: ctx, source: image, pixelsPerPoint: ppp) }
        if let id = selectedID, let a = annotations.first(where: { $0.id == id }) { AnnotationRenderer.drawSelection(a, in: ctx) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if editor != nil { commitTextEditor() }
        switch tool {
        case .select:
            if let hitIndex = annotations.lastIndex(where: { $0.hit(p) }) {
                let a = annotations[hitIndex]
                if event.clickCount == 2, a.tool == .text { editText(a); return }
                selectedID = a.id
                dragLast = p
            } else {
                selectedID = nil
                if event.clickCount == 2 { finish() }
            }
        case .text:
            beginTextEditor(at: p, text: "", replacing: nil)
        default:
            if event.clickCount == 2, draft == nil { finish(); return }
            draft = Annotation(tool: tool, color: color, size: size, dashed: dashed, points: [p, p])
        }
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(0, p.x), bounds.width); p.y = min(max(0, p.y), bounds.height)
        if var d = draft {
            if d.tool == .pen { d.points.append(p) } else { d.points[1] = p }
            draft = d
            needsDisplay = true
        } else if let last = dragLast, let id = selectedID, let i = annotations.firstIndex(where: { $0.id == id }) {
            annotations[i].translate(CGPoint(x: p.x - last.x, y: p.y - last.y))
            dragLast = p
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragLast = nil
        guard let d = draft else { return }
        draft = nil
        let r = d.rect
        let big = d.tool == .pen ? d.points.count > 1 : (r.width > 2 || r.height > 2)
        guard big else { needsDisplay = true; return }
        annotations.append(d)
        if d.tool != .pen {
            tool = .select
            selectedID = d.id
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: finish(); return
        case kVK_Escape:
            if selectedID != nil { selectedID = nil; tool = .select } else { cancel() }
            return
        case kVK_ANSI_Z where cmd: undo(); return
        case kVK_Delete, kVK_ForwardDelete: deleteSelected(); return
        default: break
        }
        if !cmd, let ch = event.charactersIgnoringModifiers?.lowercased().first,
           let t = AnnotateTool.allCases.first(where: { $0.key == ch }) {
            tool = t
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { cancel() }

    // MARK: Text tool

    private func editText(_ a: Annotation) {
        guard let p = a.points.first else { return }
        color = a.color
        size = a.size
        editingID = a.id
        needsDisplay = true
        beginTextEditor(at: p, text: a.text, replacing: a.id)
    }

    private func beginTextEditor(at p: CGPoint, text: String, replacing: UUID?) {
        let font = HandFont.font(size: size.fontSize)
        let tf = NSTextField(frame: CGRect(x: p.x - 2, y: p.y - 2, width: max(160, bounds.width - p.x + 2), height: font.pointSize * 1.5))
        tf.font = font
        tf.textColor = color
        tf.stringValue = text
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.placeholderAttributedString = NSAttributedString(string: "输入文字", attributes: [.font: font, .foregroundColor: color.withAlphaComponent(0.35)])
        tf.delegate = self
        tf.target = self
        tf.action = #selector(editorReturn)
        addSubview(tf)
        editor = tf
        editorAnchor = p
        editingID = replacing
        window?.makeFirstResponder(tf)
        if let fe = tf.currentEditor() as? NSTextView {
            fe.insertionPointColor = color
            fe.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    @objc private func editorReturn() { commitTextEditor() }

    func commitTextEditor() {
        guard let tf = editor else { return }
        editor = nil
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)
        let replacing = editingID
        editingID = nil
        if let replacing, let i = annotations.firstIndex(where: { $0.id == replacing }) {
            if text.isEmpty { annotations.remove(at: i) } else { annotations[i].text = text; annotations[i].points = [editorAnchor] }
            needsDisplay = true
            return
        }
        if !text.isEmpty {
            let a = Annotation(tool: .text, color: color, size: size, points: [editorAnchor], text: text)
            annotations.append(a)
            tool = .select
            selectedID = a.id
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            editor?.stringValue = ""
            editingID = nil
            commitTextEditor()
            return true
        }
        return false
    }
}
