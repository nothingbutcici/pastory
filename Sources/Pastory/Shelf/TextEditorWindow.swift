import AppKit

/// A sheet of paper on the desk: read the whole text, change it, 保存 writes it back to the same card and copies it.
@MainActor
final class TextEditorWindow: NSObject, NSWindowDelegate {
    private static var open: [String: TextEditorWindow] = [:]
    private let item: ClipItem
    private let window: NSWindow
    private let textView = NSTextView()
    private let titleField = TitleField()
    private let count = NSTextField(labelWithString: "")

    static func open(_ item: ClipItem) {
        if let w = open[item.id] { w.window.makeKeyAndOrderFront(nil); return }
        let e = TextEditorWindow(item: item)
        open[item.id] = e
        ShelfPanelController.shared.hide()
        NSApp.activate(ignoringOtherApps: true)
        e.window.makeKeyAndOrderFront(nil)
    }

    /// Self-test only: the content view, laid out, without showing the window.
    static func debugView(_ item: ClipItem) -> NSView? {
        let e = TextEditorWindow(item: item)
        open[item.id] = e
        return e.window.contentView
    }

    private init(item: ClipItem) {
        self.item = item
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 460),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "编辑文字".l
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.brown
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 420, height: 300)
        window.delegate = self
        window.center()

        let content = GridBackdropView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        scroll.borderType = .noBorder
        Theme.paperSheet(scroll, radius: 4)
        textView.string = ClipStore.shared.text(of: item) ?? ""
        textView.isRichText = false
        textView.font = Theme.serif(size: 16)
        textView.textColor = Theme.ink
        textView.insertionPointColor = Theme.ink
        textView.backgroundColor = Theme.paper
        textView.textContainerInset = CGSize(width: 18, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        scroll.documentView = textView

        titleField.string = item.title ?? ""
        count.font = Theme.serif(size: 13)
        count.textColor = Theme.onBrownMuted
        let cancel = Theme.paperButton("取消".l, onGround: true, target: self, action: #selector(cancelTapped))
        let save = Theme.paperButton("保存并复制".l, primary: true, target: self, action: #selector(saveTapped))
        save.toolTip = "⌘⏎"
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = [.command]
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 8
        let titleWrap = PaperSheetView()
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleWrap.addSubview(titleField)
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: titleWrap.leadingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: titleWrap.trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: titleWrap.centerYAnchor),
            titleField.heightAnchor.constraint(equalToConstant: TitleField.height),
            titleWrap.heightAnchor.constraint(equalToConstant: 52),
        ])
        for v in [titleWrap, scroll, count, buttons] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            titleWrap.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            titleWrap.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleWrap.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: titleWrap.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            count.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            count.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        window.contentView = content
        updateCount()
    }

    private func updateCount() { count.stringValue = String(format: "%d 字".l, textView.string.count) }

    @objc private func cancelTapped() { window.close() }
    @objc private func saveTapped() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        ClipStore.shared.updateText(item.id, text: text)
        ClipStore.shared.setTitle(titleField.string, for: item.id)
        if let updated = ClipStore.shared.items.first(where: { $0.id == item.id }) { ClipStore.shared.copyToPasteboard(updated) }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open[item.id] = nil
        ShelfPanelController.shared.show()
    }
}

extension TextEditorWindow: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) { updateCount() }
}

/// A small sheet of paper (grain + hairline edge + shadow) to lay controls on.
final class PaperSheetView: NSView {
    init() { super.init(frame: .zero); Theme.paperSheet(self, radius: 4) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { Theme.drawPaper(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)) }
}

/// One-line handwritten title box. An NSTextField cannot be told how tall a line is, so with Caveat's metrics the
/// caret towered over the glyphs; here the paragraph style fixes the line height and the placeholder is drawn with
/// the very same attributes, so caret, typed text and placeholder share one baseline.
final class TitleField: NSTextView {
    static let lineHeight: CGFloat = 30
    static let height: CGFloat = lineHeight + 6
    private static var attributes: [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight; ps.maximumLineHeight = lineHeight
        ps.lineBreakMode = .byTruncatingTail
        return [.font: Theme.script(size: 22), .foregroundColor: Theme.ink, .paragraphStyle: ps]
    }

    convenience init() {
        self.init(frame: .zero)
        isRichText = false
        isFieldEditor = true                       // ⏎ / ⇥ end editing instead of inserting
        drawsBackground = false
        focusRingType = .none
        insertionPointColor = Theme.ink
        textContainerInset = CGSize(width: 0, height: 3)
        textContainer?.lineFragmentPadding = 0
        textContainer?.maximumNumberOfLines = 1
        typingAttributes = Self.attributes
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
    }

    override var string: String {
        get { super.string }
        set { super.string = newValue; textStorage?.setAttributes(Self.attributes, range: NSRange(location: 0, length: (newValue as NSString).length)); needsDisplay = true }
    }

    override func didChangeText() {
        // One line only: newlines pasted in become spaces; attributes never drift from the handwritten style.
        if string.contains("\n") { string = string.replacingOccurrences(of: "\n", with: " ") }
        textStorage?.setAttributes(Self.attributes, range: NSRange(location: 0, length: (string as NSString).length))
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attrs = Self.attributes
        attrs[.foregroundColor] = Theme.inkMuted.withAlphaComponent(0.7)
        let origin = textContainerOrigin
        ("+ 加个标题".l as NSString).draw(in: CGRect(x: origin.x, y: origin.y, width: bounds.width, height: Self.lineHeight), withAttributes: attrs)
        // Offscreen renders cannot show a blinking caret; PASTORY_DEBUG_CARET paints where it would be, at its real height.
        if ProcessInfo.processInfo.environment["PASTORY_DEBUG_CARET"] != nil, let lm = layoutManager {
            let r = lm.extraLineFragmentRect
            Theme.paperBlueDeep.setFill()
            CGRect(x: origin.x + r.minX, y: origin.y + r.minY, width: 2, height: r.height == 0 ? Self.lineHeight : r.height).fill()
        }
    }
}
