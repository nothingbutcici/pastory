import AVFoundation
import ScreenCaptureKit

/// SCStream frames → our own AVAssetWriter, so the bitrate is decided while recording (no second pass).
/// Cursor included, no audio: this is "frame a region, record a short demo, send it", not a production recorder.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let queue = DispatchQueue(label: "pastory.recorder.frames")
    private var sessionStarted = false
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastPTS = CMTime.zero
    private var failed = false
    private(set) var pixelSize = CGSize.zero
    var onFailure: ((Error) -> Void)?

    static let fps: Int32 = 30

    /// Constant-quality target for the hardware encoder (0…1). Text stays crisp; still frames cost almost nothing,
    /// motion costs what it costs. 0.72 is roughly x264 CRF 20 territory for UI footage.
    static let quality: Float = 0.72

    /// Fallback when the encoder refuses quality mode: bits per pixel per frame, 0.07 (≈ 11 Mbps for 3200×1640 @ 30).
    static func bitrate(width: Int, height: Int, hevc: Bool) -> Int {
        let bpp = hevc ? 0.045 : 0.07
        let bps = Double(width * height) * Double(fps) * bpp
        return Int(min(max(bps, 2_500_000), 24_000_000))
    }

    func start(target: CaptureTarget, excluding windows: [SCWindow], backingScale: CGFloat?, outputURL: URL) async throws {
        let filter: SCContentFilter
        switch target {
        case .display(let d), .region(let d, _):
            filter = SCContentFilter(display: d, excludingWindows: windows)
        case .window(let w):
            filter = SCContentFilter(desktopIndependentWindow: w)
        }
        let cfg = SCStreamConfiguration()
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: Self.fps)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6
        cfg.scalesToFit = false
        cfg.captureResolution = .best
        cfg.showsCursor = true
        cfg.capturesAudio = false
        // Native = the display's pixels (Retina 2×); "standard" = 1 pixel per point, a quarter of the data.
        let scale = Preferences.shared.recordNativeScale ? Screenshotter.pixelScale(filter, backingScale: backingScale) : 1
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

        let (w, inp, ad) = try Self.makeWriter(url: outputURL, width: cfg.width, height: cfg.height, hevc: Preferences.shared.recordHEVC)
        writer = w; input = inp; adaptor = ad
        sessionStarted = false; lastPixelBuffer = nil; failed = false

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    /// Writer + input + adaptor, already started. Shared with the self-test so a bad settings key shows up there, not on ■.
    static func makeWriter(url: URL, width: Int, height: Int, hevc: Bool, constantQuality: Bool = true) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if constantQuality { compression[AVVideoQualityKey] = quality }
        else { compression[AVVideoAverageBitRateKey] = bitrate(width: width, height: height, hevc: hevc) }
        if !hevc { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let settings: [String: Any] = [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        inp.expectsMediaDataInRealTime = true
        guard w.canAdd(inp) else {
            if constantQuality { return try makeWriter(url: url, width: width, height: height, hevc: hevc, constantQuality: false) }
            throw NSError(domain: "Pastory.Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot add video input"])
        }
        w.add(inp)
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard w.startWriting() else { throw w.error ?? NSError(domain: "Pastory.Recorder", code: 2) }
        return (w, inp, ad)
    }

    // MARK: Frames

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, let input, let adaptor, let writer, writer.status == .writing else { return }
        // Only complete frames; SCK also delivers idle / blank ones.
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) != .complete { return }
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if !sessionStarted { writer.startSession(atSourceTime: pts); sessionStarted = true }
        guard input.isReadyForMoreMediaData else { return }        // encoder behind: drop, never block the capture queue
        if adaptor.append(pb, withPresentationTime: pts) { lastPixelBuffer = pb; lastPTS = pts }
        else if writer.status == .failed, !failed { failed = true; onFailure?(writer.error ?? NSError(domain: "Pastory.Recorder", code: 3)) }
    }

    func stop() async {
        guard let s = stream else { return }
        try? await s.stopCapture()
        try? s.removeStreamOutput(self, type: .screen)
        stream = nil
        guard let writer, let input else { return }
        // SCK sends frames only when something changes, so a still ending would otherwise be cut off:
        // hold the last picture up to the moment the user pressed stop.
        queue.sync {
            if sessionStarted, let pb = lastPixelBuffer, let adaptor {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                if CMTimeSubtract(now, lastPTS).seconds > 0.15, input.isReadyForMoreMediaData { _ = adaptor.append(pb, withPresentationTime: now) }
            }
            if sessionStarted { input.markAsFinished() }
        }
        if sessionStarted { await writer.finishWriting() } else { writer.cancelWriting() }
        if writer.status == .failed, !failed { failed = true; onFailure?(writer.error ?? NSError(domain: "Pastory.Recorder", code: 4)) }
        self.writer = nil; self.input = nil; adaptor = nil; lastPixelBuffer = nil
    }

    private static func evened(_ v: CGFloat) -> Int {
        let n = max(2, Int(v.rounded()))
        return n % 2 == 0 ? n : n - 1
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { if !failed { failed = true; onFailure?(error) } }
}
