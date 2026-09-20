import AppKit
import Carbon.HIToolbox

@MainActor
protocol AnnotateDelegate: AnyObject {
    func annotateDidFinish(_ image: CGImage)
    func annotateDidCancel()
    func annotateRequestOCR(_ image: CGImage)
    func annotateRequestRecord()
    /// Drag on empty canvas with no tool: move the whole selection by (dx, dy) in window points.
    func annotateMoveRegion(dx: CGFloat, dy: CGFloat)
}
extension AnnotateDelegate { func annotateMoveRegion(dx: CGFloat, dy: CGFloat) {} }

/// The frozen capture with vector annotations on top. Flipped: y grows downward, like the image.
/// The current tool stays active. Clicking a drawn element selects it instead of drawing:
/// drag to move, pull a handle to reshape, hit the ✕ bubble or ⌫ to delete, click selected text to edit it.
final class AnnotateView: NSView, NSTextViewDelegate {
    private(set) var image: CGImage
    private var nsImage: NSImage
    weak var delegate: AnnotateDelegate?
    var onStateChange: (() -> Void)?

    /// nil = no tool: clicks only select / move; nothing gets drawn.
    var tool: AnnotateTool? = nil { didSet { commitTextEditor(); window?.invalidateCursorRects(for: self); onStateChange?() } }
    var color: NSColor = AnnotatePalette.colors[0] { didSet { applyToSelected { $0.color = color }; restyleEditor() } }
    var size: StrokeSize = .s { didSet { applyToSelected { $0.size = size }; restyleEditor() } }
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true; onStateChange?() } }
    private var draft: Annotation?
    private(set) var selectedID: UUID? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self); onStateChange?() } }

    private enum Drag { case move(last: CGPoint), handle(Int, original: Annotation, offset: CGPoint), region(lastWindow: CGPoint) }
    private var drag: Drag?
    private var moved = false
    /// Set when a click lands on already-selected text; becomes an edit if the mouse does not move.
    private var pendingEdit: UUID?

    private var editor: AnnotationTextView?
    private var editorAnchor: CGPoint = .zero
    private var editorBoxSize: CGSize = .zero
    /// A box nobody has resized follows its text; dragging a grip fixes the width and turns wrapping on.
    private var editorAutoWidth = true
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
        if let a = editingAnnotation ?? selected {
            addCursorRect(AnnotationRenderer.deleteRect(a).insetBy(dx: -2, dy: -2), cursor: .pointingHand)
            for (i, h) in AnnotationRenderer.selectionHandles(a).enumerated() {
                let cursor: NSCursor = a.tool == .text && i >= 4 ? (i < 6 ? .resizeLeftRight : .resizeUpDown) : .arrow
                addCursorRect(CGRect(x: h.x - 8, y: h.y - 8, width: 16, height: 16), cursor: cursor)
            }
        }
    }

    /// A text box's grips and delete chip. Points inside the box itself are text, never a grip: the hit zones are
    /// wider than the 4 pt gap to the outline, and would otherwise swallow a click on the first or last glyph.
    static func onTextChrome(_ a: Annotation, _ p: CGPoint) -> Bool {
        if AnnotationRenderer.deleteRect(a).contains(p) { return true }
        if a.bounds.contains(p) { return false }
        return AnnotationRenderer.selectionHandles(a).contains { hypot(p.x - $0.x, p.y - $0.y) <= AnnotationRenderer.handleRadius + 4 }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The editor fills its box, but its resize handles still belong to the canvas.
        let p = convert(point, from: superview)
        if let a = editingAnnotation, Self.onTextChrome(a, p) { return self }
        return super.hitTest(point)
    }

    var canUndo: Bool { !annotations.isEmpty }
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
        commitTextEditor()
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
        if let a = editingAnnotation ?? selected { AnnotationRenderer.drawSelection(a, in: ctx) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let a = editingAnnotation {
            // A click outside an open text box only confirms it: the frame goes away and nothing new starts.
            // (Its own grips and delete chip still work on the confirmed box.)
            let onChrome = Self.onTextChrome(a, p)
            commitTextEditor()
            if !onChrome || selected == nil { selectedID = nil; needsDisplay = true; return }      // an empty box leaves nothing to grab
        }
        moved = false
        pendingEdit = nil

        // 1. Chrome of the current selection: delete bubble, handles.
        if let i = selectedIndex {
            let a = annotations[i]
            let c = AnnotationRenderer.deleteCenter(a)
            if hypot(p.x - c.x, p.y - c.y) <= AnnotationRenderer.deleteRadius + 2 { deleteSelected(); return }
            if !(a.tool == .text && a.bounds.contains(p)),
               let h = AnnotationRenderer.selectionHandles(a).firstIndex(where: { hypot(p.x - $0.x, p.y - $0.y) <= AnnotationRenderer.handleRadius + 4 }) {
                drag = .handle(h, original: a, offset: CGPoint(x: p.x - a.handles[h].x, y: p.y - a.handles[h].y))
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
        guard let tool else {
            drag = .region(lastWindow: event.locationInWindow)      // no tool: drag moves the selection itself
            return
        }
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
        if case .region(let last)? = drag {
            let now = event.locationInWindow
            delegate?.annotateMoveRegion(dx: now.x - last.x, dy: now.y - last.y)
            drag = .region(lastWindow: now)
            return
        }
        guard let i = selectedIndex, let drag else { return }
        switch drag {
        case .move(let last):
            annotations[i].translate(CGPoint(x: p.x - last.x, y: p.y - last.y))
            self.drag = .move(last: p)
        case .handle(let h, let original, let offset):
            // Reflow can change the height; always resize from the mouse-down geometry.
            var resized = original
            resized.setHandle(h, to: CGPoint(x: p.x - offset.x, y: p.y - offset.y))
            annotations[i] = resized
        case .region:
            break
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
        let existing = replacing.flatMap { id in annotations.first { $0.id == id } }
        editorAutoWidth = existing?.textBoxSize == nil
        editorBoxSize = existing?.bounds.size ?? .zero
        editorAnchorForSizing = p
        if editorAutoWidth { editorBoxSize = CGSize(width: autoWidth(for: text), height: 0) }
        let tv = AnnotationTextView(frame: CGRect(origin: p, size: editorBoxSize))
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: editorBoxSize.width, height: .greatestFiniteMagnitude)
        tv.string = text
        tv.delegate = self
        tv.onCommit = { [weak self] in self?.commitTextEditor() }
        addSubview(tv)
        editor = tv
        editorAnchor = p
        editingID = replacing
        restyleEditor()
        window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
    }

    private var editingAnnotation: Annotation? {
        guard let tv = editor else { return nil }
        return Annotation(tool: .text, color: color, size: size, points: [editorAnchor], text: tv.string, textBoxSize: editorBoxSize)
    }

    private var editorAnchorForSizing: CGPoint = .zero
    /// Width that just fits the longest line (or the placeholder), never past the right edge of the picture.
    private func autoWidth(for text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: HandFont.font(size: size.fontSize)]
        let measured = ((text.isEmpty ? "输入文字".l : text) as NSString).size(withAttributes: attrs).width
        return max(32, min(ceil(measured) + 6, bounds.width - editorAnchorForSizing.x - 6))
    }

    /// nil = "hug the text". A box that ran into the right edge wrapped there, so it keeps that width.
    private func committedBoxSize(for text: String) -> CGSize? {
        guard editorAutoWidth else { return editorBoxSize }
        let natural = ceil((text as NSString).size(withAttributes: [.font: HandFont.font(size: size.fontSize)]).width) + 6
        return natural <= editorBoxSize.width + 0.5 ? nil : editorBoxSize
    }

    private func layoutEditor() {
        if editorAutoWidth, let tv = editor {
            editorBoxSize = CGSize(width: autoWidth(for: tv.string), height: 0)
            tv.textContainer?.containerSize = CGSize(width: editorBoxSize.width, height: .greatestFiniteMagnitude)
        }
        guard let tv = editor, let a = editingAnnotation else { return }
        tv.frame = a.bounds
        tv.needsDisplay = true
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func textDidChange(_ notification: Notification) { layoutEditor() }

    /// Colour / size picked while a text box is open: keep the editor and export in sync.
    private func restyleEditor() {
        guard let tv = editor, let a = editingAnnotation else { return }
        tv.font = HandFont.font(size: size.fontSize)
        tv.textColor = color
        tv.insertionPointColor = color
        tv.defaultParagraphStyle = a.textAttributes[.paragraphStyle] as? NSParagraphStyle
        tv.textStorage?.setAttributes(a.textAttributes, range: NSRange(location: 0, length: tv.string.utf16.count))
        tv.typingAttributes = a.textAttributes
        layoutEditor()
    }

    func commitTextEditor() {
        guard let tv = editor else { return }
        editor = nil
        // Trailing line breaks go: Return is a new line now, and the habit of pressing it before clicking away would leave a taller box.
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(tv.string.reversed().drop(while: { $0.isNewline }).reversed())
        tv.removeFromSuperview()
        window?.makeFirstResponder(self)
        let replacing = editingID
        editingID = nil
        if let replacing, let i = annotations.firstIndex(where: { $0.id == replacing }) {
            if text.isEmpty { annotations.remove(at: i); selectedID = nil } else {
                annotations[i].text = text
                annotations[i].points = [editorAnchor]
                annotations[i].textBoxSize = committedBoxSize(for: text)
            }
            needsDisplay = true
            return
        }
        if !text.isEmpty {
            let a = Annotation(tool: .text, color: color, size: size, points: [editorAnchor], text: text, textBoxSize: committedBoxSize(for: text))
            annotations.append(a)
            selectedID = a.id
        }
    }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if textView.hasMarkedText() { return false }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            editor?.string = ""
            editingID = nil
            commitTextEditor()
            return true
        }
        return false
    }
}
