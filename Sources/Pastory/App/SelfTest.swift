import AppKit
import ScreenCaptureKit
import SwiftUI

/// `--selftest capture <out.png>` · `--selftest ocr [in.png]` · `--selftest clipboard <seconds>`
/// Set PASTORY_STORE=<dir> to keep test items out of the real store.
enum SelfTest {
    /// A file that exists in any checkout, for the file-list tests.
    static let sampleFile = Bundle.main.executableURL!.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Package.swift")
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Package.swift")
    @MainActor
    static func handleCommandLine() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return false }
        let cmd = args[i + 1]
        let rest = Array(args[(i + 2)...])
        // Anything that writes to a store must run inside PASTORY_STORE. Never against the user's data.
        let mutating: Set<String> = ["clipboard", "retention", "shelf", "settings", "editors", "import", "ingest", "tombstone", "heic", "pbfiles", "welcome"]
        if mutating.contains(cmd) {
            let env = Sandbox.store ?? ""
            // Nothing under Application Support counts as a sandbox, whatever the folder is called.
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath().path
            let target = URL(fileURLWithPath: env).resolvingSymlinksInPath().path
            if env.isEmpty || target.hasPrefix(support) {
                print("refusing: --selftest \(cmd) needs PASTORY_STORE pointing at a scratch folder (never the real store)")
                exit(2)
            }
        }
        Task { @MainActor in
            var ok = false
            switch cmd {
            case "capture": ok = await capture(out: rest.first ?? "pastory-capture.png")
            case "ocr": ok = ocr(path: rest.first)
            case "clipboard": ok = await clipboard(seconds: Int(rest.first ?? "10") ?? 10)
            case "shelf": ok = await renderShelf(out: rest.first ?? "pastory-shelf.png")
            case "settings":
                await seedStore()
                let model = ShelfPanelController.shared.model
                model.reset()
                model.showSettings = true
                let host = NSHostingView(rootView: ShelfView(model: model))
                host.frame = CGRect(x: 0, y: 0, width: 1600, height: 450)
                let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host
                w.isReleasedWhenClosed = false
                ok = snapshot(host, to: rest.first ?? "pastory-settings.png")
            case "preview":
                let mov = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-preview.mp4")
                try? FileManager.default.removeItem(at: mov)
                try? await SyntheticMovie.write(to: mov, size: CGSize(width: 1280, height: 720), seconds: 6, fps: 30)
                let w = RecordingPreviewWindow(movie: mov, duration: 6, pixelSize: CGSize(width: 1280, height: 720), near: CGRect(x: 200, y: 200, width: 640, height: 360))
                w.debugSeek(2.5)
                ok = w.debugContentView.map { snapshot($0, to: rest.first ?? "pastory-preview.png") } ?? false
            case "editors":
                await seedStore()
                let out = rest.first ?? "pastory-editor.png"
                var okAll = true
                if let t = ClipStore.shared.items.first(where: { $0.kind == .text }), let v = TextEditorWindow.debugView(t) {
                    okAll = snapshot(v, to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("text.png").path) && okAll
                }
                if let t = ClipStore.shared.items.first(where: { $0.kind == .text && $0.title == nil }), let v = TextEditorWindow.debugView(t) {
                    okAll = snapshot(v, to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("text-untitled.png").path) && okAll
                }
                if let im = ClipStore.shared.items.first(where: { $0.kind == .image }), let v = ImageEditorWindow.debugView(im) {
                    okAll = snapshot(v, to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("image.png").path) && okAll
                }
                ok = okAll
            case "download":
                // Exercise the updater's downloader for real: progress callbacks, completion, and the error wording.
                let dest = URL(fileURLWithPath: rest.count > 1 ? rest[1] : NSTemporaryDirectory() + "pastory-dl-test")
                try? FileManager.default.removeItem(at: dest)
                var ticks = 0
                do {
                    try await UpdateDownload().fetch(URL(string: rest.first ?? "")!, to: dest) { _, _ in ticks += 1 }
                    let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                    print("ok   \(size ?? 0) bytes, \(ticks) progress callbacks"); ok = true
                } catch { print("failed: \(Updater.describe(error)) [\((error as NSError).domain) \((error as NSError).code)]"); ok = false }
            case "pbtypes":
                // Read-only: what is on the general pasteboard right now (types + which of our skip markers are present).
                let pb = NSPasteboard.general
                let types = pb.types?.map(\.rawValue) ?? []
                print("changeCount \(pb.changeCount), \(types.count) types:")
                for t in types { print("  \(t)") }
                let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
                print("skip markers present: \(markers.filter { types.contains($0) })")
                print("source app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
                ok = true
            case "welcome":
                await seedStore()
                let model = ShelfPanelController.shared.model
                model.reset()
                model.showWelcome = true
                model.welcomeTried = ["shelf", "copy"]          // show both states of the checklist
                let host = NSHostingView(rootView: ShelfView(model: model))
                host.frame = CGRect(x: 0, y: 0, width: 1600, height: 540)
                let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host
                w.isReleasedWhenClosed = false
                ok = snapshot(host, to: rest.first ?? "pastory-welcome.png")
            case "updatewin":
                let w = UpdateProgressWindow(version: "1.0.3")
                w.update(done: 1_900_000, total: 4_860_000)
                ok = w.debugContentView.map { $0.frame = CGRect(x: 0, y: 0, width: 380, height: 150); $0.layoutSubtreeIfNeeded(); return snapshot($0, to: rest.first ?? "pastory-updatewin.png") } ?? false
            case "ocrpanel":
                ok = OCRPanelController.shared.debugView(sample: "Pastory 是一个截图工具\n所有复制过的内容都留在剪贴板里\nMade in 2026 · 中英混排 OK").map { snapshot($0, to: rest.first ?? "pastory-ocrpanel.png") } ?? false
            case "import":
                // Scan a foreign SQLite file (arg 1) and pull it into the sandbox store; prints what it found.
                do {
                    let scan = try Importer.scan(URL(fileURLWithPath: rest.first ?? ""))
                    print("scan: \(scan.texts) texts, \(scan.images) images from tables \(scan.tables)")
                    for e in scan.entries.prefix(12) {
                        switch e.payload {
                        case .text(let t): print("  text  \(e.createdAt) pin=\(e.pinned) \(t.prefix(40).replacingOccurrences(of: "\n", with: "⏎"))")
                        case .image(let d): print("  image \(e.createdAt) pin=\(e.pinned) \(d.count) bytes")
                        }
                    }
                    let n = ClipStore.shared.importEntries(scan.entries)
                    print("imported \(n); store now \(ClipStore.shared.items.count)")
                    ok = n > 0
                } catch { print("import failed: \(error.localizedDescription)"); ok = false }
            case "retention": ok = retention()
            case "gif": ok = await gif()
            case "writer":
                // Feed 60 synthetic Retina-sized frames through the recorder's writer (H.264 and HEVC): settings valid,
                // file plays back with the right duration, bitrate lands where the formula says.
                var okAll = true
                // UI-like content: a page of "text" (fine random pattern) that scrolls 12 px per frame, on a flat ground.
                let W = 3200, H = 1640
                var page = [UInt8](repeating: 0, count: W * (H + 800) * 4)
                var g = Seeded(7)
                for row in 0..<(H + 800) where row % 28 < 16 {                       // text lines with leading
                    for x in stride(from: 120, to: W - 120, by: 1) where (x / 9) % 3 != 2 {   // glyph cells with gaps
                        let v: UInt8 = (g.next() % 5 == 0) ? 30 : 235                  // dark strokes on light paper
                        let o = (row * W + x) * 4
                        page[o] = v; page[o + 1] = v; page[o + 2] = v; page[o + 3] = 255
                    }
                }
                for (hevc, cq, still) in [(false, false, false), (true, false, false), (false, false, true), (false, true, false)] {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-writer-\(hevc ? "hevc" : "h264")-\(cq ? "cq" : "abr").mp4")
                    try? FileManager.default.removeItem(at: url)
                    do {
                        let (w, inp, ad) = try ScreenRecorder.makeWriter(url: url, width: W, height: H, hevc: hevc, constantQuality: cq)
                        w.startSession(atSourceTime: .zero)
                        for i in 0..<60 {
                            var pb: CVPixelBuffer?
                            CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
                            guard let pb else { throw NSError(domain: "t", code: 1) }
                            CVPixelBufferLockBaseAddress(pb, [])
                            if let base = CVPixelBufferGetBaseAddress(pb) {
                                let stride = CVPixelBufferGetBytesPerRow(pb)
                                let offset = ((still ? i / 15 : i) * 12) * W * 4      // scroll every frame, or a nudge every half second
                                for row in 0..<H {
                                    page.withUnsafeBytes { src in
                                        memcpy(base + row * stride, src.baseAddress! + offset + row * W * 4, W * 4)
                                    }
                                }
                            }
                            CVPixelBufferUnlockBaseAddress(pb, [])
                            while !inp.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 5_000_000) }
                            _ = ad.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: ScreenRecorder.fps))
                        }
                        inp.markAsFinished()
                        await w.finishWriting()
                        let dur = await GIFEncoder.duration(movie: url)
                        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                        let good = w.status == .completed && abs(dur - 2.0) < 0.2 && bytes > 0
                        print("\(good ? "ok  " : "FAIL") \(hevc ? "hevc" : "h264") \(cq ? "quality \(ScreenRecorder.quality)" : "abr \(ScreenRecorder.bitrate(width: W, height: H, hevc: hevc) / 1000)kbps"): duration=\(String(format: "%.2f", dur))s size=\(bytes / 1024)K ≈ \(bytes * 8 / 2 / 1000) kbps \(still ? "mostly still" : "while scrolling")")
                        okAll = okAll && good
                    } catch { print("FAIL \(hevc ? "hevc" : "h264"): \(error)"); okAll = false }
                }
                ok = okAll
            case "pbfiles":
                PasteboardWriter.writeFiles([URL(fileURLWithPath: rest.first ?? SelfTest.sampleFile.path)], itemID: "test")
                print((NSPasteboard.general.types ?? []).map(\.rawValue).joined(separator: "\n"))
                let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
                print("readObjects → \(urls?.map(\.lastPathComponent) ?? [])")
                ok = (urls?.count ?? 0) == 1
            case "ingest": ok = ingest()
            case "tombstone": ok = tombstone()
            case "l10n":
                // The table is a list of pairs on purpose: a duplicate must be a test failure, never a launch crash.
                var seen: [String: Int] = [:]
                for (k, _) in L.pairs { seen[k, default: 0] += 1 }
                let dups = seen.filter { $0.value > 1 }.map(\.key)
                print("\(dups.isEmpty ? "ok  " : "FAIL") no duplicate keys \(dups)")
                print("ok   \(L.pairs.count) entries, \(L.en.count) unique")
                ok = dups.isEmpty
            case "updater":
                let fixture = """
                {"tag_name":"v1.2","html_url":"https://github.com/nothingbutcici/pastory/releases/tag/v1.2","body":"- faster shelf\\n- HEIC option",
                 "assets":[{"name":"Pastory-1.2.zip","browser_download_url":"https://github.com/nothingbutcici/pastory/releases/download/v1.2/Pastory-1.2.zip"}]}
                """
                let r: Updater.Release?
                do { r = try Updater.parse(Data(fixture.utf8)) } catch { print("parse error: \(error)"); r = nil }
                if let r { print("parsed: \(r.version) \(r.zipURL?.lastPathComponent ?? "-") notes=\(r.notes.count)") }
                let checks: [(String, Bool)] = [
                    ("parses tag/notes/asset", r?.version == "1.2" && r?.zipURL?.lastPathComponent == "Pastory-1.2.zip" && r?.notes.contains("HEIC") == true),
                    ("1.2 > 1.0", Updater.isNewer("1.2", than: "1.0")),
                    ("1.0.1 > 1.0", Updater.isNewer("1.0.1", than: "1.0")),
                    ("1.0 !> 1.0", !Updater.isNewer("1.0", than: "1.0")),
                    ("1.10 > 1.9", Updater.isNewer("1.10", than: "1.9")),
                    ("notes: zh half, no markdown", { let t = Updater.notesForDisplay("Pastory 1.2\n\n**新功能**\n- 一\n- 二\n\n---\n\nPastory 1.2\n\n**New**\n- one", version: "1.2", english: false)
                        return t == "新功能\n•  一\n•  二" }()),
                    ("notes: en half", Updater.notesForDisplay("中文\n---\n**New**\n- one", version: "1.2", english: true) == "New\n•  one"),
                    ("notes: no divider keeps all", Updater.notesForDisplay("- a\n- b", version: "1.2", english: true) == "•  a\n•  b"),
                    ("ad-hoc build must not self-install", Updater.teamIdentifier(of: Bundle.main.bundleURL) == nil ? !Updater.canSelfInstall : true),
                ]
                for (n, c) in checks { print("\(c ? "ok  " : "FAIL") \(n)") }
                ok = checks.allSatisfy(\.1)
            case "heic": ok = heic()
            case "openpanel":
                // How long until the system open panel is actually on screen (first show in this process)?
                let t0 = Date()
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true; panel.canChooseFiles = true
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                NSApp.activate(ignoringOtherApps: true)
                panel.begin { _ in }
                var waited = 0.0
                while !panel.isVisible, waited < 30 {
                    try? await Task.sleep(nanoseconds: 50_000_000); waited += 0.05
                }
                print(String(format: "open panel visible after %.2f s (visible=%@)", Date().timeIntervalSince(t0), panel.isVisible ? "yes" : "no"))
                panel.cancel(nil)
                ok = panel.isVisible || waited < 30
            case "annotate": ok = renderAnnotate(out: rest.first ?? "pastory-annotate.png")
            default: print("unknown selftest \(cmd)")
            }
            exit(ok ? 0 : 1)
        }
        return true
    }

    @MainActor
    private static func capture(out: String) async -> Bool {
        guard Permissions.hasScreenRecording else { print("no screen recording permission"); return false }
        do {
            let snap = try await ShareableSnapshot.fetch()
            guard let screen = NSScreen.main, let display = snap.display(for: screen) else { print("no display"); return false }
            let t0 = Date()
            let img = try await Screenshotter.capture(.display(display), snapshot: snap)
            let dt = Date().timeIntervalSince(t0)
            guard let png = Screenshotter.pngData(img) else { print("png failed"); return false }
            let url = URL(fileURLWithPath: out)
            try png.write(to: url)
            let name = (img.colorSpace?.name as String?) ?? "nil"
            print("captured \(img.width)×\(img.height) in \(Int(dt * 1000)) ms, colorSpace=\(name), \(png.count) bytes → \(url.path)")
            print("screen colorSpace=\((screen.colorSpace?.cgColorSpace?.name as String?) ?? "nil")")

            // Reference: Apple's own screencapture of the same display, then compare samples.
            let ref = url.deletingLastPathComponent().appendingPathComponent("pastory-ref.png")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let f = screen.frame
            let cgY = CoordinateSpace.primaryHeight - f.maxY
            p.arguments = ["-x", "-R", "\(Int(f.minX)),\(Int(cgY)),\(Int(f.width)),\(Int(f.height))", ref.path]
            try p.run(); p.waitUntilExit()
            guard let refData = try? Data(contentsOf: ref), let refImg = Screenshotter.image(fromPNG: refData) else {
                print("screencapture reference unavailable (skipped comparison)"); return true
            }
            print("reference \(refImg.width)×\(refImg.height), colorSpace=\((refImg.colorSpace?.name as String?) ?? "nil")")
            compare(img, refImg)
            return true
        } catch {
            print("capture failed: \(error)")
            return false
        }
    }

    /// Both images decoded into the same 8-bit sRGB buffer; sample points, report the spread.
    private static func compare(_ a: CGImage, _ b: CGImage) {
        guard a.width == b.width, a.height == b.height else { print("size differs, skipped comparison"); return }
        func raw(_ img: CGImage) -> [UInt8]? {
            let w = img.width, h = img.height
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return buf
        }
        guard let ra = raw(a), let rb = raw(b) else { return }
        var rng = SystemRandomNumberGenerator()
        var diffs: [Int] = []
        for _ in 0..<2000 {
            let i = Int.random(in: 0..<(a.width * a.height), using: &rng) * 4
            let d = max(abs(Int(ra[i]) - Int(rb[i])), abs(Int(ra[i + 1]) - Int(rb[i + 1])), abs(Int(ra[i + 2]) - Int(rb[i + 2])))
            diffs.append(d)
        }
        diffs.sort()
        let over2 = diffs.filter { $0 > 2 }.count
        print("pixel diff vs screencapture (2000 samples): median=\(diffs[1000]) p95=\(diffs[1900]) max=\(diffs.last!) samples>2: \(over2)")
    }

    private static func ocr(path: String?) -> Bool {
        let image: CGImage
        var expect: [String] = []
        if let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            image = img
        } else {
            guard let img = renderSample() else { print("sample render failed"); return false }
            image = img
            expect = ["Pastory", "截图工具", "2026"]
        }
        do {
            let t0 = Date()
            let text = try OCR.recognize(image)
            print("--- OCR (\(Int(Date().timeIntervalSince(t0) * 1000)) ms) ---\n\(text)\n---")
            let missing = expect.filter { !text.contains($0) }
            if !missing.isEmpty { print("missing: \(missing)"); return false }
            return true
        } catch {
            print("ocr failed: \(error)"); return false
        }
    }

    private static func renderSample() -> CGImage? {
        let w = 900, h = 260
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let lines = ["Pastory 是一个截图工具", "所有复制过的内容都留在剪贴板里", "Made in 2026 · 中英混排 OK"]
        for (i, s) in lines.enumerated() {
            (s as NSString).draw(at: CGPoint(x: 40, y: 180 - i * 64), withAttributes: [
                .font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Calendar-day rule, cleanup at 04:00, checked at several clock times. Pinned never goes; re-running changes nothing.
    @MainActor
    private static func retention() -> Bool {
        let store = ClipStore.shared
        let cal = Calendar.current
        let src = ClipStore.Source(bundleID: nil, name: "test")
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date()))!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func seed() {
            store.removeAll { _ in true }
            let rows: [(String, Date, Bool)] = [
                ("dayBefore", at(-2, 15), false), ("yesterday", at(-1, 15), false), ("yesterdayPinned", at(-1, 16), true),
                ("today0001", at(0, 0, 1), false), ("today0130", at(0, 1, 30), false), ("today0300", at(0, 3), false), ("today0900", at(0, 9), false),
            ]
            for (label, date, pinned) in rows {
                guard let it = store.insertText("\(label) \(UUID().uuidString)", rtf: nil, source: src) else { continue }
                store.debugSetDate(date, for: it.id)
                if pinned { store.togglePin(it.id) }
            }
        }
        func survivors() -> [String] { store.items.map { String($0.snippet.split(separator: " ")[0]) }.sorted() }
        func check(_ name: String, now: Date, days: Int = 1, expect: [String]) -> Bool {
            seed()
            Preferences.shared.cleanupHour = 4
            Preferences.shared.retentionDays = days
            Retention.sweep(now: now)
            let once = survivors()
            Retention.sweep(now: now)                     // idempotent
            let twice = survivors()
            let ok = once == expect.sorted() && twice == once
            print("\(ok ? "ok  " : "FAIL") \(name): \(once)")
            return ok
        }
        var ok = true
        ok = check("08:00 — 3am shutdown, 8am boot: yesterday goes, today's small hours stay", now: at(0, 8),
                   expect: ["yesterdayPinned", "today0001", "today0130", "today0300", "today0900"]) && ok
        ok = check("03:00 — before cleanup: yesterday still kept, day before goes", now: at(0, 3),
                   expect: ["yesterday", "yesterdayPinned", "today0001", "today0130", "today0300", "today0900"]) && ok
        ok = check("04:00 sharp", now: at(0, 4),
                   expect: ["yesterdayPinned", "today0001", "today0130", "today0300", "today0900"]) && ok
        ok = check("08:00 with 3-day retention: nothing expires", now: at(0, 8), days: 3,
                   expect: ["dayBefore", "yesterday", "yesterdayPinned", "today0001", "today0130", "today0300", "today0900"]) && ok
        // Manual delete stays deleted: remove one, sweep, re-open the store from disk.
        seed()
        if let victim = store.items.first(where: { $0.snippet.hasPrefix("today0900") }) {
            store.remove(victim.id)
            Retention.sweep(now: at(0, 8))
            let reloaded = ClipStore(root: store.root)
            let back = reloaded.items.contains { $0.snippet.hasPrefix("today0900") }
            print(back ? "FAIL manual delete came back" : "ok   manual delete stays deleted after reload")
            ok = ok && !back
        }
        // Never: nothing expires, no timer.
        seed()
        Preferences.shared.cleanupHour = 4
        Preferences.shared.retentionDays = 0
        Retention.sweep(now: at(0, 8))
        Retention.reschedule()
        let neverOK = store.items.count == 7 && Retention.nextFire == nil
        print("\(neverOK ? "ok  " : "FAIL") never: all 7 kept, no timer")
        ok = ok && neverOK
        // Timer cadence: with 7-day retention the next check is the oldest unpinned item's day + 7 at X, not tomorrow.
        seed()
        Preferences.shared.cleanupHour = 4
        Preferences.shared.retentionDays = 7
        Retention.reschedule()
        if let fire = Retention.nextFire {
            let expect = cal.date(bySettingHour: 4, minute: 0, second: 5, of: cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: at(-2, 15)))!)!
            let good = abs(fire.timeIntervalSince(expect)) < 1
            print("\(good ? "ok  " : "FAIL") 7-day timer fires at \(fire) (expected \(expect))")
            ok = ok && good
        } else { print("FAIL no timer armed"); ok = false }
        store.removeAll { _ in true }
        Preferences.shared.retentionDays = 1
        print(ok ? "retention OK" : "retention FAILED")
        return ok
    }

    /// Write a 2 s synthetic movie, encode to GIF, count frames.
    @MainActor
    private static func gif() async -> Bool {
        let dir = FileManager.default.temporaryDirectory
        let mov = dir.appendingPathComponent("pastory-selftest.mp4")
        let gifURL = dir.appendingPathComponent("pastory-selftest.gif")
        try? FileManager.default.removeItem(at: mov)
        try? FileManager.default.removeItem(at: gifURL)
        do {
            try await SyntheticMovie.write(to: mov, size: CGSize(width: 640, height: 360), seconds: 2, fps: 30)
            let t0 = Date()
            try await GIFEncoder.encode(movie: mov, to: gifURL)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard let src = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else { print("gif unreadable"); return false }
            let n = CGImageSourceGetCount(src)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int) ?? 0
            let first = CGImageSourceCreateImageAtIndex(src, 0, nil)
            print("gif: \(n) frames, \(first?.width ?? 0)×\(first?.height ?? 0), \(bytes / 1024) KB, encoded in \(ms) ms → \(gifURL.path)")
            let poster = await GIFEncoder.poster(movie: mov)
            print("poster: \(poster.map { "\($0.width)×\($0.height)" } ?? "nil"), duration \(await GIFEncoder.duration(movie: mov))s")
            return n >= 18 && n <= 22 && poster != nil   // 2 s at 10 fps
        } catch {
            print("gif selftest failed: \(error)"); return false
        }
    }

    // MARK: Offscreen UI renders (no screen-recording permission needed)

    @MainActor
    private static func seedStore() async {
        precondition(Sandbox.store != nil, "seedStore() outside PASTORY_STORE: refusing to touch the real store")
        let store = ClipStore.shared
        guard store.items.isEmpty else { return }
        let mov = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-seed.mp4")
        try? FileManager.default.removeItem(at: mov)
        if (try? await SyntheticMovie.write(to: mov, size: CGSize(width: 1280, height: 720), seconds: 8, fps: 30)) != nil {
            let poster = await GIFEncoder.poster(movie: mov)
            store.insertVideo(tempFile: mov, poster: poster, duration: 8, source: CaptureCoordinator.source)
        }
        let src = ClipStore.Source(bundleID: "com.apple.Safari", name: "Safari")
        store.insertText("会议纪要 9/11\n1. 下周三发布\n2. 演示视频重录\n3. 链接统一加追踪参数", rtf: nil, source: ClipStore.Source(bundleID: "com.apple.Notes", name: "备忘录"))
        store.insertText("https://github.com/nothingbutcici/pastory", rtf: nil, source: src)
        if let img = renderSample(), let png = Screenshotter.pngData(img) {
            store.insertImage(png: png, source: CaptureCoordinator.source, ocrText: "Pastory 是一个截图工具")
        }
        store.insertFiles([SelfTest.sampleFile, SelfTest.sampleFile.deletingLastPathComponent().appendingPathComponent("README.md")],
                          source: ClipStore.Source(bundleID: "com.apple.finder", name: "Finder"))
        store.insertText("const shelf = items.filter(i => i.pinned)\n  .map(render)\n  .join('')", rtf: nil, source: ClipStore.Source(bundleID: "com.microsoft.VSCode", name: "Code"))
        if let first = store.items.last { store.togglePin(first.id) }
        if let t = store.items.first(where: { $0.kind == .text }) { store.setTitle("翻译 prompt", for: t.id) }
    }

    @MainActor
    private static func snapshot(_ view: NSView, to out: String) -> Bool {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no rep"); return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { print("write failed: \(error)"); return false }
        print("rendered \(Int(view.bounds.width))×\(Int(view.bounds.height)) → \(out)")
        return true
    }

    @MainActor
    private static func renderShelf(out: String) async -> Bool {
        await seedStore()
        let model = ShelfPanelController.shared.model
        model.reset()
        // Thumbnails decode in the background; give them a moment so the render shows pictures, not placeholders.
        let store = ClipStore.shared
        let pictures = store.items.filter { $0.kind == .image || $0.kind == .video }
        pictures.forEach { store.warmThumbnail($0) }
        var waited = 0.0
        while waited < 3, pictures.contains(where: { !store.isThumbnailCached($0.id) }) { try? await Task.sleep(nanoseconds: 50_000_000); waited += 0.05 }
        let host = NSHostingView(rootView: ShelfView(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 1600, height: 450)
        // Needs a window for materials + layout to resolve.
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        w.isReleasedWhenClosed = false
        return snapshot(host, to: out)
    }

    @MainActor
    private static func renderAnnotate(out: String) -> Bool {
        guard let img = renderSample() else { return false }
        let scale: CGFloat = 2
        let rect = CGRect(x: 220, y: 150, width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let stage = NSView(frame: CGRect(x: 0, y: 0, width: max(rect.width + 80, 900), height: rect.height + 320))
        stage.wantsLayer = true
        stage.layer?.backgroundColor = NSColor(srgbRed: 0.35, green: 0.45, blue: 0.55, alpha: 1).cgColor   // stands in for the desktop
        let mask = OverlayView(frame: stage.bounds)
        mask.screenRef = NSScreen.main
        mask.held = true
        mask.heldRect = rect
        stage.addSubview(mask)
        let canvas = AnnotateView(frame: rect, image: img)
        stage.addSubview(canvas)
        let top = TopBar()
        let ts = top.fittingSize
        top.frame = CGRect(x: (stage.bounds.midX - ts.width / 2).rounded(), y: stage.bounds.maxY - 16 - ts.height, width: ts.width, height: ts.height)
        stage.addSubview(top)
        let bar = AnnotateToolbar(canvas: canvas)
        bar.frame = CGRect(x: max(8, (rect.midX - bar.fittingSize.width / 2).rounded()), y: rect.minY - 68, width: bar.fittingSize.width, height: bar.fittingSize.height)
        stage.addSubview(bar)
        bar.didLayout()
        let w = NSWindow(contentRect: stage.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = stage
        w.isReleasedWhenClosed = false

        let ink = AnnotatePalette.colors[5], red = AnnotatePalette.colors[1], blue = AnnotatePalette.colors[4], orange = AnnotatePalette.colors[2]
        canvas.debugSet([
            Annotation(tool: .rect, color: red, size: .m, points: [CGPoint(x: 12, y: 8), CGPoint(x: 250, y: 44)]),
            Annotation(tool: .arrow, color: blue, size: .l, points: [CGPoint(x: 300, y: 118), CGPoint(x: 215, y: 52)]),
            Annotation(tool: .ellipse, color: orange, size: .s, points: [CGPoint(x: 20, y: 56), CGPoint(x: 180, y: 104)]),
            Annotation(tool: .line, color: ink, size: .s, points: [CGPoint(x: 260, y: 60), CGPoint(x: 430, y: 60)]),
            Annotation(tool: .pen, color: red, size: .m, points: stride(from: 0, to: 120, by: 3).map { CGPoint(x: 280 + CGFloat($0), y: 96 + 9 * sin(CGFloat($0) / 7)) }),
            Annotation(tool: .mosaic, color: red, size: .m, points: [CGPoint(x: 20, y: 72), CGPoint(x: 200, y: 108)]),
            Annotation(tool: .text, color: blue, size: .m, points: [CGPoint(x: 262, y: 6)], text: "你好，今天天气怎么样？"),
            Annotation(tool: .text, color: ink, size: .s, points: [CGPoint(x: 300, y: 32)], text: "Hello Pastory"),
        ], select: nil)
        guard snapshot(stage, to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("idle.png").path) else { return false }
        canvas.debugSet(canvas.annotations, select: 0)
        guard snapshot(stage, to: out) else { return false }
        // Second frame: the arrow selected, to check endpoint handles.
        canvas.debugSet(canvas.annotations, select: 1)
        _ = snapshot(stage, to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("arrow.png").path)
        // Also the flattened export, at full pixel size.
        let flat = canvas.renderedImage()
        let flatURL = URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("flat.png")
        if let png = Screenshotter.pngData(flat) { try? png.write(to: flatURL) }
        print("flattened \(flat.width)×\(flat.height) colorSpace=\((flat.colorSpace?.name as String?) ?? "nil") → \(flatURL.path)")
        return true
    }

    @MainActor
    private static func clipboard(seconds: Int) async -> Bool {
        print("store: \(ClipStore.shared.root.path)")
        print("listening \(seconds)s — copy some text, an image, a file in Finder…")
        var seen: [ClipItem] = []
        ClipboardMonitor.shared.onChange = { item in
            seen.append(item)
            print("  + \(item.kind.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(item.sourceAppName ?? "?")  \(item.snippet.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(60))")
        }
        ClipboardMonitor.shared.start()
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        ClipboardMonitor.shared.stop()
        print("recorded \(seen.count) item(s); store now holds \(ClipStore.shared.items.count)")
        return true
    }
}

// MARK: - Pasteboard ingest rules

extension SelfTest {
    /// What other tools put on the board must land as the right kind: bitmap + temp file URL = image (thumbnail, OCR);
    /// a document copied in Finder = files; a lone temp image file = image.
    @MainActor static func ingest() -> Bool {
        let store = ClipStore.shared
        store.removeAll { _ in true }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-ingest-\(UUID().uuidString).png")
        let img = NSImage(size: CGSize(width: 40, height: 30), flipped: false) { r in NSColor.orange.setFill(); r.fill(); return true }
        guard let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        try? png.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        func board(_ fill: (NSPasteboard) -> Void) -> ClipItem? {
            let pb = NSPasteboard(name: NSPasteboard.Name("pastory.selftest.\(UUID().uuidString)"))
            pb.clearContents()
            fill(pb)
            defer { pb.releaseGlobally() }
            return ClipboardMonitor.shared.ingest(pb)
        }
        var ok = true
        func check(_ name: String, _ item: ClipItem?, _ kind: ClipKind) {
            let got = item?.kind.rawValue ?? "nil"
            print("\(got == kind.rawValue ? "ok  " : "FAIL") \(name): \(got) (want \(kind.rawValue))")
            if got != kind.rawValue { ok = false }
            store.removeAll { _ in true }
        }
        check("bitmap + temp file url (WeChat / Feishu style)", board { pb in
            pb.setData(png, forType: .png)
            pb.writeObjects([tmp as NSURL])
        }, .image)
        check("finder copy of a document", board { pb in
            pb.writeObjects([URL(fileURLWithPath: SelfTest.sampleFile.path) as NSURL])
        }, .files)
        check("lone temp image file", board { pb in pb.writeObjects([tmp as NSURL]) }, .image)
        check("plain text", board { pb in pb.setString("hello", forType: .string) }, .text)
        check("bitmap only", board { pb in pb.setData(png, forType: .png) }, .image)
        store.removeAll { _ in true }
        return ok
    }
}

// MARK: - Tombstones

extension SelfTest {
    /// Delete an item, then import a copy of the store taken before the deletion: the deleted one must stay gone,
    /// the other two are already present, nothing is added.
    @MainActor static func tombstone() -> Bool {
        let store = ClipStore.shared
        store.removeAll { _ in true }
        let src = Source(bundleID: "test", name: "Test")
        _ = store.insertText("alpha", rtf: nil, source: src)
        _ = store.insertText("beta", rtf: nil, source: src)
        _ = store.insertText("gamma", rtf: nil, source: src)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("pastory-copy-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: copy)
        do { try FileManager.default.copyItem(at: store.root, to: copy) } catch { print("copy failed: \(error)"); return false }
        defer { try? FileManager.default.removeItem(at: copy) }
        guard let beta = store.items.first(where: { $0.snippet == "beta" }) else { return false }
        store.remove(beta.id)
        guard let scan = try? Importer.scan(copy) else { print("scan failed"); return false }
        let added = store.importEntries(scan.entries)
        let back = store.items.contains { $0.snippet == "beta" }
        print("\(added == 0 && !back ? "ok  " : "FAIL") deleted item stays deleted after importing the old copy (added \(added), beta back: \(back))")
        _ = store.insertText("beta", rtf: nil, source: src)
        let fresh = store.items.contains { $0.snippet == "beta" }
        print("\(fresh ? "ok  " : "FAIL") a fresh copy of the same text is a new item again")
        store.removeAll { _ in true }
        return added == 0 && !back && fresh
    }
    typealias Source = ClipStore.Source
}

// MARK: - HEIC storage

extension SelfTest {
    /// With the HEIC setting on, a stored screenshot is smaller, keeps its pixel size and color space,
    /// and comes back out as PNG for the pasteboard / export path.
    @MainActor static func heic() -> Bool {
        let store = ClipStore.shared
        store.removeAll { _ in true }
        // A P3 picture with gradients, so the compression has something to do and the profile matters.
        let w = 1200, h = 800
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        for x in stride(from: 0, to: w, by: 4) {
            ctx.setFillColor(CGColor(colorSpace: space, components: [CGFloat(x) / CGFloat(w), 0.4, 1 - CGFloat(x) / CGFloat(w), 1])!)
            ctx.fill(CGRect(x: x, y: 0, width: 4, height: h))
        }
        guard let cg = ctx.makeImage(), let png = Screenshotter.pngData(cg) else { return false }
        var ok = true
        func check(_ name: String, _ cond: Bool) { print("\(cond ? "ok  " : "FAIL") \(name)"); if !cond { ok = false } }
        Preferences.shared.imageStorage = "heic"
        guard let item = store.insertImage(png: png, source: Source(bundleID: "test", name: "Test")) else { return false }
        check("stored as heic", item.ext == "heic")
        let onDisk = (try? Data(contentsOf: store.payloadURL(item)))?.count ?? 0
        check("heic smaller than png (\(onDisk / 1024)K vs \(png.count / 1024)K)", onDisk > 0 && onDisk < png.count / 2)
        let back = store.png(of: item)
        let cgBack = back.flatMap(Screenshotter.image(fromPNG:))
        check("png(of:) yields PNG at the same size", back?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true && cgBack?.width == w && cgBack?.height == h)
        check("color space kept (\(cgBack?.colorSpace?.name as String? ?? "nil"))", cgBack?.colorSpace?.name == space.name)
        check("hash is the PNG's, so the same picture dedupes", store.insertImage(png: png, source: Source(bundleID: "test", name: "Test"))?.id == item.id)
        Preferences.shared.imageStorage = "png"
        guard let plain = store.insertImage(png: Screenshotter.pngData(Screenshotter.thumbnail(cg, maxPixels: 300)!)!, source: Source(bundleID: "test", name: "Test")) else { return false }
        check("png when chosen", plain.ext == "png")
        Preferences.shared.imageStorage = "heic"
        store.removeAll { _ in true }
        return ok
    }
}
