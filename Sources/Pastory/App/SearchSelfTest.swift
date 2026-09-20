import AppKit

enum SearchSelfTest {
    @MainActor
    static func run() async -> Bool {
        var ok = true
        func check(_ label: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(label)")
            ok = condition && ok
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipStore(root: root)
        let source = ClipStore.Source(bundleID: nil, name: "Search Fixture")
        guard let first = store.insertText(String(repeating: "prefix ", count: 100) + "TailNeedle 中文 Caf\u{65}\u{301} 👍🏽 👨‍👩‍👧\r\nlast", rtf: nil, source: source),
              let second = store.insertText("second result", rtf: nil, source: source) else { return false }
        store.setTitle("Fixture Title", for: second.id)
        let directory = root.appendingPathComponent("items")
        let index = ClipSearchIndex()
        do {
            var emojiHits = 0
            for query in ["tailneedle", "中文", "CAFÉ", "e\u{301}", "👍", "👩", "\n", "last", "fixture title", "search fixture", "missing"] {
                // Reference semantics: a literal search over the lower-cased, precomposed full text.
                let normalized = query.trimmingCharacters(in: .whitespaces).lowercased().precomposedStringWithCanonicalMapping
                let expected = Set(store.items.filter { item in
                    let text = [store.text(of: item) ?? item.snippet, item.ocrText ?? "", item.sourceAppName ?? "", item.title ?? ""]
                        .joined(separator: "\n").lowercased().precomposedStringWithCanonicalMapping as NSString
                    return text.range(of: normalized, options: .literal).location != NSNotFound
                }.map(\.id))
                let actual = try await index.search(query, items: store.items, directory: directory)
                check("full-text match for \(query.debugDescription)", actual == expected)
                if ["👍", "👩"].contains(query), actual.contains(first.id) { emojiHits += 1 }
            }
            check("a base emoji finds its skin-tone and family variants", emojiHits == 2)
            let reads = await index.payloadReadCount
            check("repeated queries load each payload only once", reads == 2)
            var changed = store.items
            for i in changed.indices {
                changed[i].pinned.toggle()
                changed[i].createdAt = Date()
                changed[i].modifiedAt = Date()
            }
            _ = try await index.search("tailneedle", items: changed, directory: directory)
            let readsAfterMetadata = await index.payloadReadCount
            check("pinning and copying reuse the full-text cache", readsAfterMetadata == reads)
            store.updateText(first.id, text: "replacement content")
            let oldMatches = try await index.search("tailneedle", items: store.items, directory: directory)
            let newMatches = try await index.search("replacement", items: store.items, directory: directory)
            check("editing invalidates the old payload", oldMatches.isEmpty && newMatches == [first.id])
            store.setTitle("Renamed", for: second.id)
            let renamed = try await index.search("renamed", items: store.items, directory: directory)
            let oldTitle = try await index.search("fixture title", items: store.items, directory: directory)
            check("renaming updates searchable metadata", renamed == [second.id] && oldTitle.isEmpty)
            let image = ClipItem(id: "ocr-fixture", kind: .image, createdAt: Date(), sourceBundleID: nil, sourceAppName: nil,
                                 snippet: "640×480", ocrText: "recognized words", pinned: false, ext: "png", hasRTF: false,
                                 pixelWidth: 640, pixelHeight: 480, byteCount: 0, duration: nil, title: nil, contentHash: 1)
            let beforeOCR = await index.payloadReadCount
            let ocrMatches = try await index.search("recognized", items: store.items + [image], directory: directory)
            let afterOCR = await index.payloadReadCount
            check("OCR search never reads image payloads", ocrMatches == [image.id] && beforeOCR == afterOCR)
            var changedOCR = image
            changedOCR.ocrText = "updated OCR"
            let updatedOCR = try await index.search("updated ocr", items: store.items + [changedOCR], directory: directory)
            check("completed OCR invalidates cached metadata", updatedOCR == [image.id])
            let cancelled = Task { try await index.search("replacement", items: store.items, directory: directory) }
            cancelled.cancel()
            do { _ = try await cancelled.value; check("cancellation stops obsolete work", false) }
            catch is CancellationError { check("cancellation stops obsolete work", true) }

            let model = ShelfModel(store: store)
            model.reset()
            await model.updateSearch()
            model.query = "replacement"
            check("pending queries cannot paste a stale selected item", model.isSearching && model.selectedItem == nil)      // the previous list stays visible; acting on it is what is blocked
            await model.updateSearch()
            check("results select the first matching item", !model.isSearching && model.selectedItem?.id == first.id)
            let beforeFocus = model.items
            model.focusSearch += 1
            check("focusing search keeps completed results", !model.isSearching && model.items == beforeFocus)
            model.query = "missing"
            let obsolete = Task { await model.updateSearch() }
            await Task.yield()
            model.query = "second"
            obsolete.cancel()
            await model.updateSearch()
            await obsolete.value
            check("rapid typing publishes only the latest results", model.items.map(\.id) == [second.id])
            model.filter = .images
            check("category filters reuse matches and clear invalid selection", model.items.isEmpty && model.selectedItem == nil && !model.isSearching)
            model.filter = .text
            check("returning to text restores the matching selection", model.selectedItem?.id == second.id)
            store.remove(second.id)
            check("deleted items disappear before the next search finishes", model.items.isEmpty && model.selectedItem == nil)
            await model.updateSearch()
            check("deleted items stay absent from search", model.items.isEmpty && !model.isSearching)
            model.query = "   "
            check("clearing search shows history immediately", !model.isSearching && model.items.map(\.id) == [first.id])
            model.filter = .all
            check("filter counts update after deletion", model.counts[.all] == 1 && model.counts[.text] == 1)

            // A temporarily missing payload falls back to its snippet, then is retried.
            let path = store.payloadURL(store.items[0])
            try FileManager.default.removeItem(at: path)
            let recovering = ClipSearchIndex()
            _ = try await recovering.search("replacement", items: store.items, directory: directory)
            try "restored content".write(to: path, atomically: true, encoding: .utf8)
            let restored = try await recovering.search("restored", items: store.items, directory: directory)
            check("missing payloads are retried instead of caching a permanent miss", restored == [first.id])
        } catch {
            print("FAIL search self-test: \(error)")
            return false
        }
        return ok
    }
}
