import AppKit
import SQLite3

/// Pull clipboard history out of another tool's SQLite file.
/// Two paths: another Pastory store (exact), or any SQLite database (heuristic: text and image payloads,
/// dates and pins where a column looks like one; Core Data child→parent joins for the date).
enum Importer {
    struct Scan {
        var entries: [ClipStore.ImportEntry] = []
        var texts: Int { entries.filter { if case .text = $0.payload { return true } else { return false } }.count }
        var images: Int { entries.count - texts }
        var tables: [String] = []
    }

    enum Failure: LocalizedError {
        case notSQLite, empty
        var errorDescription: String? {
            switch self {
            case .notSQLite: return "这不是 SQLite 数据库文件"
            case .empty: return "没有找到能导入的文本或图片"
            }
        }
    }

    /// `url` may be a database file (any extension) or a folder: a Pastory store, or any folder that has
    /// SQLite files somewhere inside (found by file header, up to three levels down) — all of them are read.
    static func scan(_ url: URL) throws -> Scan {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return try scanFile(url) }
        let own = url.appendingPathComponent("pastory.sqlite")
        if FileManager.default.fileExists(atPath: own.path) { return try scanFile(own) }
        var merged = Scan()
        var lastError: Error = Failure.notSQLite
        for f in sqliteFiles(under: url) {
            do {
                let s = try scanFile(f)
                merged.entries += s.entries
                merged.tables += s.tables.map { "\(f.lastPathComponent):\($0)" }
            } catch { lastError = error }
        }
        guard !merged.entries.isEmpty else { throw lastError }
        return merged
    }

    private static func sqliteFiles(under dir: URL, depth: Int = 3) -> [URL] {
        guard depth >= 0, let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for k in kids {
            if (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { out += sqliteFiles(under: k, depth: depth - 1); continue }
            if k.pathExtension.lowercased().hasSuffix("wal") || k.pathExtension.lowercased().hasSuffix("shm") { continue }
            if let h = FileHandle(forReadingAtPath: k.path), let head = try? h.read(upToCount: 16), head == Data("SQLite format 3\0".utf8) { out.append(k) }
        }
        return out
    }

    private static func scanFile(_ file: URL) throws -> Scan {
        // Work on a copy (with its WAL/SHM) so a database the other app has open is never touched.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: file.path + suffix)
            if FileManager.default.fileExists(atPath: side.path) { try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix)) }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { throw Failure.notSQLite }
        defer { sqlite3_close(db) }
        let tables = try query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").compactMap { $0["name"] as? String }
        guard !tables.isEmpty else { throw Failure.notSQLite }
        var scan = Scan()
        scan.tables = tables
        if tables.contains("items"), columns(db, "items").contains("content_hash") {
            scan.entries = try pastory(db, itemsDir: file.deletingLastPathComponent().appendingPathComponent("items"))
        } else {
            scan.entries = try generic(db, tables: tables)
        }
        guard !scan.entries.isEmpty else { throw Failure.empty }
        return scan
    }

    // MARK: Pastory → Pastory

    private static func pastory(_ db: OpaquePointer, itemsDir: URL) throws -> [ClipStore.ImportEntry] {
        var out: [ClipStore.ImportEntry] = []
        for row in try query(db, "SELECT id, kind, created_at, pinned, ext, title FROM items ORDER BY created_at DESC") {
            guard let id = row["id"] as? String, let kind = row["kind"] as? String, let ext = row["ext"] as? String else { continue }
            let url = itemsDir.appendingPathComponent("\(id).\(ext)")
            guard let data = try? Data(contentsOf: url) else { continue }
            let date = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? Date().timeIntervalSince1970)
            let pinned = ((row["pinned"] as? Int64) ?? 0) != 0
            let title = row["title"] as? String
            switch kind {
            case "text", "url":
                if let s = String(data: data, encoding: .utf8) { out.append(.init(payload: .text(s), createdAt: date, pinned: pinned, title: title)) }
            case "image":
                out.append(.init(payload: .image(data), createdAt: date, pinned: pinned, title: title))
            default: continue     // file lists point at the other machine's paths; recordings are not carried over
            }
        }
        return out
    }

    // MARK: Anything else

    private static func generic(_ db: OpaquePointer, tables: [String]) throws -> [ClipStore.ImportEntry] {
        var out: [ClipStore.ImportEntry] = []
        let skip: Set<String> = ["Z_METADATA", "Z_PRIMARYKEY", "Z_MODELCACHE"]
        // Tables that can lend a date to a child row (Core Data: ZHISTORYITEM for ZHISTORYITEMCONTENT).
        let parents: [(table: String, dateCol: String, pinCol: String?)] = tables.compactMap { t in
            let cols = columns(db, t)
            guard cols.contains("Z_PK"), let d = cols.first(where: isDateColumn) else { return nil }
            return (t, d, cols.first(where: isPinColumn))
        }
        var usedAsParent = Set<String>()
        // Content tables first; a table that turned out to be somebody's parent holds titles and metadata, not payloads.
        let ordered = tables.filter { !skip.contains($0) }.sorted { a, b in
            let pa = parents.contains { $0.table == a }, pb = parents.contains { $0.table == b }
            return !pa && pb
        }
        for t in ordered where !usedAsParent.contains(t) {
            let cols = columns(db, t)
            let dateCol = cols.first(where: isDateColumn)
            let pinCol = cols.first(where: isPinColumn)
            let typeCol = cols.first { let n = $0.lowercased(); return n.contains("type") || n.contains("uti") || n == "kind" }
            // Which integer column points at a parent row that has the date?
            var join: (col: String, parent: (table: String, dateCol: String, pinCol: String?))?
            if dateCol == nil {
                let total = (try? scalar(db, "SELECT COUNT(*) FROM \"\(t)\"")) ?? 0
                if total > 0 {
                    outer: for c in cols where !["Z_PK", "Z_ENT", "Z_OPT"].contains(c) {
                        for p in parents where p.table != t {
                            let hit = (try? scalar(db, "SELECT COUNT(*) FROM \"\(t)\" WHERE \"\(c)\" IN (SELECT Z_PK FROM \"\(p.table)\")")) ?? 0
                            if hit * 2 > total { join = (c, p); break outer }
                        }
                    }
                }
            }
            var sql = "SELECT c.* "
            if let join { sql += ", p.\"\(join.parent.dateCol)\" AS __pdate" + (join.parent.pinCol.map { ", p.\"\($0)\" AS __ppin" } ?? "") }
            sql += " FROM \"\(t)\" c"
            if let join { sql += " LEFT JOIN \"\(join.parent.table)\" p ON c.\"\(join.col)\" = p.Z_PK" }
            sql += " LIMIT 50000"
            guard let rows = try? query(db, sql) else { continue }
            // One entry per source item: rows sharing a parent are the same clip in several flavours
            // (plain text + rtf + html, png + tiff). Keep one image, else the longest plain text.
            struct Candidate { var text: String?; var image: Data?; var pngImage = false; var date: Date; var pinned: Bool }
            var groups: [Int64: Candidate] = [:]
            var order: [Int64] = []
            for (i, row) in rows.enumerated() {
                let hint = (typeCol.flatMap { row[$0] as? String } ?? "").lowercased()
                if hint.contains("rtf") || hint.contains("html") || hint.contains("file-url") || hint.hasPrefix("dyn.") || hint.contains("filename") { continue }
                let date = (dateCol.flatMap { row[$0] }).flatMap(asDate) ?? row["__pdate"].flatMap(asDate) ?? Date()
                let pinned = truthy(pinCol.flatMap { row[$0] }) || truthy(row["__ppin"])
                var best: String?
                var image: Data?
                for c in cols where c != typeCol && !isDateColumn(c) {
                    let lower = c.lowercased()
                    if lower.hasSuffix("id") || lower == "uuid" || lower.contains("bundle") || lower.contains("source") || lower.contains("app")
                        || lower.contains("title") || lower.contains("name") || lower.contains("label") { continue }
                    switch row[c] {
                    case let s as String:
                        if s.count > (best?.count ?? 0) { best = s }
                    case let d as Data:
                        if let png = pngIfImage(d) { image = png }
                        else if hint.isEmpty || hint.contains("text") || hint.contains("utf8") || hint.contains("string") || hint.contains("url"),
                                let s = String(data: d, encoding: .utf8), !s.isEmpty, s.count > (best?.count ?? 0) { best = s }
                    default: continue
                    }
                }
                guard image != nil || best != nil else { continue }
                let key: Int64 = join.flatMap { row[$0.col] as? Int64 } ?? Int64(-1 - i)
                var g = groups[key] ?? { order.append(key); return Candidate(date: date, pinned: pinned) }()
                if let image, !g.pngImage { g.image = image; g.pngImage = hint.contains("png") }
                if let best, best.count > (g.text?.count ?? 0) { g.text = best }
                g.pinned = g.pinned || pinned
                groups[key] = g
            }
            for key in order {
                guard let g = groups[key] else { continue }
                if let image = g.image { out.append(.init(payload: .image(image), createdAt: g.date, pinned: g.pinned, title: nil)) }
                else if let t = g.text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.count <= 200_000 {
                    out.append(.init(payload: .text(t), createdAt: g.date, pinned: g.pinned, title: nil))
                }
            }
            if let join { usedAsParent.insert(join.parent.table) }
        }
        return out
    }

    // MARK: Heuristics

    private static func isDateColumn(_ c: String) -> Bool {
        let n = c.lowercased()
        return n.contains("date") || n.contains("time") || n.contains("created") || n.contains("copied") || n.hasSuffix("_at") || n.hasSuffix("at") && n.count > 2 && n != "format"
    }
    private static func isPinColumn(_ c: String) -> Bool {
        let n = c.lowercased()
        return n.contains("pin") || n.contains("favorite") || n.contains("favourite") || n.contains("starred")
    }
    private static func truthy(_ v: Any?) -> Bool {
        switch v {
        case let i as Int64: return i != 0
        case let d as Double: return d != 0
        case let s as String: return ["1", "true", "yes"].contains(s.lowercased()) || (!s.isEmpty && s != "0" && s.count < 40 && !s.contains(" "))
        default: return false
        }
    }
    /// Seconds since 1970, since 2001 (Core Data), or milliseconds; ISO-8601 text.
    private static func asDate(_ v: Any) -> Date? {
        var n: Double?
        switch v {
        case let d as Double: n = d
        case let i as Int64: n = Double(i)
        case let s as String:
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            n = Double(s)
        default: return nil
        }
        guard let x = n, x > 0 else { return nil }
        if x > 1e12 { return Date(timeIntervalSince1970: x / 1000) }
        if x > 1.2e9 { return Date(timeIntervalSince1970: x) }
        if x > 3e8 { return Date(timeIntervalSinceReferenceDate: x) }
        return nil
    }
    /// PNG / JPEG / TIFF / GIF / HEIC blobs → PNG data.
    private static func pngIfImage(_ d: Data) -> Data? {
        guard d.count > 16 else { return nil }
        let b = [UInt8](d.prefix(12))
        let png = b[0] == 0x89 && b[1] == 0x50
        let jpg = b[0] == 0xFF && b[1] == 0xD8
        let tiff = (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A)
        let gif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46
        let heic = b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70
        guard png || jpg || tiff || gif || heic else { return nil }
        if png { return d }
        guard let rep = NSBitmapImageRep(data: d) ?? NSImage(data: d)?.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: SQLite glue

    private static func columns(_ db: OpaquePointer, _ table: String) -> [String] {
        (try? query(db, "PRAGMA table_info(\"\(table)\")").compactMap { $0["name"] as? String }) ?? []
    }

    private static func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int {
        (try query(db, sql).first?.values.first as? Int64).map(Int.init) ?? 0
    }

    private static func query(_ db: OpaquePointer, _ sql: String) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "Pastory.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }
        let n = sqlite3_column_count(stmt)
        let names = (0..<n).map { String(cString: sqlite3_column_name(stmt, $0)) }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<n {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[names[Int(i)]] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: row[names[Int(i)]] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[names[Int(i)]] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    if let p = sqlite3_column_blob(stmt, i) { row[names[Int(i)]] = Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i))) }
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }
}
