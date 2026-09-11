import AppKit

/// Brand bar above everything while capturing:  [logo] Snip Clip   [ 截屏 | 录屏 ]  │  ✕
final class TopBar: NSView {
    var onRecord: (() -> Void)?
    var onClose: (() -> Void)?
    private let shot = NSButton(title: "截屏", target: nil, action: nil)
    private let rec = NSButton(title: "录屏", target: nil, action: nil)
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        Theme.island(self)
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let logo = NSImageView(image: Theme.logo ?? NSImage())
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 32).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let name = NSTextField(labelWithString: "Snip Clip")
        name.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        name.textColor = Theme.text
        let brand = NSStackView(views: [logo, name])
        brand.spacing = 9
        stack.addArrangedSubview(brand)
        stack.setCustomSpacing(22, after: brand)

        let seg = NSView()
        seg.wantsLayer = true
        seg.layer?.backgroundColor = Theme.bgElevated.cgColor
        seg.layer?.cornerRadius = 9
        seg.translatesAutoresizingMaskIntoConstraints = false
        let segStack = NSStackView(views: [shot, rec])
        segStack.spacing = 3
        segStack.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        segStack.translatesAutoresizingMaskIntoConstraints = false
        seg.addSubview(segStack)
        NSLayoutConstraint.activate([
            segStack.leadingAnchor.constraint(equalTo: seg.leadingAnchor), segStack.trailingAnchor.constraint(equalTo: seg.trailingAnchor),
            segStack.topAnchor.constraint(equalTo: seg.topAnchor), segStack.bottomAnchor.constraint(equalTo: seg.bottomAnchor),
        ])
        for (b, symbol) in [(shot, "viewfinder"), (rec, "camera")] {
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 8
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            b.imagePosition = .imageLeading
            b.imageHugsTitle = true
            b.target = self
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            b.widthAnchor.constraint(equalToConstant: 80).isActive = true
        }
        shot.action = #selector(pickShot)
        rec.action = #selector(pickRec)
        stack.addArrangedSubview(seg)
        stack.addArrangedSubview(Theme.divider(height: 28))
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消")!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))!, target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = Theme.text
        close.toolTip = "取消 ⎋"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: 40).isActive = true
        close.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(close)
        style(active: shot)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width, height: 52) }
    override func draw(_ dirtyRect: NSRect) { Theme.drawIsland(NSBezierPath(roundedRect: bounds, xRadius: Theme.cornerRadius, yRadius: Theme.cornerRadius)) }

    private func style(active: NSButton) {
        for b in [shot, rec] {
            let on = b === active
            b.layer?.backgroundColor = on ? Theme.purple.cgColor : nil
            b.contentTintColor = on ? Theme.onPurple : Theme.text
            b.attributedTitle = NSAttributedString(string: " " + b.title.trimmingCharacters(in: .whitespaces), attributes: [
                .foregroundColor: on ? Theme.onPurple : Theme.text,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ])
        }
    }

    @objc private func pickShot() { style(active: shot) }
    @objc private func pickRec() { style(active: rec); onRecord?() }
    @objc private func closeTapped() { onClose?() }

    // Drag the bar anywhere on its ground.
    private var dragOrigin: CGPoint?
    override func mouseDown(with event: NSEvent) { dragOrigin = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let o = dragOrigin, let host = superview else { return }
        let p = convert(event.locationInWindow, from: nil)
        var f = frame.offsetBy(dx: p.x - o.x, dy: p.y - o.y)
        f.origin.x = min(max(host.bounds.minX, f.minX), host.bounds.maxX - f.width)
        f.origin.y = min(max(host.bounds.minY, f.minY), host.bounds.maxY - f.height)
        frame = f
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }
}
