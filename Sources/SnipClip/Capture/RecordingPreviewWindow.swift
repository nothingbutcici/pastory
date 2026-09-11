import AppKit
import AVKit

/// Plays the fresh recording on loop so you can judge it before it goes anywhere.
/// Buttons: 丢弃 · 保存为 GIF · 复制 MP4（默认）.
@MainActor
final class RecordingPreviewWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let player: AVPlayer
    private var looper: Any?
    private let info = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    var onChoose: ((Bool) -> Void)?
    var onDiscard: (() -> Void)?
    private var decided = false

    init(movie: URL, duration: Double, pixelSize: CGSize, near anchor: CGRect) {
        player = AVPlayer(url: movie)
        player.isMuted = true
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Fit the video into 70% of the screen, never larger than its point size.
        let scale = screen?.backingScaleFactor ?? 2
        let natural = CGSize(width: max(1, pixelSize.width / scale), height: max(1, pixelSize.height / scale))
        let k = min(1, min(vf.width * 0.7 / natural.width, vf.height * 0.7 / natural.height))
        let videoSize = CGSize(width: max(360, (natural.width * k).rounded()), height: max(200, (natural.height * k).rounded()))
        let barH: CGFloat = 56
        let rect = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height + barH)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "录屏预览"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)

        let content = NSView(frame: rect)
        let pv = AVPlayerView()
        pv.player = player
        pv.controlsStyle = .inline
        pv.videoGravity = .resizeAspect
        pv.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pv)

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        info.font = NSFont.systemFont(ofSize: 12)
        info.textColor = NSColor(calibratedWhite: 1, alpha: 0.7)
        info.lineBreakMode = .byTruncatingTail
        info.stringValue = String(format: "%d 秒 · %d×%d · 循环播放中", Int(duration.rounded()), Int(pixelSize.width), Int(pixelSize.height))
        info.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(info)

        let discard = pill("丢弃", tint: NSColor(calibratedWhite: 1, alpha: 0.75), filled: false, action: #selector(discardTapped))
        let gif = pill(duration > 30 ? "保存为 GIF（会很大）" : "保存为 GIF", tint: NSColor(srgbRed: 0.35, green: 0.80, blue: 0.45, alpha: 1), filled: false, action: #selector(gifTapped))
        let mp4 = pill("复制 MP4  ⏎", tint: AnnotatePalette.accent, filled: true, action: #selector(mp4Tapped))
        mp4.keyEquivalent = "\r"
        buttons = [discard, gif, mp4]
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: content.topAnchor),
            pv.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: barH),
            info.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            info.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            info.trailingAnchor.constraint(lessThanOrEqualTo: stack.leadingAnchor, constant: -12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
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
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        player.play()
    }

    func setBusy(_ text: String) {
        info.stringValue = text
        buttons.forEach { $0.isEnabled = false; $0.alphaValue = 0.4 }
    }

    /// Final line, then the window goes away on its own.
    func setDone(_ text: String) {
        info.stringValue = text
        player.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.close() }
    }

    func close() {
        decided = true
        player.pause()
        if let looper { NotificationCenter.default.removeObserver(looper) }
        looper = nil
        window.orderOut(nil)
        window.close()
    }

    private func pill(_ title: String, tint: NSColor, filled: Bool, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: filled ? NSColor.white : tint, .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)])
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.layer?.backgroundColor = filled ? tint.cgColor : tint.withAlphaComponent(0.14).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        b.contentTintColor = tint
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
