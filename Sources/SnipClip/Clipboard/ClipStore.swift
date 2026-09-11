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
        let fm = FileManager.default
        let base: URL
        if let root {
            base = root
        } else {
            base = Self.defaultRoot
        }
        self.root = base
        itemsDir = base.appendingPathComponent("items", isDirectory: true)
        thumbsDir = base.appendingPathComponent("thumbs", isDirectory: true)
        shareDir = base.appendingPathComponent("share", isDirectory: true)
        _ = fm
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

    private func load() {
        do {
            let d = try ClipDB(url: dbURL)
            db = d
            var rows = try d.loadAll()
            // First run on a store from the JSON era: import, then retire the file.
            if rows.isEmpty, let data = try? Data(contentsOf: indexURL) {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                let legacy = (try? dec.decode([Failable<ClipItem>].self, from: data))?.compactMap(\.value) ?? []
                if !legacy.isEmpty {
                    try d.saveAll(legacy)
                    rows = legacy
                }
                try? FileManager.default.moveItem(at: indexURL, to: root.appendingPathComponent("index.migrated.json"))
            }
            items = rows
        } catch {
            items = []
            reportStorageFailure(error)
        }
    }

    /// True after a write failed (full disk, unplugged volume). Retention holds off until a save succeeds again.
    private(set) var lastSaveFailed = false
    private var warnedSaveFailure = false

    @discardableResult
    private func save() -> Bool {
        do {
            if db == nil { db = try ClipDB(url: dbURL) }
            try db?.saveAll(items)
            lastSaveFailed = false
            return true
        } catch {
            lastSaveFailed = true
            reportStorageFailure(error)
            return false
        }
    }

    private func reportStorageFailure(_ error: Error) {
        guard !warnedSaveFailure else { return }
        warnedSaveFailure = true
        let a = NSAlert()
        a.messageText = "Pastory 读写不了存储目录"
        a.informativeText = "\(root.path)\n\n\(error.localizedDescription)\n\n之后的记录、Pin、删除可能没有保存。检查磁盘空间。"
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
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
        if let dup = dedupe(hash: hash) { return dup }
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
        if let dup = dedupe(hash: hash) { return dup }
        guard let cg = Screenshotter.image(fromPNG: png) else { return nil }
        var item = ClipItem(id: UUID().uuidString, kind: .image, createdAt: Date(),
                            sourceBundleID: source.bundleID, sourceAppName: source.name,
                            snippet: "\(cg.width)×\(cg.height)", ocrText: ocrText, pinned: false,
                            ext: "png", hasRTF: false, pixelWidth: cg.width, pixelHeight: cg.height,
                            byteCount: png.count, duration: nil, title: nil, contentHash: hash)
        do { try png.write(to: payloadURL(item), options: .atomic) } catch { return nil }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 640), let td = Screenshotter.pngData(t) {
            try? td.write(to: thumbURL(item), options: .atomic)
        }
        prepend(item)
        if ocrText == nil, Preferences.shared.ocrImages {
            let id = item.id
            Task.detached(priority: .utility) {
                let text = try? OCR.recognize(cg)
                await MainActor.run { ClipStore.shared.setOCR(text, for: id) }
            }
        }
        item.ocrText = ocrText
        return item
    }

    @discardableResult
    func insertFiles(_ urls: [URL], source: Source) -> ClipItem? {
        let paths = urls.map(\.path)
        guard !paths.isEmpty, let data = try? JSONEncoder().encode(paths) else { return nil }
        let hash = stableHash(data)
        if let dup = dedupe(hash: hash) { return dup }
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
        if let poster, let t = Screenshotter.thumbnail(poster, maxPixels: 640), let td = Screenshotter.pngData(t) {
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
        save()
    }

    /// Edited image: new PNG + thumbnail, OCR again in the background. If the item is gone meanwhile, keep the work as a new one.
    func updateImage(_ id: String, png: Data) {
        guard let cg = Screenshotter.image(fromPNG: png) else { return }
        guard let i = items.firstIndex(where: { $0.id == id }) else { insertImage(png: png, source: CaptureCoordinator.source); return }
        do { try png.write(to: payloadURL(items[i]), options: .atomic) } catch { return }
        if let t = Screenshotter.thumbnail(cg, maxPixels: 640), let td = Screenshotter.pngData(t) {
            try? td.write(to: thumbURL(items[i]), options: .atomic)
        }
        thumbCache[id] = nil
        items[i].snippet = "\(cg.width)×\(cg.height)"
        items[i].pixelWidth = cg.width
        items[i].pixelHeight = cg.height
        items[i].byteCount = png.count
        items[i].contentHash = stableHash(png)
        save()
        if Preferences.shared.ocrImages {
            Task.detached(priority: .utility) {
                let text = try? OCR.recognize(cg)
                await MainActor.run { ClipStore.shared.setOCR(text, for: id) }
            }
        }
    }

    /// Same payload as the newest item → just bump it.
    private func dedupe(hash: Int) -> ClipItem? {
        guard let first = items.first, first.contentHash == hash else { return nil }
        bump(first.id)
        return items.first
    }

    private func prepend(_ item: ClipItem) {
        items.insert(item, at: 0)
        save()
        Retention.itemAdded()
    }

    // MARK: - Mutations

    func bump(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), i != 0 else { return }
        var item = items.remove(at: i)
        item.createdAt = Date()
        items.insert(item, at: 0)
        save()
    }

    func togglePin(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    /// Self-test only.
    func debugSetDate(_ date: Date, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].createdAt = date
        save()
    }

    func setTitle(_ title: String?, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        items[i].title = t.isEmpty ? nil : t
        save()
    }

    func setOCR(_ text: String?, for id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].ocrText = text
        save()
    }

    func remove(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        deleteFiles(item)
        save()
    }

    func removeAll(where pred: (ClipItem) -> Bool) {
        let gone = items.filter(pred)
        guard !gone.isEmpty else { return }
        items.removeAll(where: pred)
        gone.forEach(deleteFiles)
        save()
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
