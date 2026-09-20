import AppKit
import Carbon.HIToolbox

/// A multiline editor whose zero insets match AnnotationTextLayout exactly.
final class AnnotationTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let isReturn = [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode))
        if isReturn, event.modifierFlags.contains(.shift), !hasMarkedText() {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("输入文字".l as NSString).draw(at: .zero, withAttributes: [
                .font: font ?? HandFont.font(size: 18),
                .foregroundColor: (textColor ?? .labelColor).withAlphaComponent(0.35)
            ])
        }
    }
}
