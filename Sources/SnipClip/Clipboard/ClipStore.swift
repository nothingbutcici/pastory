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
///   thumbs/<id>.png  shelf thumbnail for images
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

    /// The real location — unless SNIPCLIP_STORE is set, in which case that sandbox is "default" too,
    /// so self-tests (relocate back to default included) can never touch the user's data.
    static var defaultRoot: URL {
        if let env = ProcessInfo.processInfo.environment["SNIPCLIP_STORE"], !env.isEmpty {
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

    private func write(_ op: (ClipDB) throws -> Void) -> Bool {
        guard !loadFailed, let db else { lastSaveFailed = true; return false }    // never write over a table we could not read
        do {
            try op(db)
            let recovered = lastSaveFailed
            lastSaveFailed = false
            if recovered { Retention.reschedule() }
            return true
        } catch {
            lastSaveFailed = true
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
            a.messageText = "Pastory 读写不了存储目录"
            a.informativeText = "\(path)\n\n\(msg)\n\n在修好之前不会写入任何改动，也不会清理。检查磁盘空间后重新打开 Pastory。"
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    func payloadURL(_ item: ClipItem) -> URL { itemsDir.appendingPathComponent(item.fileName) }
    func rtfURL(_ item: ClipItem) -> URL { itemsDir.appendingPathComponent("\(item.id).rtf") }
    func thumbURL(_ item: ClipItem) -> URL { thumbsDir.appendingPathComponent("\(item.id).png") }

    /// A human-named file for the pasteboard ("Rec 2026-09-11 16.10.23.mp4"), kept under share/<id>/ so it
    /// can always be found and removed with the item. Hard link when the volume allows, copy otherwise.
    func shareURL(_ item: ClipItem) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let prefix = item.kind == .video ? "Rec" : (item.kind == .image ? "Snip" : "Clip")
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
        var kind = ClipKind.text
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           let s = url.scheme, ["http", "https"].contains(s), !text.contains("\n") { kind = .url }
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
        let item = ClipItem(id: UUID().uuidString, kind: .image, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: "\(cg.width)×\(cg.height)", ocrText: ocrText, pinned: false,
                            ext: "png", hasRTF: false, pixelWidth: cg.width, pixelHeight: cg.height,
                            byteCount: png.count, duration: nil, title: nil, contentHash: hash)
        do { try png.write(to: payloadURL(item), options: .atomic) } catch { return nil }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 1200), let td = Screenshotter.pngData(t) {
            try? td.write(to: thumbURL(item), options: .atomic)
        }
        prepend(item)
        if ocrText == nil, Preferences.shared.ocrImages {
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
        let snippet = names.count <= 3 ? names.joined(separator: "\n") : names.prefix(3).joined(separator: "\n") + "\n… 共 \(names.count) 项"
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
                            snippet: "\(ext.uppercased()) · \(secs) 秒\(dims)", ocrText: nil, pinned: false,
                            ext: ext, hasRTF: false, pixelWidth: poster?.width, pixelHeight: poster?.height,
                            byteCount: size, duration: duration, title: nil, contentHash: Int(truncatingIfNeeded: UInt64.random(in: 0...UInt64.max)))
        do { try FileManager.default.moveItem(at: tempFile, to: payloadURL(item)) } catch { return nil }
        if let poster, let t = Screenshotter.thumbnail(poster, maxPixels: 1200), let td = Screenshotter.pngData(t) {
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
        items[i].snippet = ClipItem.snippet(ofText: text)
        items[i].byteCount = data.count
        items[i].contentHash = stableHash(data)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        items[i].kind = (URL(string: t).flatMap(\.scheme).map { ["http", "https"].contains($0) } ?? false) && !t.contains("\n") ? .url : .text
        persist(items[i])
    }

    /// Edited image: new PNG + thumbnail, OCR again in the background. If the item is gone meanwhile, keep the work as a new one.
    func updateImage(_ id: String, png: Data) {
        guard let cg = Screenshotter.image(fromPNG: png) else { return }
        guard let i = items.firstIndex(where: { $0.id == id }) else { insertImage(png: png, source: CaptureCoordinator.source); return }
        do { try png.write(to: payloadURL(items[i]), options: .atomic) } catch { return }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 1200), let td = Screenshotter.pngData(t) {
            try? td.write(to: thumbURL(items[i]), options: .atomic)
        }
        thumbCache[id] = nil
        items[i].snippet = "\(cg.width)×\(cg.height)"
        items[i].pixelWidth = cg.width
        items[i].pixelHeight = cg.height
        items[i].byteCount = png.count
        items[i].contentHash = stableHash(png)
        persist(items[i])
        if Preferences.shared.ocrImages {
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

    struct ImportEntry {
        enum Payload { case text(String), image(Data) }
        var payload: Payload
        var createdAt: Date
        var pinned: Bool
        var title: String?
    }

    /// Bulk insert from another store. Skips anything whose payload is already here (or repeated in the batch)
    /// and saves once. Imported history always sorts behind everything Pastory captured itself: the batch keeps its
    /// own internal order, shifted back so its newest entry is older than our oldest item. Returns how many were added.
    func importEntries(_ entries: [ImportEntry]) -> Int {
        var entries = entries.sorted { $0.createdAt > $1.createdAt }
        if let oldestOwn = items.map(\.createdAt).min(), let newestImport = entries.first?.createdAt {
            let shift = newestImport.timeIntervalSince(oldestOwn) + 1
            if shift > 0 { for i in entries.indices { entries[i].createdAt.addTimeInterval(-shift) } }
        }
        var seen = Set(items.map(\.contentHash))
        let source = Source(bundleID: nil, name: "导入")
        var added: [ClipItem] = []
        for e in entries {
            switch e.payload {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let data = Data(text.utf8)
                guard !trimmed.isEmpty, data.count <= Self.maxTextBytes else { continue }
                let hash = stableHash(data)
                guard seen.insert(hash).inserted else { continue }
                var kind = ClipKind.text
                if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s), !text.contains("\n") { kind = .url }
                let item = ClipItem(id: UUID().uuidString, kind: kind, createdAt: e.createdAt,
                                    sourceBundleID: source.bundleID, sourceAppName: source.name,
                                    snippet: ClipItem.snippet(ofText: text), ocrText: nil, pinned: e.pinned,
                                    ext: "txt", hasRTF: false, pixelWidth: nil, pixelHeight: nil,
                                    byteCount: data.count, duration: nil, title: e.title, contentHash: hash)
                guard (try? data.write(to: payloadURL(item), options: .atomic)) != nil else { continue }
                added.append(item)
            case .image(let png):
                let hash = stableHash(png)
                guard seen.insert(hash).inserted, let cg = Screenshotter.image(fromPNG: png) else { continue }
                let item = ClipItem(id: UUID().uuidString, kind: .image, createdAt: e.createdAt,
                                    sourceBundleID: source.bundleID, sourceAppName: source.name,
                                    snippet: "\(cg.width)×\(cg.height)", ocrText: nil, pinned: e.pinned,
                                    ext: "png", hasRTF: false, pixelWidth: cg.width, pixelHeight: cg.height,
                                    byteCount: png.count, duration: nil, title: e.title, contentHash: hash)
                guard (try? png.write(to: payloadURL(item), options: .atomic)) != nil else { continue }
                if let t = Screenshotter.thumbnail(cg, maxPixels: 1200), let td = Screenshotter.pngData(t) {
                    try? td.write(to: thumbURL(item), options: .atomic)
                }
                added.append(item)
            }
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
        items.insert(item, at: 0)
        persist(item)
    }

    func togglePin(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
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
        persist(items[i])
    }

    /// Only applies if the item still holds the image the OCR ran on.
    func setOCR(_ text: String?, for id: String, ifHash hash: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].contentHash == hash else { return }
        items[i].ocrText = text
        persist(items[i])
    }

    func remove(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        guard unpersist(item.id) else { items.insert(item, at: i); return }    // index first; files only once the index agrees
        deleteFiles(item)
    }

    func removeAll(where pred: (ClipItem) -> Bool) {
        let gone = items.filter(pred)
        guard !gone.isEmpty else { return }
        let before = items
        items.removeAll(where: pred)
        guard save() else { items = before; return }
        gone.forEach(deleteFiles)
    }

    private func deleteFiles(_ item: ClipItem) {
        let fm = FileManager.default
        for u in [payloadURL(item), rtfURL(item), thumbURL(item), shareDir.appendingPathComponent(item.id)] { try? fm.removeItem(at: u) }
        thumbCache[item.id] = nil
    }

    // MARK: - Read

    func text(of item: ClipItem) -> String? {
        guard item.kind == .text || item.kind == .url else { return nil }
        return try? String(contentsOf: payloadURL(item), encoding: .utf8)
    }
    func rtf(of item: ClipItem) -> Data? { item.hasRTF ? try? Data(contentsOf: rtfURL(item)) : nil }
    func png(of item: ClipItem) -> Data? { item.kind == .image ? try? Data(contentsOf: payloadURL(item)) : nil }
    func fileURLs(of item: ClipItem) -> [URL] {
        guard item.kind == .files, let data = try? Data(contentsOf: payloadURL(item)),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }
    func thumbnail(of item: ClipItem) -> NSImage? {
        if let t = thumbCache[item.id] { return t }
        guard item.kind == .image || item.kind == .video, let img = NSImage(contentsOf: thumbURL(item)) else { return nil }
        if thumbCache.count > 300 { thumbCache.removeAll() }      // a full scroll through a big library must not pin everything in memory
        thumbCache[item.id] = img
        return img
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
