import AppKit

/// TextKit layout shared by annotation measurement and export, matching the live text editor.
final class AnnotationTextLayout {
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer
    private let font: NSFont

    init(text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) {
        storage = NSTextStorage(string: text, attributes: attributes)
        font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 18)
        container = NSTextContainer(containerSize: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
    }

    var height: CGFloat {
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentTextContainer === container ? manager.extraLineFragmentRect.maxY : 0
        return ceil(max(used.maxY, extra, manager.defaultLineHeight(for: font)))
    }

    func draw(at point: CGPoint) {
        let range = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: range, at: point)
        manager.drawGlyphs(forGlyphRange: range, at: point)
    }
}
