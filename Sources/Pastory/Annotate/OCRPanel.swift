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
    /// Which capture asked for this text; a later capture must not inherit it.
    private(set) var token: UUID?
    private static let abovePicker = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

    override init() {
        super.init()
        // Labels are baked in at build time; a language switch throws the panel away so the next one is rebuilt.
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.close()
                self.panel = nil; self.textView = nil; self.status = nil
            }
        }
    }

    /// A new capture is starting: the panel must not cover the picker — the frozen backdrop shows it instead,
    /// so it can be screenshotted like any other window.
    func sinkBelowPicker() { panel?.level = .floating }

    /// Text as currently shown (edited or not); nil when the panel is not up.
    var currentText: String? {
        guard let tv = textView, panel?.isVisible == true else { return nil }
        let s = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    func show(near anchor: CGRect, image: CGImage, token: UUID? = nil, onCopy: @escaping (String) -> Void) {
        self.onCopy = onCopy
        self.token = token
        let p = panel ?? makePanel()
        panel = p
        textView?.string = ""
        status?.stringValue = "识别中…".l
        p.level = Self.abovePicker
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
        status?.stringValue = result.isEmpty ? "没有识别到文字".l : String(format: "%d 字 · 可直接编辑".l, result.count)
        if !result.isEmpty { panel?.makeFirstResponder(textView) }
    }

    /// Self-test only: the laid-out panel content with a sample result.
    func debugView(sample: String) -> NSView? {
        let p = panel ?? makePanel()
        panel = p
        showResult(sample)
        return p.contentView
    }

    func close() {
        task?.cancel()
        task = nil
        panel?.orderOut(nil)
        onCopy = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 350),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.title = "识别文字".l
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.appearance = NSAppearance(named: .darkAqua)
        p.backgroundColor = Theme.brown
        p.level = Self.abovePicker
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.minSize = CGSize(width: 280, height: 180)

        let content = GridBackdropView()
        let heading = NSTextField(labelWithString: "识别文字".l)
        heading.font = Theme.script(size: 24)
        heading.textColor = Theme.onBrown
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        Theme.paperSheet(scroll, radius: 4)
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = Theme.serif(size: 15)
        tv.textColor = Theme.ink
        tv.insertionPointColor = Theme.ink
        tv.backgroundColor = Theme.paper
        tv.textContainerInset = CGSize(width: 14, height: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        textView = tv

        let st = NSTextField(labelWithString: "")
        st.font = Theme.serif(size: 13)
        st.textColor = Theme.onBrownMuted
        status = st
        let copy = Theme.paperButton("复制文字".l, primary: true, target: self, action: #selector(copyTapped))
        copy.keyEquivalent = "\r"
        let cancel = Theme.paperButton("关闭".l, onGround: true, target: self, action: #selector(closeTapped))

        for v in [heading, scroll, st, copy, cancel] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -12),
            st.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            st.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
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
