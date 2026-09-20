import Foundation

/// File I/O, normalization and full-text scans stay off the UI actor. This is a disposable memory cache;
/// the clipboard database and payload files remain the source of truth.
actor ClipSearchIndex {
    private struct Document: Equatable {
        let kind: ClipKind
        let hash: Int
        let ext: String
        let snippet: String
        let ocr: String
        let source: String
        let title: String

        init(_ item: ClipItem) {
            kind = item.kind
            hash = item.contentHash
            ext = item.ext
            snippet = item.snippet
            ocr = item.ocrText ?? ""
            source = item.sourceAppName ?? ""
            title = item.title ?? ""
        }
    }

    private struct Entry {
        let document: Document
        let literalText: NSString      // lower-cased, precomposed; the only copy kept
    }

    private var entries: [String: Entry] = [:]
    private var cachedDirectory: URL?
    /// Used by the search self-test to verify that focusing, pinning and copying do not reread payloads.
    private(set) var payloadReadCount = 0

    nonisolated static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces).lowercased().precomposedStringWithCanonicalMapping
    }

    /// An empty query warms the cache without scanning for matches. Cancellation preserves completed entries
    /// so a new query can reuse that work, and checks between files stop obsolete searches promptly.
    func search(_ query: String, items: [ClipItem], directory: URL) throws -> Set<String> {
        try Task.checkCancellation()
        let query = Self.normalizedQuery(query)
        if cachedDirectory != directory {
            entries.removeAll()
            cachedDirectory = directory
        }
        let live = Set(items.map(\.id))
        for id in Array(entries.keys) where !live.contains(id) { entries[id] = nil }
        var matches = Set<String>()
        for item in items {
            try Task.checkCancellation()
            let document = Document(item)
            let entry: Entry
            if let cached = entries[item.id], cached.document == document {
                entry = cached
            } else {
                let body: String
                var cacheable = true
                if item.kind == .text || item.kind == .url {
                    payloadReadCount += 1
                    if let text = try? String(contentsOf: directory.appendingPathComponent(item.fileName), encoding: .utf8) {
                        body = text
                    } else {
                        body = item.snippet
                        cacheable = false     // retry a missing/unreadable payload on the next search
                    }
                } else { body = item.snippet }
                try Task.checkCancellation()
                let text = [body, document.ocr, document.source, document.title].joined(separator: "\n")
                    .lowercased().precomposedStringWithCanonicalMapping
                entry = Entry(document: document, literalText: text as NSString)
                entries[item.id] = cacheable ? entry : nil
            }
            guard !query.isEmpty else { continue }
            // Literal match on precomposed text. Deliberately not grapheme-strict: 👍 should find 👍🏽 and 👩 should
            // find 👨‍👩‍👧, which a cluster-by-cluster comparison refuses. It is also the fast path.
            if entry.literalText.range(of: query, options: .literal).location != NSNotFound { matches.insert(item.id) }
        }
        try Task.checkCancellation()
        return matches
    }
}
