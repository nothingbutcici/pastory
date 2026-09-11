import AppKit

/// Dark pill under the selection: tools · colors · sizes · OCR · undo · cancel · done.
final class AnnotateToolbar: NSView {
    private unowned let canvas: AnnotateView
    private var toolButtons: [AnnotateTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var sizeButtons: [StrokeSize: NSButton] = [:]
    private var undoButton: NSButton!

    init(canvas: AnnotateView) {
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        build()
        canvas.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width + 16, height: 40) }
    private let stack = NSStackView()

    private func build() {
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for t in AnnotateTool.allCases {
            let b = iconButton(t.symbol, tip: t.tip, action: #selector(pickTool(_:)))
            b.tag = AnnotateTool.allCases.firstIndex(of: t)!
            toolButtons[t] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(divider())
        for (i, c) in AnnotatePalette.colors.enumerated() {
            let b = NSButton(frame: .zero)
            b.isBordered = false
            b.title = ""
            b.wantsLayer = true
            b.layer?.backgroundColor = c.cgColor
            b.layer?.cornerRadius = 8
            b.layer?.borderWidth = 2
            b.tag = i
            b.target = self
            b.action = #selector(pickColor(_:))
            b.widthAnchor.constraint(equalToConstant: 16).isActive = true
            b.heightAnchor.constraint(equalToConstant: 16).isActive = true
            colorButtons.append(b)
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(b)
            b.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrap.widthAnchor.constraint(equalToConstant: 22), wrap.heightAnchor.constraint(equalToConstant: 28),
                b.centerXAnchor.constraint(equalTo: wrap.centerXAnchor), b.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            ])
            stack.addArrangedSubview(wrap)
        }
        stack.addArrangedSubview(divider())
        for s in StrokeSize.allCases {
            let b = iconButton(s == .thin ? "circle.fill" : (s == .medium ? "circle.fill" : "circle.fill"),
                               tip: s == .thin ? "细" : (s == .medium ? "中" : "粗"), action: #selector(pickSize(_:)))
            let pt: CGFloat = s == .thin ? 6 : (s == .medium ? 10 : 15)
            b.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pt, weight: .regular))
            b.tag = s.rawValue
            sizeButtons[s] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(divider())
        let ocr = textButton("识别文字", action: #selector(ocr))
        stack.addArrangedSubview(ocr)
        undoButton = iconButton("arrow.uturn.backward", tip: "撤销 ⌘Z", action: #selector(undo))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(divider())
        let cancel = iconButton("xmark", tip: "取消 ⎋", action: #selector(cancel))
        cancel.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.85)
        stack.addArrangedSubview(cancel)
        let done = iconButton("checkmark", tip: "完成 ⏎ · 复制到剪贴板", action: #selector(done))
        done.contentTintColor = NSColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        stack.addArrangedSubview(done)
    }

    private func iconButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.toolTip = tip
        b.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.85)
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func textButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        b.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.85)
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.9), .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.1).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        b.widthAnchor.constraint(equalToConstant: 66).isActive = true
        return b
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    private func refresh() {
        let accent = NSColor(srgbRed: 0.56, green: 0.42, blue: 1.0, alpha: 1)
        for (t, b) in toolButtons {
            let on = t == canvas.tool
            b.layer?.backgroundColor = on ? NSColor(calibratedWhite: 1, alpha: 0.18).cgColor : nil
            b.contentTintColor = on ? accent : NSColor(calibratedWhite: 1, alpha: 0.85)
        }
        for (i, b) in colorButtons.enumerated() {
            let on = AnnotatePalette.colors[i] == canvas.color
            b.layer?.borderColor = on ? NSColor.white.cgColor : NSColor.clear.cgColor
        }
        for (s, b) in sizeButtons {
            let on = s == canvas.size
            b.contentTintColor = on ? accent : NSColor(calibratedWhite: 1, alpha: 0.7)
        }
        undoButton.isEnabled = canvas.canUndo
        undoButton.alphaValue = canvas.canUndo ? 1 : 0.35
    }

    @objc private func pickTool(_ sender: NSButton) { canvas.tool = AnnotateTool.allCases[sender.tag] }
    @objc private func pickColor(_ sender: NSButton) { canvas.color = AnnotatePalette.colors[sender.tag] }
    @objc private func pickSize(_ sender: NSButton) { canvas.size = StrokeSize(rawValue: sender.tag) ?? .medium }
    @objc private func ocr() { canvas.requestOCR() }
    @objc private func undo() { canvas.undo() }
    @objc private func cancel() { canvas.cancel() }
    @objc private func done() { canvas.finish() }

    // Clicks on the pill itself must not fall through to the mask.
    override func mouseDown(with event: NSEvent) {}
}
