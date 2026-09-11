import AppKit
import Carbon.HIToolbox

@MainActor
protocol AnnotateDelegate: AnyObject {
    func annotateDidFinish(_ image: CGImage)
    func annotateDidCancel()
    func annotateRequestOCR(_ image: CGImage)
    func annotateRequestRecord()
}

/// The frozen capture with vector annotations on top. Flipped: y grows downward, like the image.
/// The current tool stays active. Clicking a drawn element selects it instead of drawing:
/// drag to move, pull a handle to reshape, hit the ✕ bubble or ⌫ to delete, click selected text to edit it.
final class AnnotateView: NSView, NSTextFieldDelegate {
    private(set) var image: CGImage
    private var nsImage: NSImage
    weak var delegate: AnnotateDelegate?
    var onStateChange: (() -> Void)?

    /// nil = no tool: clicks only select / move; nothing gets drawn.
    var tool: AnnotateTool? = nil { didSet { commitTextEditor(); window?.invalidateCursorRects(for: self); onStateChange?() } }
    var color: NSColor = AnnotatePalette.colors[1] { didSet { applyToSelected { $0.color = color } } }
    var size: StrokeSize = .m { didSet { applyToSelected { $0.size = size } } }
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true; onStateChange?() } }
    private var draft: Annotation?
    private(set) var selectedID: UUID? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self); onStateChange?() } }

    private enum Drag { case move(last: CGPoint), handle(Int) }
    private var drag: Drag?
    private var moved = false
    /// Set when a click lands on already-selected text; becomes an edit if the mouse does not move.
    private var pendingEdit: UUID?

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
        let c: NSCursor = tool == nil ? .arrow : (tool == .text ? .iBeam : .crosshair)
        addCursorRect(bounds, cursor: c)
        // Selection chrome gets the pointer: the delete button and the handles are buttons, not canvas.
        if let a = selected {
            addCursorRect(AnnotationRenderer.deleteRect(a).insetBy(dx: -2, dy: -2), cursor: .pointingHand)
            for h in a.handles {
                addCursorRect(CGRect(x: h.x - 8, y: h.y - 8, width: 16, height: 16), cursor: .arrow)
            }
        }
    }

    var canUndo: Bool { !annotations.isEmpty }
    var hasSelection: Bool { selectedID != nil }
    private var selectedIndex: Int? { selectedID.flatMap { id in annotations.firstIndex { $0.id == id } } }
    var selected: Annotation? { selectedIndex.map { annotations[$0] } }
    /// What the sub-bar should describe: the selected element, else the active tool.
    var activeKind: AnnotateTool? { selected?.tool ?? tool }
    var effectiveColor: NSColor { selected?.color ?? color }
    var effectiveSize: StrokeSize { selected?.size ?? size }

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
        if let i = selectedIndex { change(&annotations[i]) }
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
    func requestRecord() { commitTextEditor(); delegate?.annotateRequestRecord() }

    /// Region resized: new crop, new frame; annotations stay put on screen.
    func replaceImage(_ img: CGImage, frame newFrame: CGRect) {
        let d = CGPoint(x: frame.minX - newFrame.minX, y: newFrame.maxY - frame.maxY)   // view is flipped: y from the top edge
        for i in annotations.indices { annotations[i].translate(d) }
        image = img
        nsImage = NSImage(cgImage: img, size: newFrame.size)
        frame = newFrame
        needsDisplay = true
    }

    /// Self-test only.
    func debugSet(_ list: [Annotation], select: Int? = nil) {
        annotations = list
        if let select, list.indices.contains(select) { selectedID = list[select].id }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ppp = CGFloat(image.width) / bounds.width
        for a in annotations where a.id != editingID { AnnotationRenderer.draw(a, in: ctx, source: image, pixelsPerPoint: ppp) }
        if let draft { AnnotationRenderer.draw(draft, in: ctx, source: image, pixelsPerPoint: ppp) }
        if let i = selectedIndex, editingID == nil { AnnotationRenderer.drawSelection(annotations[i], in: ctx) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if editor != nil { commitTextEditor() }
        moved = false
        pendingEdit = nil

        // 1. Chrome of the current selection: delete bubble, handles.
        if let i = selectedIndex {
            let a = annotations[i]
            let c = AnnotationRenderer.deleteCenter(a)
            if hypot(p.x - c.x, p.y - c.y) <= AnnotationRenderer.deleteRadius + 2 { deleteSelected(); return }
            if let h = a.handles.firstIndex(where: { hypot(p.x - $0.x, p.y - $0.y) <= AnnotationRenderer.handleRadius + 4 }) {
                drag = .handle(h)
                return
            }
        }
        // 2. An existing element under the cursor: select it (and maybe edit text).
        if let hitIndex = annotations.lastIndex(where: { $0.hit(p) }) {
            let a = annotations[hitIndex]
            if a.tool == .text, selectedID == a.id || event.clickCount == 2 { pendingEdit = a.id }
            selectedID = a.id
            drag = .move(last: p)
            return
        }
        // 3. Empty space: deselect; double-click finishes; otherwise start drawing with the active tool.
        if selectedID != nil { selectedID = nil; if event.clickCount == 2 { return } }
        if event.clickCount == 2, draft == nil { finish(); return }
        guard let tool else { return }
        if tool == .text {
            beginTextEditor(at: p, text: "", replacing: nil)
        } else {
            draft = Annotation(tool: tool, color: color, size: size, points: [p, p])
        }
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(0, p.x), bounds.width); p.y = min(max(0, p.y), bounds.height)
        moved = true
        if var d = draft {
            if d.tool == .pen { d.points.append(p) } else { d.points[1] = p }
            draft = d
            needsDisplay = true
            return
        }
        guard let i = selectedIndex, let drag else { return }
        switch drag {
        case .move(let last):
            annotations[i].translate(CGPoint(x: p.x - last.x, y: p.y - last.y))
            self.drag = .move(last: p)
        case .handle(let h):
            annotations[i].setHandle(h, to: p)
        }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; pendingEdit = nil }
        if let id = pendingEdit, !moved, let a = annotations.first(where: { $0.id == id }) { editText(a); return }
        guard let d = draft else { return }
        draft = nil
        let r = d.rect
        let big = d.tool == .pen ? d.points.count > 1 : (r.width > 2 || r.height > 2)
        guard big else { needsDisplay = true; return }
        annotations.append(d)
        selectedID = d.tool == .pen ? nil : d.id
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: finish(); return
        case kVK_Escape:
            if selectedID != nil { selectedID = nil } else { cancel() }
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
            if text.isEmpty { annotations.remove(at: i); selectedID = nil } else { annotations[i].text = text; annotations[i].points = [editorAnchor] }
            needsDisplay = true
            return
        }
        if !text.isEmpty {
            let a = Annotation(tool: .text, color: color, size: size, points: [editorAnchor], text: text)
            annotations.append(a)
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
