import AppKit
import UniformTypeIdentifiers

/// "保存到本地": always ask where, remember the folder for next time.
@MainActor
enum Exporter {
    static func export(_ item: ClipItem) {
        let store = ClipStore.shared
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = f.string(from: item.createdAt)
        let shelf = ShelfPanelController.shared
        shelf.holdOpen = true
        defer { shelf.holdOpen = false; shelf.refocus() }
        NSApp.activate(ignoringOtherApps: true)

        switch item.kind {
        case .image, .text, .url, .video:
            let panel = NSSavePanel()
            panel.directoryURL = Preferences.shared.exportDirectory()
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            if item.kind == .image {
                panel.nameFieldStringValue = "Snip \(stamp).png"
                panel.allowedContentTypes = [.png]
            } else if item.kind == .video {
                panel.nameFieldStringValue = "Rec \(stamp).\(item.ext)"
                panel.allowedContentTypes = [item.ext == "gif" ? .gif : .mpeg4Movie]
            } else {
                panel.nameFieldStringValue = "Clip \(stamp).txt"
                panel.allowedContentTypes = [.plainText]
            }
            panel.prompt = "保存"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: url)
            do {
                try fm.copyItem(at: store.payloadURL(item), to: url)
                remember(url.deletingLastPathComponent())
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSSound.beep()
            }
        case .files:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = Preferences.shared.exportDirectory()
            panel.prompt = "保存到这里"
            panel.message = "选择一个文件夹，把这些文件复制过去"
            guard panel.runModal() == .OK, let dir = panel.url else { return }
            let fm = FileManager.default
            var out: [URL] = []
            for src in store.fileURLs(of: item) where fm.fileExists(atPath: src.path) {
                var dst = dir.appendingPathComponent(src.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: dst.path) {
                    dst = dir.appendingPathComponent("\(src.deletingPathExtension().lastPathComponent) \(n).\(src.pathExtension)")
                    n += 1
                }
                if (try? fm.copyItem(at: src, to: dst)) != nil { out.append(dst) }
            }
            remember(dir)
            if !out.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(out) }
        }
    }

    private static func remember(_ dir: URL) { Preferences.shared.customExportDir = dir.path }
}
