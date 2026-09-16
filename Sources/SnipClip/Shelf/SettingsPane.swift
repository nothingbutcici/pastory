import SwiftUI

/// Settings, rendered in the shelf's right half in the shelf's own look.
struct SettingsPane: View {
    @Bindable var model: ShelfModel
    @State private var prefs = PrefsMirror()
    @State private var cleared = false
    @State private var importNote: String?
    @State private var storeSize: String?
    @State private var updateNote: String?
    @State private var checkingUpdate = false
    @State private var hasAX = Permissions.hasAccessibility
    @State private var hasSR = Permissions.hasScreenRecording


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("设置".l).font(.serif(22, bold: true)).foregroundStyle(Color.onBrown)
                Spacer()
                Button { model.showSettings = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("返回剪贴板".l).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.onBrown)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Color.onBrown.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { ShelfPanelController.shared.hide() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .regular)).foregroundStyle(Color.onBrown).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
            .padding(.bottom, 14)
            .task {
                // Permission badges: re-check every second while the pane is up (each check is an XPC call; not per body).
                while !Task.isCancelled {
                    hasAX = Permissions.hasAccessibility; hasSR = Permissions.hasScreenRecording
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        section("版本更新".l) {
                            row(String(format: "当前版本 %@".l, Updater.currentVersion)) {
                                HStack(spacing: 8) {
                                    if let updateNote { Text(updateNote).font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1) }
                                    pill(checkingUpdate ? "检查中…".l : "检查更新".l, disabled: checkingUpdate) {
                                        checkingUpdate = true
                                        Task { @MainActor in
                                            let outcome = await Updater.shared.check(interactive: true, quiet: true)
                                            switch outcome {
                                            case .upToDate: updateNote = "已是最新版本".l
                                            case .available(let v): updateNote = String(format: "有新版本 %@".l, v)
                                            case .failed(let msg): updateNote = String(format: "检查失败：%@".l, msg)
                                            case .skipped: break
                                            }
                                            checkingUpdate = false
                                        }
                                    }
                                }
                            }
                            row("每天自动检查一次（app 唯一的联网请求，不带任何标识）".l) { PaperToggle(isOn: $prefs.checkForUpdates) }
                        }
                        section("快捷键".l) {
                            row("截图".l) { ShortcutRecorder(key: Preferences.Key.hotkeyCapture) }
                            row("显示 / 隐藏剪贴板".l) { ShortcutRecorder(key: Preferences.Key.hotkeyShelf) }
                            row("搜索剪贴板".l) { ShortcutRecorder(key: Preferences.Key.hotkeySearch) }
                        }
                        section("剪贴板".l) {
                            row("未 Pin 内容保留时间".l) {
                                HStack(spacing: 4) {
                                    ForEach([(1, "1 天".l), (3, "3 天".l), (7, "7 天".l), (30, "30 天".l), (365, "一年".l), (0, "永不删除".l)], id: \.0) { days, label in
                                        let on = prefs.retentionDays == days
                                        Button { changeRetention(to: days) } label: {
                                            Text(label).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                                .foregroundStyle(on ? Color.ink : Color.ink)
                                                .padding(.horizontal, 11).padding(.vertical, 6)
                                                .background(on ? Color.paperBlue : Color.clear, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
                            }
                            row("当日清理时间".l) {
                                HourWheel(hour: $prefs.cleanupHour, enabled: prefs.retentionDays != 0)
                                    .opacity(prefs.retentionDays == 0 ? 0.35 : 1)
                            }
                            row("图片自动识别文字（可按文字搜图）".l) { PaperToggle(isOn: $prefs.ocrImages) }
                            row("暂停同步至剪贴板".l) { PaperToggle(isOn: $prefs.paused) }
                            row("双击 / ⏎ 后直接粘贴到刚才的应用".l) {
                                HStack(spacing: 8) {
                                    if prefs.pasteOnDoubleClick {
                                        Text(hasAX ? "已授权".l : "需要辅助功能权限".l)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(hasAX ? Color.ink : Color(nsColor: Theme.warn))
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(hasAX ? Color.paperBlue : Color.clear, in: Capsule())
                                            .overlay(Capsule().stroke((hasAX ? Color.clear : Color(nsColor: Theme.warn)).opacity(0.7), lineWidth: 1))
                                        if !hasAX { pill("系统设置".l) { Permissions.requestAccessibility(); Permissions.openSettings("Privacy_Accessibility") } }
                                    }
                                    PaperToggle(isOn: $prefs.pasteOnDoubleClick)
                                }
                            }
                            row("录屏编码".l) {
                                HStack(spacing: 4) {
                                    ForEach([(false, "H.264（到处能放）"), (true, "HEVC（再小一半，Windows 可能放不了）")], id: \.0) { hevc, label in
                                        let on = prefs.recordHEVC == hevc
                                        Button { prefs.recordHEVC = hevc } label: {
                                            Text(label.l).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                                .foregroundStyle(Color.ink)
                                                .padding(.horizontal, 11).padding(.vertical, 6)
                                                .background(on ? Color.paperBlue : Color.clear, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
                            }
                            row("本地数据库截图存储方式".l) {
                                HStack(spacing: 4) {
                                    ForEach([("heic", "高质量 HEIC（默认，约小 3 倍）"), ("png", "无损 PNG")], id: \.0) { code, label in
                                        let on = prefs.imageStorage == code
                                        Button { prefs.imageStorage = code } label: {
                                            Text(label.l).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                                .foregroundStyle(Color.ink)
                                                .padding(.horizontal, 11).padding(.vertical, 6)
                                                .background(on ? Color.paperBlue : Color.clear, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
                            }
                            row("语言".l) {
                                HStack(spacing: 4) {
                                    ForEach([("system", "跟随系统".l), ("zh", "中文".l), ("en", "English")], id: \.0) { code, label in
                                        let on = Preferences.shared.language == code
                                        Button { Preferences.shared.language = code; model.langTick += 1 } label: {
                                            Text(label.l).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                                .foregroundStyle(Color.ink)
                                                .padding(.horizontal, 11).padding(.vertical, 6)
                                                .background(on ? Color.paperBlue : Color.clear, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
                            }
                            row("从其他剪贴板工具导入（SQLite）".l) {
                                HStack(spacing: 8) {
                                    if let importNote { Text(importNote).font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1) }
                                    pill("选择数据库…".l) { importDatabase() }
                                }
                            }
                            if ClipStore.shared.items.contains(where: { $0.sourceAppName == ClipStore.importSourceName }) {
                                row("移除所有导入进来的条目（来源为「导入」）".l) {
                                    pill("移除".l) { removeImported() }
                                }
                            }
                            row("手动清空一次（不含已 Pin 内容）".l) {
                                pill(cleared ? "已清空".l : "现在清空".l, disabled: cleared) {
                                    ClipStore.shared.removeAll { !$0.pinned }
                                    cleared = true
                                }
                            }
                        }
                    }
                    VStack(spacing: 16) {
                        section("位置".l) {
                            row("「保存到本地」默认打开的文件夹".l) {
                                HStack(spacing: 8) {
                                    Text(prefs.exportDir.isEmpty ? "~/Downloads" : (prefs.exportDir as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing)
                                    if !prefs.exportDir.isEmpty { pill("默认".l) { prefs.exportDir = "" } }
                                    pill("选择…".l) { chooseFolder() }
                                }
                            }
                            row("剪贴板内容临时存放位置".l) {
                                HStack(spacing: 8) {
                                    Text("SQLite").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
                                    Text((ClipStore.shared.root.appendingPathComponent("pastory.sqlite").path as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 340, alignment: .trailing)
                                        .textSelection(.enabled)
                                    if let storeSize { Text(storeSize).font(.system(size: 12)).foregroundStyle(Color.inkMuted) }
                                }
                                .task {
                                    let root = ClipStore.shared.root, n = ClipStore.shared.items.count
                                    let bytes = await Task.detached { () -> Int64 in
                                        var total: Int64 = 0
                                        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                                            for case let u as URL in e { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                                        }
                                        return total
                                    }.value
                                    storeSize = "· " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " · " + String(format: "%d 项".l, n)
                                }
                            }
                        }
                        section("系统".l) {
                            row("登录时启动".l) { PaperToggle(isOn: $prefs.launchAtLogin) }
                            if let e = prefs.loginError { Text(e).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.warn)).padding(.horizontal, 16) }
                            row("屏幕录制权限（截图、录屏需要）".l) {
                                HStack(spacing: 8) {
                                    Text(hasSR ? "已授权".l : "未授权".l)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(hasSR ? Color.ink : Color(nsColor: Theme.warn))
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(hasSR ? Color.paperBlue : Color.clear, in: Capsule())
                                        .overlay(Capsule().stroke((hasSR ? Color.clear : Color(nsColor: Theme.warn)).opacity(0.7), lineWidth: 1))
                                    pill("系统设置".l) { Permissions.openSettings("Privacy_ScreenCapture") }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.serif(13, bold: true)).foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)      // the sheet casts it, the type does not
        )
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack {
            Text(label).font(.serif(15)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func pill(_ title: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    /// Shortening the retention can wipe a lot at once; say how much and ask.
    private func changeRetention(to days: Int) {
        let p = Preferences.shared
        let effective: (Int) -> Int = { $0 == 0 ? Int.max : $0 }
        if effective(days) < effective(prefs.retentionDays) {
            let doomed = ClipStore.shared.items.filter { Retention.isExpired($0, now: Date(), cleanupHour: p.cleanupHour, retentionDays: days) }.count
            if doomed > 0 {
                let go = ShelfPanelController.shared.withDialog { () -> Bool in
                    let a = NSAlert()
                    a.messageText = String(format: "把保留期改成 %d 天？".l, days)
                    a.informativeText = String(format: "会立刻清掉 %d 条未 Pin 的记录。Pin 住的不受影响。".l, doomed)
                    a.addButton(withTitle: "改并清理".l)
                    a.addButton(withTitle: "取消".l)
                    return a.runModal() == .alertFirstButtonReturn
                }
                if !go { return }
            }
        }
        prefs.retentionDays = days
    }

    private func removeImported() {
        let n = ClipStore.shared.items.filter { $0.sourceAppName == ClipStore.importSourceName }.count
        let go = ShelfPanelController.shared.withDialog { () -> Bool in
            let a = NSAlert()
            a.messageText = String(format: "移除 %d 条导入的内容？".l, n)
            a.informativeText = "只删来源标为「导入」的条目，包括其中已 Pin 的；其他内容不动。".l
            a.addButton(withTitle: "移除".l)
            a.addButton(withTitle: "取消".l)
            return a.runModal() == .alertFirstButtonReturn
        }
        guard go else { return }
        ClipStore.shared.removeAll { $0.sourceAppName == ClipStore.importSourceName }
        model.refreshOrder()
        importNote = String(format: "已移除 %d 条".l, n)
    }

    /// Pick a .sqlite (or a Pastory folder), count what is inside, ask, import.
    private func importDatabase() {
        let picked: URL? = ShelfPanelController.shared.withDialog {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.prompt = "扫描".l
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            panel.message = "选另一个剪贴板工具的数据库文件或它的数据文件夹，或另一台机器的 Pastory 文件夹".l
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let picked else { return }
        importNote = "扫描中…".l
        Task.detached(priority: .userInitiated) {
            let result = Result { try Importer.scan(picked) }
            await MainActor.run {
                switch result {
                case .failure(let e):
                    importNote = e.localizedDescription
                case .success(let scan):
                    // Imported history is older than anything here, so a finite retention would sweep it at the next cleanup.
                    let cleans = !Preferences.shared.neverCleans
                    let choice = ShelfPanelController.shared.withDialog { () -> Int in
                        let a = NSAlert()
                        a.messageText = String(format: "找到 %d 条文本、%d 张图片".l, scan.texts, scan.images)
                        a.informativeText = String(format: "来自 %@。已经在 Pastory 里的内容会自动跳过，Pin 会保留；导入的内容排在 Pastory 自己记录的后面。".l, picked.lastPathComponent)
                            + (cleans ? String(format: "\n\n当前保留期是 %d 天，而这些内容都比保留期老：导入会同时把保留期改为「永不删除」，否则它们马上就会被清掉。".l, Preferences.shared.retentionDays) : "")
                        a.addButton(withTitle: cleans ? "导入并改为永不删除".l : "导入".l)
                        a.addButton(withTitle: "取消".l)
                        return a.runModal() == .alertFirstButtonReturn ? 1 : 0
                    }
                    guard choice != 0 else { importNote = nil; return }
                    if cleans { prefs.retentionDays = 0 }
                    let n = ClipStore.shared.importEntries(scan.entries)
                    model.refreshOrder()
                    importNote = n == 0 ? "没有新内容（都已存在）".l : String(format: "已导入 %d 条".l, n)
                }
            }
        }
    }

    private func chooseFolder() {
        let picked: URL? = ShelfPanelController.shared.withDialog {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "选择".l
            return panel.runModal() == .OK ? panel.url : nil
        }
        if let picked { prefs.exportDir = picked.path }
    }
}

/// One-line hour control: scroll up / down over it (trackpad or wheel) to change; tiny ▲▼ for clicking.
struct HourWheel: View {
    @Binding var hour: Int
    var enabled: Bool = true
    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(Color.ink)
                .frame(width: 58)
            VStack(spacing: 0) {
                Button { if enabled { hour = (hour + 23) % 24 } } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 11) }
                Button { if enabled { hour = (hour + 1) % 24 } } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 11) }
            }
            .buttonStyle(.plain).foregroundStyle(Color.inkMuted)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
        .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
        .overlay(ScrollSteps(enabled: enabled) { step in hour = (hour + step + 24) % 24 })
        .help("上下滑动或点箭头调整".l)
    }
}

/// Transparent view that turns scroll-wheel motion into +1 / -1 steps.
struct ScrollSteps: NSViewRepresentable {
    var enabled: Bool = true
    let onStep: (Int) -> Void
    func makeNSView(context: Context) -> StepView { let v = StepView(); v.onStep = onStep; v.enabled = enabled; return v }
    func updateNSView(_ v: StepView, context: Context) { v.onStep = onStep; v.enabled = enabled }
    final class StepView: NSView {
        var onStep: ((Int) -> Void)?
        var enabled = true
        private var acc: CGFloat = 0
        override func scrollWheel(with event: NSEvent) {
            guard enabled else { return }
            guard event.momentumPhase.isEmpty else { return }      // inertia from scrolling the page must not turn the dial
            acc += event.scrollingDeltaY
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 18 : 1
            while acc >= threshold { acc -= threshold; onStep?(-1) }     // scroll up → earlier hour
            while acc <= -threshold { acc += threshold; onStep?(1) }
        }
        // Scroll events are ours; clicks are handed back to the hosting view so the ▲▼ buttons still work.
        override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
        override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
        override func mouseDragged(with event: NSEvent) { superview?.mouseDragged(with: event) }
        override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
    }
}

/// Switch in the paper palette: blue track when on, cream track with an ink outline when off, paper knob.
struct PaperToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color.paperBlue : Color.paperDim)
                Capsule().stroke(Color.ink.opacity(isOn ? 0.35 : 0.5), lineWidth: 1)
                Circle().fill(Color.paper)
                    .overlay(Circle().stroke(Color.ink.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 44, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
