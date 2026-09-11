import AppKit

/// Floating result of "识别文字": editable text, copy button.
@MainActor
final class OCRPanelController: NSObject, NSWindowDelegate {
    static let shared = OCRPanelController()
    private var panel: NSPanel?
    private var textView: NSTextView?
    private var status: NSTextField?
    private var onCopy: ((String) -> Void)?
    private var task: Task<Void, Never>?

    /// Text as currently shown (edited or not); nil when the panel is not up.
    var currentText: String? {
        guard let tv = textView, panel?.isVisible == true else { return nil }
        let s = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    func show(near anchor: CGRect, image: CGImage, onCopy: @escaping (String) -> Void) {
        self.onCopy = onCopy
        let p = panel ?? makePanel()
        panel = p
        textView?.string = ""
        status?.stringValue = "识别中…"
        place(p, near: anchor)
        p.orderFrontRegardless()
        p.makeKey()
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            let result = (try? OCR.recognize(image)) ?? ""
            guard !Task.isCancelled else { return }
            await MainActor.run { OCRPanelController.shared.showResult(result) }
        }
    }

    private func showResult(_ result: String) {
        textView?.string = result
        status?.stringValue = result.isEmpty ? "没有识别到文字" : "\(result.count) 字 · 可直接编辑"
        if !result.isEmpty { panel?.makeFirstResponder(textView) }
    }

    func close() {
        task?.cancel()
        task = nil
        panel?.orderOut(nil)
        onCopy = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 300),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .resizable],
                        backing: .buffered, defer: false)
        p.title = "识别文字"
        p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.minSize = CGSize(width: 280, height: 180)

        let content = NSView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = CGSize(width: 8, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        textView = tv

        let st = NSTextField(labelWithString: "")
        st.font = NSFont.systemFont(ofSize: 11)
        st.textColor = .secondaryLabelColor
        status = st
        let copy = NSButton(title: "复制文字", target: self, action: #selector(copyTapped))
        copy.keyEquivalent = "\r"
        copy.bezelStyle = .rounded
        let cancel = NSButton(title: "关闭", target: self, action: #selector(closeTapped))
        cancel.bezelStyle = .rounded

        for v in [scroll, st, copy, cancel] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -10),
            st.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            st.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            cancel.trailingAnchor.constraint(equalTo: copy.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
        ])
        p.contentView = content
        return p
    }

    private func place(_ p: NSPanel, near anchor: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { p.center(); return }
        let size = p.frame.size
        var origin = CGPoint(x: anchor.maxX + 12, y: anchor.maxY - size.height)
        if origin.x + size.width > vf.maxX { origin.x = anchor.minX - size.width - 12 }
        if origin.x < vf.minX { origin.x = min(anchor.minX, vf.maxX - size.width) }
        origin.y = min(max(vf.minY, origin.y), vf.maxY - size.height)
        p.setFrameOrigin(origin)
    }

    @objc private func copyTapped() {
        guard let text = currentText else { NSSound.beep(); return }
        onCopy?(text)
    }
    @objc private func closeTapped() { close() }
    func windowWillClose(_ notification: Notification) { task?.cancel() }
}
