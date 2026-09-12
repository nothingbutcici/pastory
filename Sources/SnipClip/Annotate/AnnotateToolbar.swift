import AppKit

/// Two-layer toolbar, Feishu-style, dark with a lime active state.
/// Main bar:  ▢ ○ ╱ ↗ ✎ A ▦ │ 识别文字 │ ↶ │ ✕ · [✓ 复制]
/// Sub bar:   appears under the active tool (or the selected element's tool) with sizes · colors.
final class AnnotateToolbar: NSView {
    private unowned let canvas: AnnotateView
    private var toolButtons: [AnnotateTool: NSButton] = [:]
    private var undoButton: NSButton!
    private let stack = NSStackView()
    let subBar: SubBar

    static let ink = Theme.onBrown
    static let selectedBG = Theme.paperBlue
    static let selectedInk = Theme.ink

    private let doneTitle: String

    init(canvas: AnnotateView, doneTitle: String = "复制") {
        self.canvas = canvas
        self.doneTitle = doneTitle
        subBar = SubBar(canvas: canvas)
        super.init(frame: .zero)
        Theme.paperSheet(self)
        build()
        canvas.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width + 16, height: 56) }
    override func draw(_ dirtyRect: NSRect) { Theme.drawDesk(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.paperRadius, yRadius: Theme.paperRadius)) }

    private func build() {
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for t in AnnotateTool.allCases {
            let b = Self.iconButton(ToolIcons.image(for: t), tip: t.tip, target: self, action: #selector(pickTool(_:)))
            b.tag = AnnotateTool.allCases.firstIndex(of: t)!
            toolButtons[t] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(Self.divider())
        // 识别文字: icon + label
        let ocrBtn = NSButton(title: " 识别文字", image: NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!, target: self, action: #selector(ocr))
        ocrBtn.isBordered = false
        ocrBtn.imagePosition = .imageLeading
        ocrBtn.imageHugsTitle = true
        ocrBtn.contentTintColor = Self.ink
        ocrBtn.attributedTitle = NSAttributedString(string: " 识别文字", attributes: [
            .foregroundColor: Self.ink, .font: Theme.serif(size: 15)])
        ocrBtn.wantsLayer = true
        ocrBtn.layer?.cornerRadius = 9
        ocrBtn.translatesAutoresizingMaskIntoConstraints = false
        ocrBtn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        ocrBtn.widthAnchor.constraint(equalToConstant: 112).isActive = true
        stack.addArrangedSubview(ocrBtn)
        stack.addArrangedSubview(Self.divider())
        // Function group: 撤销 · 取消 · 完成 — plain ink glyphs; 完成 in the deep blue.
        undoButton = Self.iconButton(NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))!, tip: "撤销 ⌘Z", target: self, action: #selector(undo))
        undoButton.contentTintColor = Theme.onBrown
        stack.addArrangedSubview(undoButton)
        let cancel = Self.iconButton(NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))!, tip: "取消 ⎋", target: self, action: #selector(cancel))
        cancel.contentTintColor = Theme.onBrown
        stack.addArrangedSubview(cancel)
        let done = Self.iconButton(NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 17, weight: .bold))!,
            tip: doneTitle == "复制" ? "完成 ⏎ · 复制到剪贴板" : "\(doneTitle) ⏎", target: self, action: #selector(done))
        done.contentTintColor = Theme.paperBlue
        stack.addArrangedSubview(done)
    }

    static func iconButton(_ image: NSImage, tip: String, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(image: image, target: target, action: action)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.toolTip = tip
        b.contentTintColor = ink
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 38).isActive = true
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }

    static func divider() -> NSView { Theme.deskDivider(height: 26) }

    /// Called once the overlay has placed the main bar; the sub bar hangs off it.
    func didLayout() { refresh() }

    private func refresh() {
        undoButton.isEnabled = canvas.canUndo
        undoButton.alphaValue = canvas.canUndo ? 1 : 0.35
        let active = canvas.activeKind
        for (t, b) in toolButtons {
            let on = t == active
            b.layer?.backgroundColor = on ? Self.selectedBG.cgColor : nil
            b.contentTintColor = on ? Self.selectedInk : Self.ink
        }
        layoutSubBar(for: active)
    }

    private func layoutSubBar(for kind: AnnotateTool?) {
        guard let kind, let host = superview, let button = toolButtons[kind] else {
            subBar.removeFromSuperview()
            return
        }
        subBar.configure(kind: kind)
        if subBar.superview !== host { host.addSubview(subBar) }
        let size = subBar.fittingSize
        let gap: CGFloat = 8
        let below = frame.minY - gap - size.height >= host.bounds.minY + 4
        let y = below ? frame.minY - gap - size.height : frame.maxY + gap
        let anchorX = button.convert(button.bounds, to: host).midX
        var x = anchorX - size.width / 2
        x = min(max(host.bounds.minX + 4, x), host.bounds.maxX - size.width - 4)
        subBar.pointerX = anchorX - x
        subBar.pointsUp = below
        subBar.frame = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        subBar.needsDisplay = true
    }

    @objc private func pickTool(_ sender: NSButton) {
        let t = AnnotateTool.allCases[sender.tag]
        canvas.tool = canvas.tool == t ? nil : t     // second click deactivates
    }
    @objc private func ocr() { canvas.requestOCR() }
    @objc private func undo() { canvas.undo() }
    @objc private func cancel() { canvas.cancel() }
    @objc private func done() { canvas.finish() }

    // Drag the bar anywhere on its ground; the sub bar follows.
    private var dragOrigin: CGPoint?
    override func mouseDown(with event: NSEvent) { dragOrigin = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let o = dragOrigin, let host = superview else { return }
        let p = convert(event.locationInWindow, from: nil)
        var f = frame.offsetBy(dx: p.x - o.x, dy: p.y - o.y)
        f.origin.x = min(max(host.bounds.minX, f.minX), host.bounds.maxX - f.width)
        f.origin.y = min(max(host.bounds.minY, f.minY), host.bounds.maxY - f.height)
        frame = f
        refresh()
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }
}

/// sizes (dots, or 小/中/大 for text) │ colors as rounded squares with a check (not for mosaic)
final class SubBar: NSView {
    private unowned let canvas: AnnotateView
    private let stack = NSStackView()
    private var sizeButtons: [StrokeSize: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var colorDivider: NSView!
    var pointerX: CGFloat = 40
    var pointsUp = true
    private static let pointerH: CGFloat = 7

    init(canvas: AnnotateView) {
        self.canvas = canvas
        super.init(frame: .zero)
        Theme.paperSheet(self)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for s in StrokeSize.allCases {
            let b = NSButton(title: "", target: self, action: #selector(pickSize(_:)))
            b.isBordered = false
            b.tag = s.rawValue
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            sizeButtons[s] = b
            stack.addArrangedSubview(b)
        }
        colorDivider = AnnotateToolbar.divider()
        stack.addArrangedSubview(colorDivider)
        for (i, c) in AnnotatePalette.colors.enumerated() {
            let b = NSButton(title: "", target: self, action: #selector(pickColor(_:)))
            b.isBordered = false
            b.tag = i
            b.wantsLayer = true
            b.layer?.backgroundColor = c.cgColor
            b.layer?.cornerRadius = 6
            b.layer?.borderWidth = 1
            b.layer?.borderColor = NSColor.clear.cgColor
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            colorButtons.append(b)
            stack.addArrangedSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width + 28, height: 46 + Self.pointerH) }

    func configure(kind: AnnotateTool) {
        let colored = kind != .mosaic
        colorDivider.isHidden = !colored
        colorButtons.forEach { $0.isHidden = !colored }
        let sel = canvas.effectiveSize
        for (s, b) in sizeButtons {
            let on = s == sel
            b.layer?.backgroundColor = on ? Theme.paperBlue.cgColor : nil
            let tint = on ? Theme.ink : Theme.onBrown
            if kind == .text {
                b.image = nil
                b.attributedTitle = NSAttributedString(string: ["小", "中", "大"][s.rawValue - 1], attributes: [
                    .foregroundColor: tint, .font: Theme.serif(size: 13, bold: on)])
            } else {
                b.attributedTitle = NSAttributedString(string: "")
                let d = s.dotDiameter
                b.image = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { _ in
                    tint.setFill()
                    NSBezierPath(ovalIn: CGRect(x: (14 - d) / 2, y: (14 - d) / 2, width: d, height: d)).fill()
                    return true
                }
                b.imagePosition = .imageOnly
            }
        }
        let color = canvas.effectiveColor
        for (i, b) in colorButtons.enumerated() {
            let c = AnnotatePalette.colors[i]
            let on = c == color
            b.image = on ? Self.check(on: c) : nil
            b.imagePosition = .imageOnly
            b.layer?.borderColor = (on ? Theme.paper : NSColor.clear).cgColor
            b.layer?.borderWidth = on ? 2 : 1
        }
    }

    private static func check(on color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 14, height: 14), flipped: false) { _ in
            let p = NSBezierPath()
            p.move(to: CGPoint(x: 3, y: 7)); p.line(to: CGPoint(x: 6, y: 4)); p.line(to: CGPoint(x: 11.5, y: 10.5))
            p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
            (color.isLight ? NSColor.black : NSColor.white).setStroke()
            p.stroke()
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Paper slip with a little pointer toward the main bar.
        let ph = Self.pointerH
        let body = pointsUp ? CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - ph)
                            : CGRect(x: 0, y: ph, width: bounds.width, height: bounds.height - ph)
        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let px = min(max(14, pointerX), bounds.width - 14)
        if pointsUp {
            path.move(to: CGPoint(x: px - 7, y: body.maxY)); path.line(to: CGPoint(x: px, y: body.maxY + ph)); path.line(to: CGPoint(x: px + 7, y: body.maxY))
        } else {
            path.move(to: CGPoint(x: px - 7, y: body.minY)); path.line(to: CGPoint(x: px, y: body.minY - ph)); path.line(to: CGPoint(x: px + 7, y: body.minY))
        }
        path.close()
        Theme.drawDesk(path)
    }

    override func layout() {
        super.layout()
        // Keep the stack centred in the body, not the pointer strip.
        stack.frame.origin.y = (pointsUp ? 0 : Self.pointerH) + ((bounds.height - Self.pointerH) - stack.frame.height) / 2
    }

    @objc private func pickSize(_ sender: NSButton) { canvas.size = StrokeSize(rawValue: sender.tag) ?? .m }
    @objc private func pickColor(_ sender: NSButton) { canvas.color = AnnotatePalette.colors[sender.tag] }
    override func mouseDown(with event: NSEvent) {}
}

/// Thin-line 18 pt template icons drawn in code, so every tool shares one visual weight.
enum ToolIcons {
    static func image(for tool: AnnotateTool) -> NSImage {
        switch tool {
        case .rect: return make { p in p.appendRoundedRect(CGRect(x: 2.5, y: 3, width: 13, height: 12), xRadius: 1.5, yRadius: 1.5) }
        case .ellipse: return make { p in p.appendOval(in: CGRect(x: 2.5, y: 2.5, width: 13, height: 13)) }
        case .arrow: return make { p in
            p.move(to: CGPoint(x: 3, y: 15)); p.line(to: CGPoint(x: 15, y: 3))
            p.move(to: CGPoint(x: 8.5, y: 3)); p.line(to: CGPoint(x: 15, y: 3)); p.line(to: CGPoint(x: 15, y: 9.5))
        }
        case .line: return make { p in p.move(to: CGPoint(x: 3, y: 15)); p.line(to: CGPoint(x: 15, y: 3)) }
        case .pen: return make { p in
            // Pen nib with a squiggle under it.
            p.move(to: CGPoint(x: 11.5, y: 2.5)); p.line(to: CGPoint(x: 15.5, y: 6.5)); p.line(to: CGPoint(x: 7.5, y: 14.5))
            p.line(to: CGPoint(x: 3.5, y: 15.5)); p.line(to: CGPoint(x: 4.5, y: 11.5)); p.close()
            p.move(to: CGPoint(x: 9.5, y: 4.5)); p.line(to: CGPoint(x: 13.5, y: 8.5))
        }
        case .text: return make { p in
            p.move(to: CGPoint(x: 3.5, y: 4)); p.line(to: CGPoint(x: 14.5, y: 4))
            p.move(to: CGPoint(x: 3.5, y: 3)); p.line(to: CGPoint(x: 3.5, y: 6))
            p.move(to: CGPoint(x: 14.5, y: 3)); p.line(to: CGPoint(x: 14.5, y: 6))
            p.move(to: CGPoint(x: 9, y: 4)); p.line(to: CGPoint(x: 9, y: 15.5))
            p.move(to: CGPoint(x: 6.5, y: 15.5)); p.line(to: CGPoint(x: 11.5, y: 15.5))
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
