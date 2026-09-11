import AppKit

/// Plain, dark, ours: read the whole text, change it, 保存 writes it back to the same card and copies it.
@MainActor
final class TextEditorWindow: NSObject, NSWindowDelegate {
    private static var open: [String: TextEditorWindow] = [:]
    private let item: ClipItem
    private let window: NSWindow
    private let textView = NSTextView()
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
        window.title = "编辑文字"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.shelfBG
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 420, height: 300)
        window.delegate = self
        window.center()

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.shelfBG.cgColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.shelfCard
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        textView.string = ClipStore.shared.text(of: item) ?? ""
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = Theme.shelfInk
        textView.insertionPointColor = Theme.purple
        textView.backgroundColor = Theme.shelfCard
        textView.textContainerInset = CGSize(width: 14, height: 14)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        scroll.documentView = textView

        count.font = NSFont.systemFont(ofSize: 12)
        count.textColor = Theme.shelfMuted
        let cancel = pill("取消", fill: Theme.shelfCard, ink: Theme.shelfInk, action: #selector(cancelTapped))
        let save = pill("保存并复制  ⌘⏎", fill: Theme.purple, ink: Theme.onPurple, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = [.command]
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 8
        for v in [scroll, count, buttons] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
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

    private func pill(_ title: String, fill: NSColor, ink: NSColor, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: ink, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        b.wantsLayer = true
        b.layer?.backgroundColor = fill.cgColor
        b.layer?.cornerRadius = 9
        b.layer?.borderWidth = fill == Theme.shelfCard ? 1 : 0
        b.layer?.borderColor = Theme.shelfBorder.cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        return b
    }

    private func updateCount() { count.stringValue = "\(textView.string.count) 字" }

    @objc private func cancelTapped() { window.close() }
    @objc private func saveTapped() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        ClipStore.shared.updateText(item.id, text: text)
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
