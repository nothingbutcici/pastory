import CoreGraphics
import Vision

/// On-device text recognition, Chinese + English. Lines come back top-to-bottom.
enum OCR {
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let obs = request.results ?? []
        // Vision's order is mostly reading order already; sort by top edge, then left edge.
        let sorted = obs.sorted { a, b in
            let ay = a.boundingBox.maxY, by = b.boundingBox.maxY
            if abs(ay - by) > 0.01 { return ay > by }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
