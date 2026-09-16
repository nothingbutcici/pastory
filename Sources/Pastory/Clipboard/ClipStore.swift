import AppKit
import CryptoKit
import Observation

/// Stable across launches (Swift's `hashValue` is randomly seeded per process).
func stableHash(_ data: Data) -> Int {
    let digest = SHA256.hash(data: data)
    return digest.withUnsafeBytes { Int(truncatingIfNeeded: $0.load(as: UInt64.self)) }
}

/// ~/Library/Application Support/Pastory/
///   pastory.sqlite   the index (SQLite, WAL); an old index.json is imported once and renamed
///   items/<id>.<ext> payload (txt / png / json list of paths); <id>.rtf alongside when rich text
///   thumbs/<id>.heic shelf thumbnail for images and recordings (older stores: .png)
@MainActor
@Observable
final class ClipStore {
    static let shared = ClipStore()

    private(set) var items: [ClipItem] = []
    private(set) var root: URL
    private var itemsDir: URL
    private var thumbsDir: URL
    private var shareDir: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }     // legacy, imported once
    private var dbURL: URL { root.appendingPathComponent("pastory.sqlite") }
    private var db: ClipDB?

    /// The real location — unless PASTORY_STORE is set, in which case that sandbox is "default" too,
    /// so self-tests (relocate back to default included) can never touch the user's data.
    static var defaultRoot: URL {
        if let env = Sandbox.store {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let new = support.appendingPathComponent("Pastory", isDirectory: true)
        let old = support.appendingPathComponent("Snip Clip", isDirectory: true)
        // One-time rename from the code-name folder; never leave two stores around.
        if !FileManager.default.fileExists(atPath: new.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: new)
        }
        return new
    }
    private var thumbCache: [String: NSImage] = [:]
    static let maxTextBytes = 20 * 1024 * 1024

    init(root: URL? = nil) {
        let base = root ?? Self.defaultRoot
        self.root = base
        itemsDir = base.appendingPathComponent("items", isDirectory: true)
        thumbsDir = base.appendingPathComponent("thumbs", isDirectory: true)
        shareDir = base.appendingPathComponent("share", isDirectory: true)
        ensureDirs()
        load()
    }

    private func ensureDirs() {
        let fm = FileManager.default
        for d in [root, itemsDir, thumbsDir, shareDir] where !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    // MARK: - Persistence

    /// One bad row must not take the whole index with it.
    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// Set when the index could not be read at launch. While it is set nothing is ever written back,
    /// because a replace-all save from an empty in-memory list would wipe the table.
    private(set) var loadFailed = false

    private func load() {
        do {
            let d = try ClipDB(url: dbURL)
            var rows = try d.loadAll()
            // First run on a store from the JSON era: import, then retire the file.
            if rows.isEmpty, let data = try? Data(contentsOf: indexURL) {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                let legacy = (try? dec.decode([Failable<ClipItem>].self, from: data))?.compactMap(\.value) ?? []
                if !legacy.isEmpty {
                    try d.saveAll(legacy)
                    rows = legacy
                }
                let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
                try? FileManager.default.moveItem(at: indexURL, to: root.appendingPathComponent("index.migrated.\(f.string(from: Date())).json"))
            }
            db = d
            items = rows
            buried = (try? d.tombstoneHashes()) ?? []
            loadFailed = false
        } catch {
            db = nil
            items = []
            loadFailed = true
            lastSaveFailed = true
            reportStorageFailure(error)
        }
    }

    /// True after a write failed (full disk, unplugged volume). Retention holds off until a save succeeds again.
    private(set) var lastSaveFailed = false
    private var warnedSaveFailure = false

    /// Whole table (bulk changes: clear, import, migration). `persist` / `unpersist` are the one-row versions.
    @discardableResult
    private func save() -> Bool { write { try $0.saveAll(items) } }
    @discardableResult
    private func persist(_ item: ClipItem) -> Bool { write { try $0.upsert(item) } }
    @discardableResult
    private func unpersist(_ id: String) -> Bool { write { try $0.delete(id) } }

    /// Set when a one-row write failed: the table no longer matches memory, so the next write rewrites the whole table.
    private var needsFullSave = false

    /// Bumped on every successful write; views cache derived lists against it.
    private(set) var version = 0

    private func write(_ op: (ClipDB) throws -> Void) -> Bool {
        guard !loadFailed, let db else { lastSaveFailed = true; return false }    // never write over a table we could not read
        version += 1
        do {
            if needsFullSave { try db.saveAll(items); needsFullSave = false } else { try op(db) }
            let recovered = lastSaveFailed
            lastSaveFailed = false
            if recovered { Retention.reschedule() }
            return true
        } catch {
            lastSaveFailed = true
            needsFullSave = true
            reportStorageFailure(error)
            return false
        }
    }

    /// Shown once, and never from inside the singleton's initializer (a modal there can re-enter `shared` and deadlock).
    private func reportStorageFailure(_ error: Error) {
        guard !warnedSaveFailure else { return }
        warnedSaveFailure = true
        let path = root.path, msg = error.localizedDescription
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "Pastory 读写不了存储目录".l
            a.informativeText = path + "\n\n" + msg + "\n\n" + "在修好之前不会写入任何改动，也不会清理。检查磁盘空间后重新打开 Pastory。".l
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    func payloadURL(_ item: ClipItem) -> URL { itemsDir.appendingPathComponent(item.fileName) }
    func rtfURL(_ item: ClipItem) -> URL { itemsDir.appendingPathComponent("\(item.id).rtf") }
    /// Thumbnails are display-only, so they are lossy HEIC (≈ a quarter of a PNG). Older stores still have .png ones.
    func thumbURL(_ item: ClipItem) -> URL {
        let heic = thumbsDir.appendingPathComponent("\(item.id).heic")
        if FileManager.default.fileExists(atPath: heic.path) { return heic }
        let png = thumbsDir.appendingPathComponent("\(item.id).png")
        return FileManager.default.fileExists(atPath: png.path) ? png : heic
    }
    private func thumbData(_ t: CGImage) -> Data? { Screenshotter.heicData(t, quality: 0.8) ?? Screenshotter.pngData(t) }

    /// A human-named file for the pasteboard ("Rec 2026-09-11 16.10.23.mp4"), kept under share/<id>/ so it
    /// can always be found and removed with the item. Hard link when the volume allows, copy otherwise.
    func shareURL(_ item: ClipItem) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let prefix = "Rec"          // only recordings are shared as files
        let dir = shareDir.appendingPathComponent(item.id, isDirectory: true)
        let url = dir.appendingPathComponent("\(prefix) \(f.string(from: item.createdAt)).\(item.ext)")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? fm.linkItem(at: payloadURL(item), to: url)) == nil {
                try? fm.copyItem(at: payloadURL(item), to: url)
            }
        }
        return url
    }

    // MARK: - Insert

    struct Source {
        var bundleID: String?
        var name: String?
        static var frontmost: Source {
            let app = NSWorkspace.shared.frontmostApplication
            return Source(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        }
    }

    @discardableResult
    func insertText(_ text: String, rtf: Data?, source: Source) -> ClipItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let data = Data(text.utf8)
        guard data.count <= Self.maxTextBytes else { return nil }
        let hash = stableHash(data)
        if let dup = dedupe(hash: hash, kinds: [.text, .url]) { return dup }
        let kind: ClipKind = ClipItem.isURLText(text) ? .url : .text
        let item = ClipItem(id: UUID().uuidString, kind: kind, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: ClipItem.snippet(ofText: text), ocrText: nil, pinned: false,
                            ext: "txt", hasRTF: rtf != nil, pixelWidth: nil, pixelHeight: nil,
                            byteCount: data.count, duration: nil, title: nil, contentHash: hash)
        do {
            try data.write(to: payloadURL(item), options: .atomic)
            if let rtf { try rtf.write(to: rtfURL(item), options: .atomic) }
        } catch { return nil }
        prepend(item)
        return item
    }

    @discardableResult
    func insertImage(png: Data, source: Source, ocrText: String? = nil) -> ClipItem? {
        let hash = stableHash(png)
        if let dup = dedupe(hash: hash, kinds: [.image]) { return dup }
        guard let cg = Screenshotter.image(fromPNG: png) else { return nil }
        let (stored, ext) = Screenshotter.storedImage(png: png, cg: cg)      // hash stays that of the PNG, so dedupe works either way
        let item = ClipItem(id: UUID().uuidString, kind: .image, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: "\(cg.width)×\(cg.height)", ocrText: ocrText, pinned: false,
                            ext: ext, hasRTF: false, pixelWidth: cg.width, pixelHeight: cg.height,
                            byteCount: stored.count, duration: nil, title: nil, contentHash: hash)
        do { try stored.write(to: payloadURL(item), options: .atomic) } catch { return nil }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 900), let td = thumbData(t) {
            try? td.write(to: thumbURL(item), options: .atomic)
        }
        prepend(item)
        if ocrText == nil {
            let id = item.id, expected = hash
            Task.detached(priority: .utility) {
                let text = try? OCR.recognize(cg)
                await MainActor.run { ClipStore.shared.setOCR(text, for: id, ifHash: expected) }
            }
        }
        return item
    }

    @discardableResult
    func insertFiles(_ urls: [URL], source: Source) -> ClipItem? {
        let paths = urls.map(\.path)
        guard !paths.isEmpty, let data = try? JSONEncoder().encode(paths) else { return nil }
        let hash = stableHash(data)
        if let dup = dedupe(hash: hash, kinds: [.files]) { return dup }
        let names = urls.map(\.lastPathComponent)
        let snippet = names.count <= 3 ? names.joined(separator: "\n") : names.prefix(3).joined(separator: "\n") + "\n" + String(format: "… 共 %d 项".l, names.count)
        let item = ClipItem(id: UUID().uuidString, kind: .files, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: snippet, ocrText: nil, pinned: false,
                            ext: "json", hasRTF: false, pixelWidth: nil, pixelHeight: nil,
                            byteCount: data.count, duration: nil, title: nil, contentHash: hash)
        do { try data.write(to: payloadURL(item), options: .atomic) } catch { return nil }
        prepend(item)
        return item
    }

    /// Move a finished recording (mp4 / gif) into the store.
    @discardableResult
    func insertVideo(tempFile: URL, poster: CGImage?, duration: Double, source: Source) -> ClipItem? {
        let ext = tempFile.pathExtension.lowercased()
        let size = (try? FileManager.default.attributesOfItem(atPath: tempFile.path)[.size] as? Int) ?? 0
        let secs = Int(duration.rounded())
        var dims = ""
        if let poster { dims = " · \(poster.width)×\(poster.height)" }
        let item = ClipItem(id: UUID().uuidString, kind: .video, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: String(format: "%@ · %d 秒%@".l, ext.uppercased(), secs, dims), ocrText: nil, pinned: false,
                            ext: ext, hasRTF: false, pixelWidth: poster?.width, pixelHeight: poster?.height,
                            byteCount: size, duration: duration, title: nil, contentHash: Int(truncatingIfNeeded: UInt64.random(in: 0...UInt64.max)))
        do { try FileManager.default.moveItem(at: tempFile, to: payloadURL(item)) } catch { return nil }
        if let poster, let t = Screenshotter.thumbnail(poster, maxPixels: 900), let td = thumbData(t) {
            try? td.write(to: thumbURL(item), options: .atomic)
        }
        prepend(item)
        return item
    }

    /// Edited text: rewrite the payload, keep id / pin / position. If the item is gone meanwhile, keep the work as a new one.
    func updateText(_ id: String, text: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { insertText(text, rtf: nil, source: CaptureCoordinator.source); return }
        let data = Data(text.utf8)
        do { try data.write(to: payloadURL(items[i]), options: .atomic) } catch { return }
        try? FileManager.default.removeItem(at: rtfURL(items[i]))
        items[i].hasRTF = false
        items[i].modifiedAt = Date()
        items[i].snippet = ClipItem.snippet(ofText: text)
        items[i].byteCount = data.count
        items[i].contentHash = stableHash(data)
        items[i].kind = ClipItem.isURLText(text) ? .url : .text
        persist(items[i])
    }

    /// Edited image: new PNG + thumbnail, OCR again in the background. If the item is gone meanwhile, keep the work as a new one.
    func updateImage(_ id: String, png: Data) {
        guard let cg = Screenshotter.image(fromPNG: png) else { return }
        guard let i = items.firstIndex(where: { $0.id == id }) else { insertImage(png: png, source: CaptureCoordinator.source); return }
        let (stored, ext) = Screenshotter.storedImage(png: png, cg: cg)
        let old = items[i]
        items[i].ext = ext
        do { try stored.write(to: payloadURL(items[i]), options: .atomic) } catch { items[i].ext = old.ext; return }
        if old.ext != ext { try? FileManager.default.removeItem(at: payloadURL(old)) }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 900), let td = thumbData(t) {
            try? td.write(to: thumbURL(items[i]), options: .atomic)
        }
        thumbCache[id] = nil
        thumbMissing.remove(id)
        items[i].modifiedAt = Date()
        items[i].snippet = "\(cg.width)×\(cg.height)"
        items[i].pixelWidth = cg.width
        items[i].pixelHeight = cg.height
        items[i].byteCount = stored.count
        items[i].contentHash = stableHash(png)
        persist(items[i])
        do {
            let expected = stableHash(png)
            Task.detached(priority: .utility) {
                let text = try? OCR.recognize(cg)
                await MainActor.run { ClipStore.shared.setOCR(text, for: id, ifHash: expected) }
            }
        }
    }

    /// Same payload anywhere in the history (same kind family) → bring that card to the front instead of making a twin;
    /// its title and pin come along. Paste does the same by checksum.
    private func dedupe(hash: Int, kinds: Set<ClipKind>) -> ClipItem? {
        guard let hit = items.first(where: { $0.contentHash == hash && kinds.contains($0.kind) }) else { return nil }
        bump(hit.id)
        return items.first
    }

    private func prepend(_ item: ClipItem) {
        items.insert(item, at: 0)
        persist(item)
        Retention.itemAdded()
    }

    // MARK: - Import

    /// Marker in `sourceAppName` for imported items (stored as-is in the DB; shown localized). Never rename.
    static let importSourceName = "导入"

    struct ImportEntry {
        enum Payload { case text(String), image(Data) }
        var payload: Payload
        var createdAt: Date
        var pinned: Bool
        var title: String?
    }

    /// Everything about an entry that can be computed away from the main thread: bytes to write, thumbnail, hash.
    struct PreparedEntry: @unchecked Sendable {
        var kind: ClipKind; var payload: Data; var ext: String; var thumb: Data?
        var snippet: String; var pixelWidth: Int?; var pixelHeight: Int?; var hash: Int
        var createdAt: Date; var pinned: Bool; var title: String?
    }

    /// Hashing, decoding, HEIC re-encoding and thumbnails for a whole batch — run this off the main actor.
    nonisolated static func prepareImport(_ entries: [ImportEntry], storeHEIC: Bool) -> [PreparedEntry] {
        var out: [PreparedEntry] = []
        for e in entries {
            switch e.payload {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let data = Data(text.utf8)
                guard !trimmed.isEmpty, data.count <= maxTextBytes else { continue }
                out.append(.init(kind: ClipItem.isURLText(text) ? .url : .text, payload: data, ext: "txt", thumb: nil,
                                 snippet: ClipItem.snippet(ofText: text), pixelWidth: nil, pixelHeight: nil, hash: stableHash(data),
                                 createdAt: e.createdAt, pinned: e.pinned, title: e.title))
            case .image(let png):
                guard let cg = Screenshotter.image(fromPNG: png) else { continue }
                let heic = storeHEIC ? Screenshotter.heicData(cg) : nil
                let thumb = Screenshotter.thumbnail(cg, maxPixels: 900).flatMap { Screenshotter.heicData($0, quality: 0.8) ?? Screenshotter.pngData($0) }
                out.append(.init(kind: .image, payload: heic ?? png, ext: heic == nil ? "png" : "heic", thumb: thumb,
                                 snippet: "\(cg.width)×\(cg.height)", pixelWidth: cg.width, pixelHeight: cg.height, hash: stableHash(png),
                                 createdAt: e.createdAt, pinned: e.pinned, title: e.title))
            }
        }
        return out
    }

    /// Bulk insert from another store. Skips anything whose payload is already here (or repeated in the batch)
    /// and saves once. Imported history always sorts behind everything Pastory captured itself: the batch keeps its
    /// own internal order, shifted back so its newest entry is older than our oldest item. Returns how many were added.
    func importEntries(_ entries: [ImportEntry]) -> Int {
        commitImport(Self.prepareImport(entries, storeHEIC: Preferences.shared.storesHEIC))
    }

    /// Main-actor half of an import: write files, build items, save once.
    func commitImport(_ prepared: [PreparedEntry]) -> Int {
        var entries = prepared.sorted { $0.createdAt > $1.createdAt }
        if let oldestOwn = items.map(\.createdAt).min(), let newestImport = entries.first?.createdAt {
            let shift = newestImport.timeIntervalSince(oldestOwn) + 1
            if shift > 0 { for i in entries.indices { entries[i].createdAt.addTimeInterval(-shift) } }
        }
        var seen = Set(items.map(\.contentHash)).union(buried)      // what you deleted here stays deleted
        let source = Source(bundleID: nil, name: Self.importSourceName)
        var added: [ClipItem] = []
        for e in entries {
            guard seen.insert(e.hash).inserted else { continue }
            let item = ClipItem(id: UUID().uuidString, kind: e.kind, createdAt: e.createdAt,
                                sourceBundleID: source.bundleID, sourceAppName: source.name,
                                snippet: e.snippet, ocrText: nil, pinned: e.pinned,
                                ext: e.ext, hasRTF: false, pixelWidth: e.pixelWidth, pixelHeight: e.pixelHeight,
                                byteCount: e.payload.count, duration: nil, title: e.title, contentHash: e.hash)
            guard (try? e.payload.write(to: payloadURL(item), options: .atomic)) != nil else { continue }
            if let t = e.thumb { try? t.write(to: thumbURL(item), options: .atomic) }
            added.append(item)
        }
        guard !added.isEmpty else { return 0 }
        items = (items + added).sorted { $0.createdAt > $1.createdAt }
        guard save() else {
            // Disk said no: take the files back out so nothing half-exists.
            let ids = Set(added.map(\.id))
            items.removeAll { ids.contains($0.id) }
            for a in added { try? FileManager.default.removeItem(at: payloadURL(a)); try? FileManager.default.removeItem(at: thumbURL(a)) }
            return 0
        }
        Retention.reschedule()
        return added.count
    }

    // MARK: - Mutations

    func bump(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), i != 0 else { return }
        var item = items.remove(at: i)
        item.createdAt = Date()
        item.modifiedAt = item.createdAt
        items.insert(item, at: 0)
        persist(item)
    }

    func togglePin(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        items[i].modifiedAt = Date()
        guard persist(items[i]) else { items[i].pinned.toggle(); return }      // UI must not claim a pin the disk does not have
        if !items[i].pinned { Retention.reschedule() }             // an un-pinned old item may be the next to expire
    }

    /// Self-test only.
    func debugSetDate(_ date: Date, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].createdAt = date
        persist(items[i])
    }

    func setTitle(_ title: String?, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        items[i].title = t.isEmpty ? nil : t
        items[i].modifiedAt = Date()
        persist(items[i])
    }

    /// Only applies if the item still holds the image the OCR ran on.
    func setOCR(_ text: String?, for id: String, ifHash hash: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].contentHash == hash else { return }
        items[i].ocrText = text
        items[i].modifiedAt = Date()
        persist(items[i])
    }

    func remove(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        guard unpersist(item.id) else { items.insert(item, at: i); return }    // index first; files only once the index agrees
        bury([item])
        deleteFiles(item)
    }

    func removeAll(where pred: (ClipItem) -> Bool) {
        let gone = items.filter(pred)
        guard !gone.isEmpty else { return }
        let before = items
        items.removeAll(where: pred)
        guard save() else { items = before; return }
        bury(gone)
        gone.forEach(deleteFiles)
    }

    /// Deleted is deleted: remember the id and content hash so an import (or, one day, a sync) cannot resurrect it.
    private func bury(_ gone: [ClipItem]) {
        guard let db, !gone.isEmpty else { return }
        try? db.addTombstones(gone)
        for g in gone { buried.insert(g.contentHash) }
    }
    /// Content hashes of deleted items, loaded with the index; consulted by `importEntries`.
    private var buried = Set<Int>()

    /// Tombstones older than this are forgotten; a fresh copy of the same content is a new item anyway.
    func purgeTombstones(olderThan days: Int = 30) {
        guard let db else { return }
        try? db.purgeTombstones(before: Date().addingTimeInterval(-Double(days) * 86400))
        buried = (try? db.tombstoneHashes()) ?? buried
    }

    private func deleteFiles(_ item: ClipItem) {
        let fm = FileManager.default
        for u in [payloadURL(item), rtfURL(item), thumbURL(item), shareDir.appendingPathComponent(item.id)] { try? fm.removeItem(at: u) }
        thumbCache[item.id] = nil
        thumbMissing.remove(item.id)
    }

    // MARK: - Read

    func text(of item: ClipItem) -> String? {
        guard item.kind == .text || item.kind == .url else { return nil }
        return try? String(contentsOf: payloadURL(item), encoding: .utf8)
    }
    func rtf(of item: ClipItem) -> Data? { item.hasRTF ? try? Data(contentsOf: rtfURL(item)) : nil }
    /// PNG bytes of an image item, whatever is on disk (HEIC-stored items are decoded and re-wrapped losslessly, same pixels, same color space).
    func png(of item: ClipItem) -> Data? {
        guard item.kind == .image, let data = try? Data(contentsOf: payloadURL(item)) else { return nil }
        if item.ext == "png" { return data }
        return Screenshotter.image(fromPNG: data).flatMap(Screenshotter.pngData)
    }
    func fileURLs(of item: ClipItem) -> [URL] {
        guard item.kind == .files, let data = try? Data(contentsOf: payloadURL(item)),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }
    /// Bumped when a thumbnail finishes decoding; cards that asked for one re-render.
    private(set) var thumbTick = 0
    private var thumbLoading = Set<String>()

    /// Cached thumbnail, or nil while it decodes in the background (the card shows a placeholder for a frame or two).
    func thumbnail(of item: ClipItem) -> NSImage? {
        _ = thumbTick
        if let t = thumbCache[item.id] { return t }
        guard item.kind == .image || item.kind == .video else { return nil }
        warmThumbnail(item)
        return nil
    }

    /// Self-tests wait on this before snapshotting the shelf.
    func isThumbnailCached(_ id: String) -> Bool { thumbCache[id] != nil }
    /// Decoding was tried and there is no usable file (no poster, thumb write failed): show a glyph, do not retry.
    private var thumbMissing = Set<String>()
    func thumbnailMissing(_ id: String) -> Bool { thumbMissing.contains(id) }
    private var thumbOrder: [String] = []

    /// Start decoding an item's thumbnail off the main thread; no-op when cached or already in flight.
    func warmThumbnail(_ item: ClipItem) {
        guard item.kind == .image || item.kind == .video, thumbCache[item.id] == nil, !thumbLoading.contains(item.id), !thumbMissing.contains(item.id) else { return }
        thumbLoading.insert(item.id)
        let url = thumbURL(item), id = item.id
        Task.detached(priority: .userInitiated) {
            let box = DecodedImage(url: url)
            await MainActor.run {
                let store = ClipStore.shared
                store.thumbLoading.remove(id)
                guard let image = box.image else { store.thumbMissing.insert(id); store.thumbTick += 1; return }
                if store.thumbCache.count > 100 {                                    // ~2 MB decoded each: drop the oldest third, not everything on screen
                    for old in store.thumbOrder.prefix(34) { store.thumbCache[old] = nil }
                    store.thumbOrder.removeFirst(min(34, store.thumbOrder.count))
                }
                store.thumbCache[id] = image
                store.thumbOrder.append(id)
                store.thumbTick += 1
            }
        }
    }

    // MARK: - Actions

    /// Put the item back on the pasteboard (the monitor then bumps it).
    func copyToPasteboard(_ item: ClipItem) {
        switch item.kind {
        case .text, .url:
            guard let s = text(of: item) else { return }
            PasteboardWriter.writeText(s, rtf: rtf(of: item), itemID: item.id)
        case .image:
            guard let png = png(of: item) else { return }
            PasteboardWriter.writeImage(png: png, itemID: item.id)
        case .files:
            PasteboardWriter.writeFiles(fileURLs(of: item), itemID: item.id)
        case .video:
            if item.ext == "gif", let data = try? Data(contentsOf: payloadURL(item)) {
                PasteboardWriter.writeGIF(data, itemID: item.id)
            } else {
                PasteboardWriter.writeFiles([shareURL(item)], itemID: item.id)
            }
        }
        bump(item.id)
    }
}

/// Decoded off the main thread, handed over once; NSImage itself is not Sendable, so the hand-off is explicit.
private struct DecodedImage: @unchecked Sendable {
    let image: NSImage?
    init(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { image = nil; return }
        image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
    }
}
