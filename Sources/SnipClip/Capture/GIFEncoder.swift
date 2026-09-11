import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// MP4 → GIF: sample at a fixed rate, keep the recording's own pixels (long edge capped at 1920),
/// let ImageIO build per-frame palettes.
enum GIFEncoder {
    static let fps: Double = 12
    static let maxEdge: CGFloat = 1920

    static func encode(movie: URL, to out: URL, progress: ((Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "gif", code: 1) }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let k = min(1, maxEdge / max(natural.width, natural.height))
        let size = CGSize(width: (natural.width * k).rounded(), height: (natural.height * k).rounded())

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
