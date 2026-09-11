import Foundation

enum ClipKind: String, Codable {
    case text, url, image, files

    var label: String {
        switch self {
        case .text: return "文本"
        case .url: return "链接"
        case .image: return "图片"
        case .files: return "文件"
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
    /// Extension of items/<id>.<ext>: txt / png / json
    var ext: String
    var hasRTF: Bool
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int
    /// Hash of the payload, for de-duplicating back-to-back copies.
    var contentHash: Int

    var fileName: String { "\(id).\(ext)" }

    static func snippet(ofText s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(400))
    }
}
