import AppKit
import Carbon.HIToolbox

/// Exercises actual editor events and resize geometry without touching the clipboard or user's store.
enum AnnotationTextSelfTest {
    @MainActor
    static func run(out: String, snapshot: (NSView, String) -> Bool) -> Bool {
        var ok = true
        func check(_ label: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(label)")
            ok = condition && ok
        }
        let sample = L.isEnglish
            ? "Resize this text box to wrap words automatically.\nKeep the font size, and all the text visible. 👋🏽"
            : "拖动文字框的边或四角，文字会随宽度自动换行。\n字号保持不变，完整内容不会被截掉。👋🏽"
        let original = Annotation(tool: .text, color: Theme.purple, size: .m, points: [CGPoint(x: 80, y: 80)], text: sample,
                                  textBoxSize: CGSize(width: 420, height: 220))
        var narrow = original
        narrow.setHandle(5, to: CGPoint(x: 280, y: original.bounds.midY))
        check("narrowing wraps text without changing its content or font", narrow.textLayout.height > original.textLayout.height && narrow.size == original.size && narrow.text == original.text)
        check("text has corner and edge handles", narrow.handles.count == 8)
        check("right edge preserves top-left anchor", narrow.bounds.origin == original.bounds.origin && narrow.bounds.width == 200)
        narrow.setHandle(7, to: CGPoint(x: narrow.bounds.midX, y: 600))
        check("height can be extended independently", narrow.bounds.height == 520 && narrow.bounds.width == 200)
        narrow.setHandle(7, to: CGPoint(x: narrow.bounds.midX, y: 81))
        check("height cannot clip wrapped text", narrow.bounds.height == narrow.textLayout.height)
        for handle in 0..<8 {
            var a = original
            let p = a.handles[handle]
            a.setHandle(handle, to: CGPoint(x: p.x + 24, y: p.y + 12))
            let r = a.bounds, before = original.bounds
            let horizontal = [0, 2, 4].contains(handle) ? r.maxX == before.maxX : r.minX == before.minX
            let vertical = [0, 1, 6].contains(handle) ? r.maxY == before.maxY : r.minY == before.minY
            check("handle \(handle) preserves opposite edges", horizontal && vertical)
        }
        var crossed = original
        crossed.setHandle(0, to: CGPoint(x: 900, y: 900))
        check("dragging past the opposite corner keeps a usable box", crossed.bounds.width == 32 && crossed.bounds.height >= crossed.textLayout.height)
        let empty = AnnotationTextLayout(text: "", attributes: original.textAttributes, width: 200)
        check("empty text still has a line for the caret", empty.height > 0)
        let trailing = AnnotationTextLayout(text: "Hello\n", attributes: original.textAttributes, width: 200)
        let single = AnnotationTextLayout(text: "Hello", attributes: original.textAttributes, width: 200)
        check("explicit trailing newline has room for the caret", trailing.height > single.height)

        guard let ctx = CGContext(data: nil, width: 1440, height: 1040, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(Theme.paper.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 1440, height: 1040))
        guard let image = ctx.makeImage() else { return false }
        let canvas = AnnotateView(frame: CGRect(x: 0, y: 0, width: 720, height: 520), image: image)
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func click(_ point: CGPoint) {
            canvas.mouseDown(with: mouse(.leftMouseDown, at: point))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: point))
        }
        func activeEditor() -> NSTextView? { canvas.subviews.compactMap { $0 as? NSTextView }.first }
        canvas.tool = .text
        canvas.size = .m
        click(CGPoint(x: 80, y: 80))
        guard let editor = activeEditor() else { check("opens a multiline editor", false); return false }
        editor.insertText(sample, replacementRange: editor.selectedRange())
        let expected = Annotation(tool: .text, color: canvas.color, size: canvas.size, points: [CGPoint(x: 80, y: 80)], text: sample,
                                  textBoxSize: CGSize(width: 320, height: 0))
        check("typing grows the editor to fit the wrapped content", editor.frame == expected.bounds)
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        check("live editor and export have the same line layout", ceil(editor.layoutManager!.usedRect(for: editor.textContainer!).maxY) == expected.textLayout.height)
        let url = URL(fileURLWithPath: out).deletingPathExtension()
        check("editing snapshot", snapshot(canvas, url.appendingPathExtension("editing.png").path))
        let edge = AnnotationRenderer.selectionHandles(expected)[5]
        check("editor lets the canvas receive resize handles", canvas.hitTest(canvas.convert(edge, to: canvas.superview)) === canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: edge))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 288, y: edge.y)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 268, y: edge.y)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 268, y: edge.y)))
        guard let resized = canvas.selected else { check("resize commits the edited text", false); return false }
        check("dragging an active editor commits and resizes it", activeEditor() == nil && resized.text == sample && resized.bounds.width == 180)
        check("successive drag events keep the original anchor", resized.bounds.origin == expected.bounds.origin)
        check("selected text snapshot", snapshot(canvas, out))
        click(CGPoint(x: 100, y: 100))
        guard let reopened = activeEditor() else { check("reopens resized text", false); return false }
        check("reopening preserves box dimensions and Unicode caret position", reopened.frame == resized.bounds && reopened.selectedRange().location == sample.utf16.count)
        // IME confirmation belongs to the input method, not to the canvas's Return shortcut.
        reopened.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0), replacementRange: reopened.selectedRange())
        check("Return does not commit an IME candidate", !canvas.textView(reopened, doCommandBy: #selector(NSResponder.insertNewline(_:))) && activeEditor() != nil)
        reopened.unmarkText()
        _ = canvas.textView(reopened, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check("Escape restores existing text and box geometry", canvas.selected?.text == sample && canvas.selected?.bounds == resized.bounds)
        click(CGPoint(x: 100, y: 100))
        guard let finalEditor = activeEditor() else { return false }
        finalEditor.insertText(" ✓", replacementRange: finalEditor.selectedRange())
        func key(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return))!
        }
        finalEditor.keyDown(with: key(.command))
        check("⌘Return commits multiline editing", activeEditor() == nil)
        check("editing preserves the resized width", canvas.selected?.bounds.width == 180 && canvas.selected?.text == sample + " ✓")
        click(CGPoint(x: 100, y: 100))
        guard let lineEditor = activeEditor() else { return false }
        lineEditor.keyDown(with: key([]))
        check("Return inserts a line break and keeps editing", activeEditor() != nil && lineEditor.string == sample + " ✓\n")
        canvas.commitTextEditor()
        let flat = canvas.renderedImage()
        check("export keeps the original image resolution", flat.width == image.width && flat.height == image.height)
        do { try Screenshotter.pngData(flat)?.write(to: url.appendingPathExtension("flat.png")) } catch { check("writes flattened output", false) }
        canvas.debugSet([original], select: 0)
        let corner = AnnotationRenderer.selectionHandles(original)[1]
        canvas.mouseDown(with: mouse(.leftMouseDown, at: corner))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: corner.x + 20, y: corner.y)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: corner.x + 20, y: corner.y)))
        check("top-right grip resizes without hitting delete", canvas.annotations.count == 1 && canvas.selected?.bounds.width == 440)
        return ok
    }
}
