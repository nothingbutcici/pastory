import AppKit

/// 「截屏 │ 录屏」pill shown above the selection, Feishu-style. Screenshot is the default;
/// tapping 录屏 hands the region to the recorder.
final class ModeSwitch: NSView {
    var onRecord: (() -> Void)?
    private let shot = NSButton(title: "截屏", target: nil, action: nil)
    private let rec = NSButton(title: "录屏", target: nil, action: nil)
    static let size = CGSize(width: 132, height: 32)

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.08).cgColor
        shadow = AnnotateToolbar.shadow()
        for (i, b) in [shot, rec].enumerated() {
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.frame = CGRect(x: 4 + CGFloat(i) * 62, y: 4, width: 62, height: 24)
            b.target = self
            addSubview(b)
        }
        shot.action = #selector(pickShot)
        rec.action = #selector(pickRec)
        style(active: shot)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func style(active: NSButton) {
        for b in [shot, rec] {
            let on = b === active
            b.layer?.backgroundColor = on ? AnnotateToolbar.selectedBG.cgColor : nil
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .foregroundColor: on ? AnnotateToolbar.selectedInk : NSColor(calibratedWhite: 0.3, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12.5, weight: on ? .semibold : .medium),
            ])
        }
    }

    @objc private func pickShot() { style(active: shot) }
    @objc private func pickRec() {
        style(active: rec)
        onRecord?()
    }
    override func mouseDown(with event: NSEvent) {}
}
