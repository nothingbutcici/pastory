import AppKit

/// A sheet of paper on the desk: read the whole text, change it, 保存 writes it back to the same card and copies it.
@MainActor
final class TextEditorWindow: NSObject, NSWindowDelegate {
    private static var open: [String: TextEditorWindow] = [:]
    private let item: ClipItem
    private let window: NSWindow
    private let textView = NSTextView()
    private let titleField = NSTextField()
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

        titleField.stringValue = item.title ?? ""
        titleField.placeholderAttributedString = NSAttributedString(string: "+ 加个标题".l, attributes: [
            .foregroundColor: Theme.inkMuted.withAlphaComponent(0.7), .font: Theme.script(size: 22)])      // same font as the field, so caret and placeholder line up
        titleField.font = Theme.script(size: 22)
        titleField.textColor = Theme.ink
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.cell?.focusRingType = .none
        titleField.cell?.usesSingleLineMode = true
        titleField.cell?.isScrollable = true
        titleField.cell?.wraps = false
        (titleField.cell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
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
            titleField.heightAnchor.constraint(equalToConstant: (Theme.script(size: 22).ascender - Theme.script(size: 22).descender + 4).rounded(.up)),
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
        ClipStore.shared.setTitle(titleField.stringValue, for: item.id)
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
