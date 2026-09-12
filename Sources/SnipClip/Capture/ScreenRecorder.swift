import AVFoundation
import ScreenCaptureKit

/// SCStream + SCRecordingOutput straight to an .mp4. Cursor included, no audio: this is
/// "frame a region, record a short demo, send it", not a production recorder.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private let lock = NSLock()
    private var finished = false
    private var finishCont: CheckedContinuation<Void, Never>?
    private(set) var pixelSize = CGSize.zero
    var onFailure: ((Error) -> Void)?

    func start(target: CaptureTarget, excluding windows: [SCWindow], backingScale: CGFloat?, outputURL: URL) async throws {
        let filter: SCContentFilter
        switch target {
        case .display(let d), .region(let d, _):
            filter = SCContentFilter(display: d, excludingWindows: windows)
        case .window(let w):
            filter = SCContentFilter(desktopIndependentWindow: w)
        }
        let cfg = SCStreamConfiguration()
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6
        cfg.scalesToFit = false
        cfg.captureResolution = .best
        cfg.showsCursor = true
        cfg.capturesAudio = false
        let scale = Screenshotter.pixelScale(filter, backingScale: backingScale)
        let pointSize: CGSize
        switch target {
        case .region(_, let r):
            cfg.sourceRect = r
            pointSize = r.size
        case .display, .window:
            pointSize = filter.contentRect.size
        }
        cfg.width = Self.evened(pointSize.width * scale)
        cfg.height = Self.evened(pointSize.height * scale)
        pixelSize = CGSize(width: cfg.width, height: cfg.height)

        let outCfg = SCRecordingOutputConfiguration()
        outCfg.outputURL = outputURL
        outCfg.outputFileType = .mp4
        outCfg.videoCodecType = .h264

        lock.withLock { finished = false }
        let out = SCRecordingOutput(configuration: outCfg, delegate: self)
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addRecordingOutput(out)
        try await s.startCapture()
        stream = s
        output = out
    }

    func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        await waitForFinalize(timeoutNs: 15_000_000_000)
        if let out = output { try? s.removeRecordingOutput(out) }
        stream = nil
        output = nil
    }

    private func waitForFinalize(timeoutNs: UInt64) async {
        if lock.withLock({ finished }) { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let done = lock.withLock { () -> Bool in
                if finished { return true }
                finishCont = cont
                return false
            }
            if done { cont.resume(); return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNs)
                self?.resumeWaiter()
            }
        }
    }

    private func resumeWaiter() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let c = finishCont
            finishCont = nil
            return c
        }
        c?.resume()
    }

    private static func evened(_ v: CGFloat) -> Int {
        let n = max(2, Int(v.rounded()))
        return n % 2 == 0 ? n : n - 1
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?(error) }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { onFailure?(error) }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        lock.withLock { finished = true }
        resumeWaiter()
    }
}
