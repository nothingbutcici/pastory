import AppKit

/// Small paper-style panel shown while an update downloads and installs: what is happening, how far, and a way out.
@MainActor
final class UpdateProgressWindow: NSObject {
    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let track = ProgressTrack()
    private var cancelButton: NSButton!
    var onCancel: (() -> Void)?

    init(version: String) {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 150),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = Theme.brown
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = GridBackdropView()
        title.stringValue = String(format: "正在下载 Pastory %@…".l, version)
        title.font = Theme.serif(size: 16, bold: true)
        title.textColor = Theme.onBrown
        detail.stringValue = "正在连接 GitHub…".l
        detail.font = Theme.serif(size: 13)
        detail.textColor = Theme.onBrownMuted
        cancelButton = Theme.paperButton("取消".l, onGround: true, target: self, action: #selector(cancelTapped))
        for v in [title, track, detail, cancelButton!] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -22),
            track.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            track.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            track.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            track.heightAnchor.constraint(equalToConstant: 8),
            detail.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            detail.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        panel.contentView = content
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }

    /// `total` is 0 until the server says how big the file is.
    func update(done: Int64, total: Int64) {
        let f = ByteCountFormatter(); f.countStyle = .file
        if total > 0 {
            track.fraction = CGFloat(done) / CGFloat(total)
            detail.stringValue = "\(f.string(fromByteCount: done)) / \(f.string(fromByteCount: total))"
        } else {
            detail.stringValue = f.string(fromByteCount: done)
        }
    }

    /// Download finished: verifying and swapping the bundle cannot be interrupted half-way.
    func beginInstalling() {
        title.stringValue = "正在校验并安装…".l
        detail.stringValue = ""
        track.fraction = 1
        cancelButton.isHidden = true
    }

    @objc private func cancelTapped() { onCancel?() }

    /// Self-test only.
    var debugContentView: NSView? { panel.contentView }
}

/// A thin paper-blue bar on a dim track.
final class ProgressTrack: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        Theme.onBrown.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        let w = max(bounds.height, bounds.width * min(max(fraction, 0), 1))
        guard fraction > 0 else { return }
        Theme.paperBlue.setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: r, yRadius: r).fill()
    }
}

/// One file download with progress and cancel. Short idle timeout: a stalled connection should fail, not hang.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private var progress: (@MainActor (Int64, Int64) -> Void)?
    private var moveError: Error?
    private let lock = NSLock()

    func fetch(_ url: URL, to destination: URL, progress: @escaping @MainActor (Int64, Int64) -> Void) async throws {
        self.destination = destination
        self.progress = progress
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 900
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); continuation = c; lock.unlock()
            let t = session.downloadTask(with: url)
            task = t
            t.resume()
        }
    }

    func cancel() { task?.cancel() }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let p = progress
        Task { @MainActor in p?(totalBytesWritten, max(0, totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is gone when this returns: move it now.
        guard let destination else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 { moveError = URLError(.badServerResponse); return }
        do { try FileManager.default.moveItem(at: location, to: destination) } catch { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let moveError { finish(.failure(moveError)) }
        else { finish(.success(())) }
    }
}
