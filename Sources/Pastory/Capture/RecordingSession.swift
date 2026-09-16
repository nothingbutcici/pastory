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
        tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-\(UUID().uuidString).mp4")
    }

    func start() {
        showFrame()
        showBar()
        Task { @MainActor in
            do {
                // Re-fetch so the frame and bar (created just now) are excluded; the shelf, if open, stays visible.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mine = Set([frame, bar].compactMap { $0 }.map { CGWindowID($0.windowNumber) })
                let own = content.windows.filter { mine.contains($0.windowID) }
                recorder.onFailure = { [weak self] err in
                    Task { @MainActor in self?.fail(err) }
                }
                let scale = NSScreen.screens.first { $0.frame.intersects(regionScreenRect) }?.backingScaleFactor
                try await recorder.start(target: target, excluding: own, backingScale: scale, outputURL: tmpURL)
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
        timeLabel?.stringValue = "保存中…".l
        Task { @MainActor in
            await recorder.stop()
            isRecording = false
            let dur = await GIFEncoder.duration(movie: tmpURL)
            guard dur > 0.2, FileManager.default.fileExists(atPath: tmpURL.path) else { fail(nil); return }
            showFormatChoice(duration: dur)
        }
    }

    func cancel() {
        guard !(stopping && isRecording) else { return }     // stop() is mid-flight; its continuation must not be raced
        timer?.invalidate()
        Task { @MainActor in
            if isRecording { await recorder.stop() }
            isRecording = false
            try? FileManager.default.removeItem(at: tmpURL)
            teardown()
        }
    }

    private var failed = false
    private func fail(_ error: Error?) {
        guard !failed else { return }      // both stream delegates report the same failure
        failed = true
        timer?.invalidate()
        isRecording = false
        try? FileManager.default.removeItem(at: tmpURL)
        teardown()
        if let error {
            let a = NSAlert()
            a.messageText = "录屏失败".l
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

    private func showBar() {
        bar?.orderOut(nil); bar?.close()
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 220, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = DeskStripView()
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
        label.textColor = Theme.onBrown
        timeLabel = label
        let stopBtn = Theme.paperButton("■ 停止".l, primary: true, target: self, action: #selector(stopTapped))
        let cancelBtn = Theme.paperButton("丢弃".l, onGround: true, target: self, action: #selector(cancelTapped))
        for x in [d, label, NSView(), stopBtn, cancelBtn] { stack.addArrangedSubview(x) }
        p.contentView = v
        place(p, size: CGSize(width: 290, height: 52))
        p.orderFrontRegardless()
        bar = p
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
        preview?.setBusy(gif ? "正在转 GIF…".l : "保存中…".l)
        Task { @MainActor in
            var fileURL = src
            if gif {
                let g = src.deletingPathExtension().appendingPathExtension("gif")
                do {
                    try await GIFEncoder.encode(movie: src, to: g) { [weak self] p in
                        Task { @MainActor in self?.preview?.setBusy(String(format: "正在转 GIF… %d%%".l, Int(p * 100))) }
                    }
                    fileURL = g
                } catch {
                    // The MP4 is untouched: let them pick it instead of throwing the recording away.
                    try? FileManager.default.removeItem(at: g)
                    preview?.setIdle(String(format: "GIF 转换失败：%@，可以改选 MP4".l, error.localizedDescription))
                    return
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

/// Desk-coloured strip, used as a bare container.
final class DeskStripView: NSView {
    init() {
        super.init(frame: .zero)
        Theme.paperSheet(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { Theme.drawDesk(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.paperRadius, yRadius: Theme.paperRadius)) }
}

/// Blue frame just outside the recorded region.
private final class FrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = 3
        AnnotatePalette.accent.setStroke()
        path.stroke()
    }
}
