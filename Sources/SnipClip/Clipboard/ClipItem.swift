import Foundation

enum ClipKind: String, Codable {
    case text, url, image, files, video

    var label: String {
        switch self {
        case .text: return "文本"
        case .url: return "链接"
        case .image: return "图片"
        case .files: return "文件"
        case .video: return "录屏"
        }
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    let id: String
    var kind: ClipKind
    var createdAt: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    /// Card preview: first lines of text, file names, or "1280×720".
    var snippet: String
    var ocrText: String?
    var pinned: Bool
    /// Extension of items/<id>.<ext>: txt / png / json / mp4 / gif
    var ext: String
    var hasRTF: Bool
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int
    /// Seconds, for recordings.
    var duration: Double?
    /// User-given name ("翻译 prompt"), shown above the content and searchable.
    var title: String?
    /// Hash of the payload, for de-duplicating back-to-back copies.
    var contentHash: Int

    var fileName: String { "\(id).\(ext)" }

    static func snippet(ofText s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(400))
    }
}
