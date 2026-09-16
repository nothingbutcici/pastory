import Foundation

enum ClipKind: String, Codable {
    case text, url, image, files, video

    var label: String {
        switch self {
        case .text: return "文本".l
        case .url: return "链接".l
        case .image: return "图片".l
        case .files: return "文件".l
        case .video: return "录屏".l
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
    /// Last change to any field (pin, title, OCR, edit, bump). Sync merges on this; equals createdAt for old rows.
    var modifiedAt: Date = Date()

    var fileName: String { "\(id).\(ext)" }

    enum CodingKeys: String, CodingKey {
        case id, kind, createdAt, sourceBundleID, sourceAppName, snippet, ocrText, pinned, ext, hasRTF,
             pixelWidth, pixelHeight, byteCount, duration, title, contentHash, modifiedAt
    }

    init(id: String, kind: ClipKind, createdAt: Date, sourceBundleID: String?, sourceAppName: String?, snippet: String, ocrText: String?,
         pinned: Bool, ext: String, hasRTF: Bool, pixelWidth: Int?, pixelHeight: Int?, byteCount: Int, duration: Double?, title: String?,
         contentHash: Int, modifiedAt: Date? = nil) {
        self.id = id; self.kind = kind; self.createdAt = createdAt; self.sourceBundleID = sourceBundleID; self.sourceAppName = sourceAppName
        self.snippet = snippet; self.ocrText = ocrText; self.pinned = pinned; self.ext = ext; self.hasRTF = hasRTF
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.byteCount = byteCount; self.duration = duration; self.title = title
        self.contentHash = contentHash; self.modifiedAt = modifiedAt ?? createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ClipKind.self, forKey: .kind)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        snippet = try c.decode(String.self, forKey: .snippet)
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        ext = try c.decode(String.self, forKey: .ext)
        hasRTF = try c.decode(Bool.self, forKey: .hasRTF)
        pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight)
        byteCount = try c.decode(Int.self, forKey: .byteCount)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        contentHash = try c.decodeIfPresent(Int.self, forKey: .contentHash) ?? 0
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    /// One http(s) link on its own line, nothing else.
    static func isURLText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains("\n"), let url = URL(string: t), let s = url.scheme else { return false }
        return ["http", "https"].contains(s)
    }

    static func snippet(ofText s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(400))
    }
}
