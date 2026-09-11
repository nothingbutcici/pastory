import AppKit

/// White island under the selection, Excalidraw-style:
/// select · rect · ellipse · arrow · line · pen · text · mosaic │ colors │ S M L · dashed │ 识别文字 · undo │ ✕ ✓
final class AnnotateToolbar: NSView {
    private unowned let canvas: AnnotateView
    private var toolButtons: [AnnotateTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var sizeButtons: [StrokeSize: NSButton] = [:]
    private var dashButton: NSButton!
    private var undoButton: NSButton!
    private let stack = NSStackView()

    private static let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.46, alpha: 1)
    private static let selectedBG = NSColor(srgbRed: 0.88, green: 0.86, blue: 1.0, alpha: 1)
    private static let selectedInk = NSColor(srgbRed: 0.28, green: 0.27, blue: 0.70, alpha: 1)

    init(canvas: AnnotateView) {
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.08).cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        shadow?.shadowBlurRadius = 10
        shadow?.shadowOffset = CGSize(width: 0, height: -2)
        build()
        canvas.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width + 12, height: 44) }

    private func build() {
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for t in AnnotateTool.allCases {
            let b = iconButton(ToolIcons.image(for: t), tip: t.tip, action: #selector(pickTool(_:)))
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
            b.layer?.borderWidth = c == .white ? 1 : 0
            b.layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.18).cgColor
            b.tag = i
            b.target = self
            b.action = #selector(pickColor(_:))
            b.toolTip = "颜色"
            let wrap = NSView()
            wrap.wantsLayer = true
            wrap.layer?.cornerRadius = 11
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(b)
            b.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrap.widthAnchor.constraint(equalToConstant: 22), wrap.heightAnchor.constraint(equalToConstant: 22),
                b.widthAnchor.constraint(equalToConstant: 16), b.heightAnchor.constraint(equalToConstant: 16),
                b.centerXAnchor.constraint(equalTo: wrap.centerXAnchor), b.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            ])
            colorButtons.append(b)
            stack.addArrangedSubview(wrap)
            stack.setCustomSpacing(4, after: wrap)
        }
        stack.addArrangedSubview(divider())
        for s in StrokeSize.allCases {
            let b = NSButton(title: s.label, target: self, action: #selector(pickSize(_:)))
            b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            b.tag = s.rawValue
            b.toolTip = "大小：线宽和字号"
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            sizeButtons[s] = b
            stack.addArrangedSubview(b)
        }
        dashButton = iconButton(ToolIcons.dashed(), tip: "虚线", action: #selector(toggleDash))
        stack.addArrangedSubview(dashButton)
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(textButton("识别文字", action: #selector(ocr)))
        undoButton = iconButton(NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!, tip: "撤销 ⌘Z", action: #selector(undo))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(divider())
        let cancel = iconButton(NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)!, tip: "取消 ⎋", action: #selector(cancel))
        stack.addArrangedSubview(cancel)
        let done = iconButton(NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 13, weight: .bold))!,
                              tip: "完成 ⏎ · 复制到剪贴板", action: #selector(done))
        done.contentTintColor = NSColor(srgbRed: 0.16, green: 0.65, blue: 0.27, alpha: 1)
        stack.addArrangedSubview(done)
    }

    private func iconButton(_ image: NSImage, tip: String, action: Selector) -> NSButton {
        let b = NSButton(image: image, target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.toolTip = tip
        b.contentTintColor = Self.ink
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    private func textButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: Self.ink, .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.06).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        b.widthAnchor.constraint(equalToConstant: 68).isActive = true
        return b
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.1).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }

    private func refresh() {
        for (t, b) in toolButtons {
            let on = t == canvas.tool
            b.layer?.backgroundColor = on ? Self.selectedBG.cgColor : nil
            b.contentTintColor = on ? Self.selectedInk : Self.ink
        }
        for (i, b) in colorButtons.enumerated() {
            let on = AnnotatePalette.colors[i] == canvas.color
            b.superview?.layer?.borderWidth = on ? 1.5 : 0
            b.superview?.layer?.borderColor = Self.selectedInk.cgColor
        }
        for (s, b) in sizeButtons {
            let on = s == canvas.size
            b.layer?.backgroundColor = on ? Self.selectedBG.cgColor : nil
            b.attributedTitle = NSAttributedString(string: s.label, attributes: [
                .foregroundColor: on ? Self.selectedInk : Self.muted, .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)])
        }
        dashButton.layer?.backgroundColor = canvas.dashed ? Self.selectedBG.cgColor : nil
        dashButton.contentTintColor = canvas.dashed ? Self.selectedInk : Self.ink
        undoButton.isEnabled = canvas.canUndo
        undoButton.alphaValue = canvas.canUndo ? 1 : 0.3
    }

    @objc private func pickTool(_ sender: NSButton) { canvas.tool = AnnotateTool.allCases[sender.tag] }
    @objc private func pickColor(_ sender: NSButton) { canvas.color = AnnotatePalette.colors[sender.tag] }
    @objc private func pickSize(_ sender: NSButton) { canvas.size = StrokeSize(rawValue: sender.tag) ?? .m }
    @objc private func toggleDash() { canvas.dashed.toggle() }
    @objc private func ocr() { canvas.requestOCR() }
    @objc private func undo() { canvas.undo() }
    @objc private func cancel() { canvas.cancel() }
    @objc private func done() { canvas.finish() }

    // Clicks on the island itself must not fall through to the mask.
    override func mouseDown(with event: NSEvent) {}
}

/// Thin-line 18 pt template icons drawn in code, so every tool shares one visual weight.
enum ToolIcons {
    static func image(for tool: AnnotateTool) -> NSImage {
        switch tool {
        case .select: return make { p in
            p.move(to: CGPoint(x: 4, y: 3)); p.line(to: CGPoint(x: 4, y: 15)); p.line(to: CGPoint(x: 7.2, y: 12.2))
            p.line(to: CGPoint(x: 9.5, y: 16.5)); p.line(to: CGPoint(x: 11.5, y: 15.5)); p.line(to: CGPoint(x: 9.3, y: 11.3))
            p.line(to: CGPoint(x: 13.5, y: 11)); p.close()
        }
        case .rect: return make { p in p.appendRoundedRect(CGRect(x: 2.5, y: 4, width: 13, height: 10), xRadius: 2.5, yRadius: 2.5) }
        case .ellipse: return make { p in p.appendOval(in: CGRect(x: 2.5, y: 3.5, width: 13, height: 11)) }
        case .arrow: return make { p in
            p.move(to: CGPoint(x: 3, y: 15)); p.line(to: CGPoint(x: 15, y: 3))
            p.move(to: CGPoint(x: 8.5, y: 3)); p.line(to: CGPoint(x: 15, y: 3)); p.line(to: CGPoint(x: 15, y: 9.5))
        }
        case .line: return make { p in p.move(to: CGPoint(x: 3, y: 15)); p.line(to: CGPoint(x: 15, y: 3)) }
        case .pen: return make { p in
            p.move(to: CGPoint(x: 2.5, y: 12))
            p.curve(to: CGPoint(x: 8, y: 9), controlPoint1: CGPoint(x: 4, y: 5), controlPoint2: CGPoint(x: 6, y: 5))
            p.curve(to: CGPoint(x: 13, y: 8), controlPoint1: CGPoint(x: 10, y: 13), controlPoint2: CGPoint(x: 11, y: 13))
            p.curve(to: CGPoint(x: 15.5, y: 6), controlPoint1: CGPoint(x: 14.5, y: 4), controlPoint2: CGPoint(x: 15, y: 4))
        }
        case .text: return make(fill: true) { p in
            let s = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.black])
            let sz = s.size()
            s.draw(at: CGPoint(x: 9 - sz.width / 2, y: 9 - sz.height / 2))
        }
        case .mosaic: return make(fill: true) { p in
            for r in 0..<3 { for c in 0..<3 where (r + c) % 2 == 0 {
                p.appendRect(CGRect(x: 3 + CGFloat(c) * 4.2, y: 3 + CGFloat(r) * 4.2, width: 3.8, height: 3.8))
            } }
            p.fill()
            NSColor.black.withAlphaComponent(0.35).setFill()
            let q = NSBezierPath()
            for r in 0..<3 { for c in 0..<3 where (r + c) % 2 == 1 {
                q.appendRect(CGRect(x: 3 + CGFloat(c) * 4.2, y: 3 + CGFloat(r) * 4.2, width: 3.8, height: 3.8))
            } }
            q.fill()
        }
        }
    }

    static func dashed() -> NSImage {
        make { p in
            p.setLineDash([3, 2.5], count: 2, phase: 0)
            p.move(to: CGPoint(x: 2.5, y: 9)); p.line(to: CGPoint(x: 15.5, y: 9))
        }
    }

    private static func make(fill: Bool = false, _ draw: @escaping (NSBezierPath) -> Void) -> NSImage {
        let img = NSImage(size: CGSize(width: 18, height: 18), flipped: true) { _ in
            let p = NSBezierPath()
            p.lineWidth = 1.6
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw(p)
            if !fill { p.stroke() }
            return true
        }
        img.isTemplate = true
        return img
    }
}
