import AppKit

/// Brand bar above everything while capturing:  [logo] Pastory   [ 截屏 | 录屏 ]  │  ✕
final class TopBar: NSView {
    var onRecord: (() -> Void)?
    var onClose: (() -> Void)?
    private let shot = NSButton(title: "截屏".l, target: nil, action: nil)
    private let rec = NSButton(title: "录屏".l, target: nil, action: nil)
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        Theme.paperSheet(self)
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
        logo.widthAnchor.constraint(equalToConstant: 30).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let name = NSTextField(labelWithString: "Pastory")
        name.font = Theme.brandFont(size: 19)
        name.textColor = Theme.onBrown
        let brand = NSStackView(views: [logo, name])
        brand.spacing = 9
        stack.addArrangedSubview(brand)
        stack.setCustomSpacing(22, after: brand)

        let seg = NSView()
        seg.wantsLayer = true
        seg.layer?.borderWidth = 1
        seg.layer?.borderColor = Theme.onBrown.withAlphaComponent(0.35).cgColor
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
        }
        // Both segments share one width, sized to the longer title in the current language.
        let widest = [shot, rec].map { (($0.title.trimmingCharacters(in: .whitespaces)) as NSString).size(withAttributes: [.font: Theme.serif(size: 14, bold: true)]).width }.max() ?? 40
        for b in [shot, rec] { b.widthAnchor.constraint(equalToConstant: (widest + 44).rounded(.up)).isActive = true }
        shot.action = #selector(pickShot)
        rec.action = #selector(pickRec)
        stack.addArrangedSubview(seg)
        stack.addArrangedSubview(Theme.deskDivider(height: 28))
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消".l)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))!, target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = Theme.onBrown
        close.toolTip = "取消 ⎋".l
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: 40).isActive = true
        close.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(close)
        style(active: shot)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width, height: 52) }
    override func draw(_ dirtyRect: NSRect) { Theme.drawDesk(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.paperRadius, yRadius: Theme.paperRadius)) }

    private func style(active: NSButton) {
        for b in [shot, rec] {
            let on = b === active
            b.layer?.backgroundColor = on ? Theme.paperBlue.cgColor : nil
            b.contentTintColor = on ? Theme.ink : Theme.onBrown
            b.attributedTitle = NSAttributedString(string: " " + b.title.trimmingCharacters(in: .whitespaces), attributes: [
                .foregroundColor: on ? Theme.ink : Theme.onBrown,
                .font: Theme.serif(size: 14, bold: on),
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
