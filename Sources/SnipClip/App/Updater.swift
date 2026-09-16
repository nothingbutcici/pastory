import AppKit

/// Update check against GitHub Releases, once a day and on demand. Installs the release zip in place when the new
/// build is signed by the same team as the running one; before the app is notarized it only points at the release page.
/// The only network request Pastory ever makes; it carries no identifier (settings can turn it off).
@MainActor
final class Updater {
    static let shared = Updater()
    static let repo = "nothingbutcici/pastory"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    struct Release: Equatable {
        var version: String
        var notes: String
        var zipURL: URL?
        var page: URL
    }

    private var timer: Timer?
    private var busy = false

    enum Outcome { case upToDate, available(String), failed(String), skipped }

    /// Current version, from the bundle.
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Launch: first check after half a minute, then every 24 h while running. Respects the setting.
    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            Task { @MainActor in
                await Updater.shared.check(interactive: false)
                Updater.shared.timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
                    Task { @MainActor in await Updater.shared.check(interactive: false) }
                }
            }
        }
    }

    /// `interactive`: the user asked (menu / settings). `quiet`: the caller shows the outcome itself (settings pane),
    /// so no "up to date" / "failed" alert — the offer dialog for a new version always appears.
    @discardableResult
    func check(interactive: Bool, quiet: Bool = false) async -> Outcome {
        guard !busy else { return .skipped }
        if !interactive {
            guard Preferences.shared.checkForUpdates else { return .skipped }
            if let last = Preferences.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 20 * 3600 { return .skipped }
        }
        busy = true
        defer { busy = false }
        Preferences.shared.lastUpdateCheck = Date()
        do {
            let release = try await Self.fetchLatest()
            guard Self.isNewer(release.version, than: Self.currentVersion) else {
                if interactive, !quiet { info("已经是最新版本".l, String(format: "Pastory %@".l, Self.currentVersion)) }
                return .upToDate
            }
            if !interactive, Preferences.shared.skippedVersion == release.version { return .skipped }
            offer(release)
            return .available(release.version)
        } catch {
            if interactive, !quiet { info("检查更新失败".l, error.localizedDescription) }
            return .failed(error.localizedDescription)
        }
    }

    // MARK: GitHub

    static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Pastory/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Release {
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String else { throw URLError(.cannotParseResponse) }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = j["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
        let page = (j["html_url"] as? String).flatMap(URL.init) ?? releasesPage
        return Release(version: version, notes: (j["body"] as? String) ?? "", zipURL: zip, page: page)
    }

    /// "1.2.1" > "1.2" > "1.0"; non-numeric parts compare as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Prompt

    private func offer(_ r: Release) {
        let a = NSAlert()
        a.messageText = String(format: "Pastory %@ 可以更新了（当前 %@）".l, r.version, Self.currentVersion)
        let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        a.informativeText = notes.isEmpty ? "" : String(notes.prefix(600))
        let canInstall = r.zipURL != nil && Self.canSelfInstall
        a.addButton(withTitle: canInstall ? "下载并安装".l : "打开下载页".l)
        a.addButton(withTitle: "稍后".l)
        a.addButton(withTitle: "跳过这个版本".l)
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if canInstall, let zip = r.zipURL { Task { await install(from: zip, version: r.version, page: r.page) } }
            else { NSWorkspace.shared.open(r.page) }
        case .alertThirdButtonReturn:
            Preferences.shared.skippedVersion = r.version
        default: break
        }
    }

    private func info(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: Install

    /// Only a signed, notarized build knows who it is; an ad-hoc one must not replace itself with an unverifiable download.
    static var canSelfInstall: Bool {
        guard let team = teamIdentifier(of: Bundle.main.bundleURL), !team.isEmpty else { return false }
        let path = Bundle.main.bundleURL.path
        return !path.contains("/AppTranslocation/") && FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
    }

    static func teamIdentifier(of app: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", "--verbose=2", app.path]
        let pipe = Pipe()
        p.standardError = pipe; p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let line = out.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else { return nil }
        let id = line.dropFirst("TeamIdentifier=".count)
        return id == "not set" ? nil : String(id)
    }

    private func install(from zip: URL, version: String, page: URL) async {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("pastory-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (tmp, _) = try await URLSession.shared.download(from: zip)
            let zipFile = work.appendingPathComponent("Pastory.zip")
            try fm.moveItem(at: tmp, to: zipFile)
            try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
            let newApp = work.appendingPathComponent("Pastory.app")
            guard fm.fileExists(atPath: newApp.path) else { throw URLError(.cannotDecodeContentData) }
            // Same team as the running copy, and a valid signature, or we do not touch anything.
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            guard let mine = Self.teamIdentifier(of: Bundle.main.bundleURL), Self.teamIdentifier(of: newApp) == mine else { throw URLError(.secureConnectionFailed) }
            let target = Bundle.main.bundleURL
            _ = try fm.replaceItemAt(target, withItemAt: newApp, backupItemName: nil, options: [])
            try? fm.removeItem(at: work)
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: target, configuration: cfg) { _, error in
                if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
            }
        } catch {
            try? fm.removeItem(at: work)
            let a = NSAlert()
            a.messageText = "自动更新没有成功".l
            a.informativeText = error.localizedDescription + "\n\n" + "可以手动从下载页更新。".l
            a.addButton(withTitle: "打开下载页".l)
            a.addButton(withTitle: "取消".l)
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
        }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "Pastory.Update", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }
}
