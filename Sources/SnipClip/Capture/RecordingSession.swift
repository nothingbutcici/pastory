import AppKit
import ScreenCaptureKit

/// Region recording after the picker: a click-through frame around the region, a small control bar,
/// then "MP4 or GIF?" when you stop. Result goes to the shelf and the pasteboard as a file.
@MainActor
final class RecordingSession {
    private let target: CaptureTarget
    private let regionScreenRect: CGRect
    private let recorder = ScreenRecorder()
    private var frame: NSWindow?
    private var bar: NSPanel?
    private var timeLabel: NSTextField?
    private var dot: NSView?
    private var timer: Timer?
    private var started = Date()
    private var tmpURL: URL
    private(set) var isRecording = false
    private var stopping = false
    var onFinish: (() -> Void)?

    init(target: CaptureTarget, regionScreenRect: CGRect) {
        self.target = target
        self.regionScreenRect = regionScreenRect
        tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("snipclip-\(UUID().uuidString).mp4")
    }

    func start() {
        showFrame()
        showBar(recording: true)
        Task { @MainActor in
            do {
                // Re-fetch so the frame and bar (created just now) are excluded; the shelf, if open, stays visible.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mine = Set([frame, bar].compactMap { $0 }.map { CGWindowID($0.windowNumber) })
                let own = content.windows.filter { mine.contains($0.windowID) }
                recorder.onFailure = { [weak self] err in
                    Task { @MainActor in self?.fail(err) }
                }
                try await recorder.start(target: target, excluding: own, outputURL: tmpURL)
                isRecording = true
                started = Date()
                let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
                RunLoop.main.add(t, forMode: .common)
                timer = t
                tick()
            } catch {
                fail(error)
            }
        }
    }

    private func tick() {
        let s = Int(Date().timeIntervalSince(started))
        timeLabel?.stringValue = String(format: "%02d:%02d", s / 60, s % 60)
        dot?.alphaValue = dot?.alphaValue == 1 ? 0.25 : 1
        if s >= 600 { stop() }     // 10 min hard cap; this is for short demos
    }

    func stop() {
        guard isRecording, !stopping else { return }
        stopping = true
        timer?.invalidate()
        timeLabel?.stringValue = "保存中…"
        Task { @MainActor in
            await recorder.stop()
            isRecording = false
            let dur = await GIFEncoder.duration(movie: tmpURL)
            guard dur > 0.2, FileManager.default.fileExists(atPath: tmpURL.path) else { fail(nil); return }
            showFormatChoice(duration: dur)
        }
    }

    func cancel() {
        timer?.invalidate()
        Task { @MainActor in
            if isRecording { await recorder.stop() }
            isRecording = false
            try? FileManager.default.removeItem(at: tmpURL)
            teardown()
        }
    }

    private func fail(_ error: Error?) {
        timer?.invalidate()
        isRecording = false
        try? FileManager.default.removeItem(at: tmpURL)
        teardown()
        if let error {
            let a = NSAlert()
            a.messageText = "录屏失败"
            a.informativeText = (error as NSError).localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    private func teardown() {
        frame?.orderOut(nil); frame?.close(); frame = nil
        bar?.orderOut(nil); bar?.close(); bar = nil
        preview?.onDiscard = nil
        preview?.close()
        preview = nil
        onFinish?()
    }

    // MARK: Windows

    private func showFrame() {
        let pad: CGFloat = 3
        let r = regionScreenRect.insetBy(dx: -pad, dy: -pad)
        let w = NSWindow(contentRect: r, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = FrameView(frame: CGRect(origin: .zero, size: r.size))
        w.orderFrontRegardless()
        frame = w
    }

    private func showBar(recording: Bool) {
        bar?.orderOut(nil); bar?.close()
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 220, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = IslandView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor), stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.topAnchor.constraint(equalTo: v.topAnchor), stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        let d = NSView()
        d.wantsLayer = true
        d.layer?.backgroundColor = NSColor(srgbRed: 0.88, green: 0.20, blue: 0.20, alpha: 1).cgColor
        d.layer?.cornerRadius = 5
        d.translatesAutoresizingMaskIntoConstraints = false
        d.widthAnchor.constraint(equalToConstant: 10).isActive = true
        d.heightAnchor.constraint(equalToConstant: 10).isActive = true
        dot = d
        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = Theme.text
        timeLabel = label
        let stopBtn = pill("■ 停止", fill: Theme.purple, ink: Theme.onPurple, action: #selector(stopTapped))
        let cancelBtn = pill("丢弃", fill: Theme.shelfCard, ink: Theme.text, action: #selector(cancelTapped))
        for x in [d, label, NSView(), stopBtn, cancelBtn] { stack.addArrangedSubview(x) }
        p.contentView = v
        place(p, size: CGSize(width: 290, height: 52))
        p.orderFrontRegardless()
        bar = p
    }

    private func pill(_ title: String, fill: NSColor, ink: NSColor, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: ink, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.layer?.backgroundColor = fill.cgColor
        b.layer?.borderWidth = fill == Theme.shelfCard ? 1 : 0
        b.layer?.borderColor = Theme.shelfBorder.cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    private func place(_ p: NSWindow, size: CGSize) {
        let screen = NSScreen.screens.first { $0.frame.intersects(regionScreenRect) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? regionScreenRect
        var origin = CGPoint(x: regionScreenRect.maxX - size.width, y: regionScreenRect.minY - size.height - 10)
        if origin.y < vf.minY { origin.y = regionScreenRect.maxY + 10 }
        if origin.y + size.height > vf.maxY { origin.y = regionScreenRect.minY + 10 }
        origin.x = min(max(vf.minX + 8, origin.x), vf.maxX - size.width - 8)
        p.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    @objc private func stopTapped() { stop() }
    @objc private func cancelTapped() { cancel() }

    // MARK: After stop

    private var preview: RecordingPreviewWindow?

    private func showFormatChoice(duration: Double) {
        frame?.orderOut(nil); frame?.close(); frame = nil
        bar?.orderOut(nil); bar?.close(); bar = nil
        let w = RecordingPreviewWindow(movie: tmpURL, duration: duration, pixelSize: recorder.pixelSize, near: regionScreenRect)
        w.onChoose = { [weak self] gif in self?.deliver(gif: gif) }
        w.onDiscard = { [weak self] in self?.cancel() }
        preview = w
        w.present()
    }

    private func deliver(gif: Bool) {
        let src = tmpURL
        preview?.setBusy(gif ? "正在转 GIF…" : "保存中…")
        Task { @MainActor in
            var fileURL = src
            if gif {
                let g = src.deletingPathExtension().appendingPathExtension("gif")
                do {
                    try await GIFEncoder.encode(movie: src, to: g) { [weak self] p in
                        Task { @MainActor in self?.preview?.setBusy("正在转 GIF… \(Int(p * 100))%") }
                    }
                    fileURL = g
                } catch {
                    fail(error); return
                }
            }
            let poster = await GIFEncoder.poster(movie: src)
            let dur = await GIFEncoder.duration(movie: src)
            let item = ClipStore.shared.insertVideo(tempFile: fileURL, poster: poster, duration: dur, source: CaptureCoordinator.source)
            if gif { try? FileManager.default.removeItem(at: src) }
            if let item { ClipStore.shared.copyToPasteboard(item) }
            teardown()      // closes the preview too
        }
    }
}

/// Dark rounded island with the grid, used as a bare container.
final class IslandView: NSView {
    init() {
        super.init(frame: .zero)
        Theme.island(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { Theme.drawIsland(NSBezierPath(roundedRect: bounds, xRadius: Theme.cornerRadius, yRadius: Theme.cornerRadius)) }
}

/// Purple frame just outside the recorded region.
private final class FrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 3
        AnnotatePalette.accent.setStroke()
        path.stroke()
    }
}
