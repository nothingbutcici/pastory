import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// MP4 → GIF with a size budget: start from the recording's pixels (long edge ≤ 1280, 10 fps) and
/// scale down / drop frames until the estimate fits ~8 MB. Short clips stay sharp, long ones stay sendable.
enum GIFEncoder {
    static let budgetBytes: Double = 8 * 1024 * 1024
    static let bytesPerPixelFrame: Double = 0.15      // optimistic; a second pass corrects if the file overshoots
    static let maxEdge: CGFloat = 1280
    static let minEdge: CGFloat = 640

    struct Plan { var size: CGSize; var fps: Double }

    static func plan(natural: CGSize, duration: Double, shrink: Double = 1) -> Plan {
        var k = min(1, maxEdge / max(natural.width, natural.height)) * shrink
        var fps = 10.0
        func estimate() -> Double { duration * fps * Double(natural.width * k) * Double(natural.height * k) * bytesPerPixelFrame }
        if estimate() > budgetBytes { fps = 8 }
        if estimate() > budgetBytes {
            k *= sqrt(budgetBytes / estimate())
            let minK = minEdge / max(natural.width, natural.height)
            k = max(min(k, 1), min(minK, 1))
        }
        if estimate() > budgetBytes { fps = 6 }
        return Plan(size: CGSize(width: (natural.width * k).rounded(), height: (natural.height * k).rounded()), fps: fps)
    }

    /// Encode once; if the file overshoots the budget by more than a quarter, shrink and encode again.
    static func encode(movie: URL, to out: URL, progress: ((Double) -> Void)? = nil) async throws {
        try await encodePass(movie: movie, to: out, shrink: 1, progress: progress)
        let bytes = Double((try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0)
        if bytes > budgetBytes * 1.25 {
            let shrink = max(0.4, sqrt(budgetBytes / bytes))
            try await encodePass(movie: movie, to: out, shrink: shrink, progress: progress)
        }
    }

    private static func encodePass(movie: URL, to out: URL, shrink: Double, progress: ((Double) -> Void)?) async throws {
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "gif", code: 1) }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let plan = plan(natural: natural, duration: duration, shrink: shrink)
        let fps = plan.fps
        let size = plan.size
        let k = size.width / natural.width

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "gif", code: 2) }

        let count = max(1, Int(duration * fps))
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw NSError(domain: "gif", code: 3) }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        var nextTime = 0.0
        var written = 0
        var lastImage: CGImage?
        while let sb = output.copyNextSampleBuffer() {
            let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
            guard t + 1e-6 >= nextTime, let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let ci = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: k, y: k))
            guard let cg = ciContext.createCGImage(ci, from: CGRect(origin: .zero, size: size)) else { continue }
            // A slow source (static screen) yields fewer frames than the clock wants; repeat to keep timing.
            while nextTime <= t && written < count {
                CGImageDestinationAddImage(dest, cg, frameProps)
                written += 1
                nextTime += 1 / fps
            }
            lastImage = cg
            progress?(Double(written) / Double(count))
            if written >= count { break }
        }
        while written < count, let cg = lastImage { CGImageDestinationAddImage(dest, cg, frameProps); written += 1 }
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "gif", code: 4) }
    }

    /// First frame, for thumbnails.
    static func poster(movie: URL) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        return try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
    }

    static func duration(movie: URL) async -> Double {
        (try? await AVURLAsset(url: movie).load(.duration).seconds) ?? 0
    }
}
