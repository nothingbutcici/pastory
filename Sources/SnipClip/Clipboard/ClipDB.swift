import Foundation
import SQLite3

/// The index, in SQLite (WAL). Payloads stay as files next to it; this replaces index.json.
/// One table, whole-list writes inside a transaction: simple, atomic, and quick for thousands of rows.
final class ClipDB {
    private var db: OpaquePointer?
    let url: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Self.error(db, "open")
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA synchronous=NORMAL")
        try exec("""
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY, kind TEXT NOT NULL, created_at REAL NOT NULL,
                source_bundle TEXT, source_name TEXT, snippet TEXT NOT NULL, ocr_text TEXT,
                pinned INTEGER NOT NULL DEFAULT 0, ext TEXT NOT NULL, has_rtf INTEGER NOT NULL DEFAULT 0,
                pixel_w INTEGER, pixel_h INTEGER, byte_count INTEGER NOT NULL DEFAULT 0,
                duration REAL, title TEXT, content_hash INTEGER NOT NULL DEFAULT 0
            )
            """)
        try exec("CREATE INDEX IF NOT EXISTS items_created ON items(created_at DESC)")
    }

    deinit { sqlite3_close(db) }

    static func error(_ db: OpaquePointer?, _ what: String) -> NSError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return NSError(domain: "Pastory.SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(what): \(msg)"])
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw Self.error(db, sql) }
    }

    /// Newest first.
    func loadAll() throws -> [ClipItem] {
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, kind, created_at, source_bundle, source_name, snippet, ocr_text, pinned, ext, has_rtf,
                   pixel_w, pixel_h, byte_count, duration, title, content_hash FROM items ORDER BY created_at DESC
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw Self.error(db, "prepare select") }
        defer { sqlite3_finalize(stmt) }
        var out: [ClipItem] = []
        func text(_ i: Int32) -> String? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, i)) }
        func int(_ i: Int32) -> Int? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i)) }
        func real(_ i: Int32) -> Double? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = text(0), let kindRaw = text(1), let kind = ClipKind(rawValue: kindRaw), let created = real(2),
                  let snippet = text(5), let ext = text(8) else { continue }
            out.append(ClipItem(id: id, kind: kind, createdAt: Date(timeIntervalSince1970: created),
                                sourceBundleID: text(3), sourceAppName: text(4), snippet: snippet, ocrText: text(6),
                                pinned: (int(7) ?? 0) != 0, ext: ext, hasRTF: (int(9) ?? 0) != 0,
                                pixelWidth: int(10), pixelHeight: int(11), byteCount: int(12) ?? 0,
                                duration: real(13), title: text(14), contentHash: int(15) ?? 0))
        }
        return out
    }

    /// Replace the whole table with `items` atomically.
    func saveAll(_ items: [ClipItem]) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try exec("DELETE FROM items")
            var stmt: OpaquePointer?
            let sql = """
                INSERT INTO items (id, kind, created_at, source_bundle, source_name, snippet, ocr_text, pinned, ext, has_rtf,
                                   pixel_w, pixel_h, byte_count, duration, title, content_hash)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw Self.error(db, "prepare insert") }
            defer { sqlite3_finalize(stmt) }
            for it in items {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                func bindText(_ i: Int32, _ s: String?) { if let s { sqlite3_bind_text(stmt, i, s, -1, Self.transient) } else { sqlite3_bind_null(stmt, i) } }
                func bindInt(_ i: Int32, _ v: Int?) { if let v { sqlite3_bind_int64(stmt, i, Int64(v)) } else { sqlite3_bind_null(stmt, i) } }
                func bindReal(_ i: Int32, _ v: Double?) { if let v { sqlite3_bind_double(stmt, i, v) } else { sqlite3_bind_null(stmt, i) } }
                bindText(1, it.id); bindText(2, it.kind.rawValue); bindReal(3, it.createdAt.timeIntervalSince1970)
                bindText(4, it.sourceBundleID); bindText(5, it.sourceAppName); bindText(6, it.snippet); bindText(7, it.ocrText)
                bindInt(8, it.pinned ? 1 : 0); bindText(9, it.ext); bindInt(10, it.hasRTF ? 1 : 0)
                bindInt(11, it.pixelWidth); bindInt(12, it.pixelHeight); bindInt(13, it.byteCount)
                bindReal(14, it.duration); bindText(15, it.title); bindInt(16, it.contentHash)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw Self.error(db, "insert") }
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}
