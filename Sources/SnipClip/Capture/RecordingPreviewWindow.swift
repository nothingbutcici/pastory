import AppKit
import AVFoundation
import AVKit

/// Plays the fresh recording on loop so you can judge it before it goes anywhere.
/// Dark island look: our own transport bar (play, time, purple progress, duration),
/// then 丢弃 · 复制为 GIF · 复制为 MP4.
@MainActor
final class RecordingPreviewWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let player: AVPlayer
    private var looper: Any?
    private var timeObserver: Any?
    private let info = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private let transport: TransportBar
    var onChoose: ((Bool) -> Void)?
    var onDiscard: (() -> Void)?
    private var decided = false

    init(movie: URL, duration: Double, pixelSize: CGSize, near anchor: CGRect) {
        player = AVPlayer(url: movie)
        player.isMuted = true
        transport = TransportBar(duration: duration)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = screen?.backingScaleFactor ?? 2
        let natural = CGSize(width: max(1, pixelSize.width / scale), height: max(1, pixelSize.height / scale))
        let k = min(1, min((vf.width * 0.7 - 48) / natural.width, (vf.height * 0.7 - 160) / natural.height))
        let videoSize = CGSize(width: max(420, (natural.width * k).rounded()), height: max(220, (natural.height * k).rounded()))
        let pad: CGFloat = 24
        let transportH: CGFloat = 52
        let buttonsH: CGFloat = 64
        let rect = CGRect(x: 0, y: 0, width: videoSize.width + pad * 2, height: 44 + videoSize.height + transportH + buttonsH)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "录屏预览"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.shelfBG
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let content = GridBackdropView(frame: rect)
        let pv = AVPlayerView()
        pv.player = player
        pv.controlsStyle = .none
        pv.videoGravity = .resizeAspect
        pv.wantsLayer = true
        pv.layer?.cornerRadius = 12
        pv.layer?.masksToBounds = true
        pv.frame = CGRect(x: pad, y: transportH + buttonsH, width: videoSize.width, height: videoSize.height)
        content.addSubview(pv)

        transport.frame = CGRect(x: pad, y: buttonsH, width: videoSize.width, height: transportH)
        transport.onToggle = { [weak self] in self?.togglePlay() }
        transport.onSeek = { [weak self] t in
            guard let self else { return }
            self.player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        content.addSubview(transport)

        info.font = NSFont.systemFont(ofSize: 12)
        info.textColor = Theme.shelfMuted
        info.lineBreakMode = .byTruncatingTail
        let discard = pill("丢弃", fill: Theme.shelfCard, ink: Theme.text, action: #selector(discardTapped))
        let gif = pill(duration > 30 ? "复制为 GIF（会很大）" : "复制为 GIF", fill: Theme.shelfCard, ink: Theme.text, action: #selector(gifTapped))
        let mp4 = pill("复制为 MP4", fill: Theme.purple, ink: Theme.onPurple, action: #selector(mp4Tapped))
        mp4.keyEquivalent = "\r"
        buttons = [discard, gif, mp4]
        let stack = NSStackView(views: buttons)
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        info.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        content.addSubview(info)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            info.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            info.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            info.trailingAnchor.constraint(lessThanOrEqualTo: stack.leadingAnchor, constant: -12),
        ])
        window.contentView = content

        var origin = CGPoint(x: anchor.midX - rect.width / 2, y: anchor.midY - rect.height / 2)
        origin.x = min(max(vf.minX + 12, origin.x), vf.maxX - rect.width - 12)
        origin.y = min(max(vf.minY + 12, origin.y), vf.maxY - rect.height - 12)
        window.setFrameOrigin(origin)

        looper = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.transport.current = t.seconds }
        }
    }

    /// Self-test only.
    var debugContentView: NSView? { window.contentView }
    func debugSeek(_ t: Double) { transport.current = t }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        player.play()
        transport.playing = true
    }

    private func togglePlay() {
        if player.timeControlStatus == .playing { player.pause(); transport.playing = false }
        else { player.play(); transport.playing = true }
    }

    func setBusy(_ text: String) {
        info.stringValue = text
        buttons.forEach { $0.isEnabled = false; $0.alphaValue = 0.4 }
    }

    func close() {
        decided = true
        player.pause()
        if let looper { NotificationCenter.default.removeObserver(looper) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        looper = nil
        timeObserver = nil
        window.orderOut(nil)
        window.close()
    }

    private func pill(_ title: String, fill: NSColor, ink: NSColor, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: ink, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.layer?.backgroundColor = fill.cgColor
        b.layer?.borderWidth = fill == Theme.shelfCard ? 1 : 0
        b.layer?.borderColor = Theme.shelfBorder.cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        return b
    }

    @objc private func discardTapped() { decided = true; onDiscard?() }
    @objc private func gifTapped() { decided = true; onChoose?(true) }
    @objc private func mp4Tapped() { decided = true; onChoose?(false) }

    /// Closing the window with the red button counts as discarding.
    func windowWillClose(_ notification: Notification) {
        if !decided { decided = true; onDiscard?() }
    }
}

/// Window ground: dark + grid.
final class GridBackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.shelfBG.setFill()
        bounds.fill()
        Theme.drawGrid(in: bounds)
    }
}

/// ▶ 00:01 ────●──── 00:11   — click or drag the track to seek.
final class TransportBar: NSView {
    var duration: Double
    var current: Double = 0 { didSet { needsDisplay = true } }
    var playing = false { didSet { needsDisplay = true } }
    var onToggle: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    private let buttonSize: CGFloat = 36
    private var trackRect: CGRect {
        CGRect(x: buttonSize + 14 + 52, y: bounds.midY - 3, width: bounds.width - (buttonSize + 14 + 52) - 52, height: 6)
    }

    init(duration: Double) {
        self.duration = max(0.01, duration)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func clock(_ t: Double) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }

    override func draw(_ dirtyRect: NSRect) {
        // Play / pause disc
        let disc = CGRect(x: 0, y: bounds.midY - buttonSize / 2, width: buttonSize, height: buttonSize)
        Theme.shelfCard.setFill()
        NSBezierPath(ovalIn: disc).fill()
        let icon = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .bold))
        if let icon {
            let tinted = icon.tinted(Theme.text)
            let s = tinted.size
            tinted.draw(in: CGRect(x: disc.midX - s.width / 2 + (playing ? 0 : 1), y: disc.midY - s.height / 2, width: s.width, height: s.height))
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: Theme.text]
        (clock(current) as NSString).draw(at: CGPoint(x: buttonSize + 14, y: bounds.midY - 8), withAttributes: attrs)
        let total = clock(duration) as NSString
        let ts = total.size(withAttributes: attrs)
        total.draw(at: CGPoint(x: bounds.maxX - ts.width, y: bounds.midY - 8), withAttributes: attrs)
        // Track
        let tr = trackRect
        NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: tr, xRadius: 3, yRadius: 3).fill()
        let f = min(1, max(0, current / duration))
        Theme.purple.setFill()
        NSBezierPath(roundedRect: CGRect(x: tr.minX, y: tr.minY, width: tr.width * f, height: tr.height), xRadius: 3, yRadius: 3).fill()
        let knob = CGRect(x: tr.minX + tr.width * f - 7, y: tr.midY - 7, width: 14, height: 14)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x <= buttonSize + 6 { onToggle?(); return }
        seek(to: p)
    }
    override func mouseDragged(with event: NSEvent) { seek(to: convert(event.locationInWindow, from: nil)) }
    private func seek(to p: CGPoint) {
        let tr = trackRect.insetBy(dx: -20, dy: -14)
        guard tr.contains(p) || abs(p.y - trackRect.midY) < 20 else { return }
        let f = min(1, max(0, (p.x - trackRect.minX) / trackRect.width))
        current = f * duration
        onSeek?(current)
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return img
    }
}
