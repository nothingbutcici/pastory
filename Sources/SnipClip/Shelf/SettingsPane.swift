import SwiftUI

/// Settings, rendered in the shelf's right half in the shelf's own look.
struct SettingsPane: View {
    @Bindable var model: ShelfModel
    @State private var prefs = PrefsMirror()
    @State private var cleared = false
    @State private var importNote: String?


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("设置").font(.serif(22, bold: true)).foregroundStyle(Color.onBrown)
                Spacer()
                Button { model.showSettings = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("返回剪贴板").font(.system(size: 13, weight: .medium))
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

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        section("快捷键") {
                            row("截图") { ShortcutRecorder(key: Preferences.Key.hotkeyCapture) }
                            row("显示 / 隐藏剪贴板") { ShortcutRecorder(key: Preferences.Key.hotkeyShelf) }
                            row("搜索剪贴板") { ShortcutRecorder(key: Preferences.Key.hotkeySearch) }
                        }
                        section("剪贴板") {
                            row("未 Pin 内容保留时间") {
                                HStack(spacing: 4) {
                                    ForEach([(1, "1 天"), (3, "3 天"), (7, "7 天"), (30, "30 天"), (365, "一年"), (0, "永不删除")], id: \.0) { days, label in
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
                            row("当日清理时间") {
                                HourWheel(hour: $prefs.cleanupHour, enabled: prefs.retentionDays != 0)
                                    .opacity(prefs.retentionDays == 0 ? 0.35 : 1)
                            }
                            row("图片自动识别文字（可按文字搜图）") { PaperToggle(isOn: $prefs.ocrImages) }
                            row("暂停同步至剪贴板") { PaperToggle(isOn: $prefs.paused) }
                            row("从其他剪贴板工具导入（SQLite）") {
                                HStack(spacing: 8) {
                                    if let importNote { Text(importNote).font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1) }
                                    pill("选择数据库…") { importDatabase() }
                                }
                            }
                            if ClipStore.shared.items.contains(where: { $0.sourceAppName == "导入" }) {
                                row("移除所有导入进来的条目（来源为「导入」）") {
                                    pill("移除") { removeImported() }
                                }
                            }
                            row("手动清空一次（不含已 Pin 内容）") {
                                pill(cleared ? "已清空" : "现在清空", disabled: cleared) {
                                    ClipStore.shared.removeAll { !$0.pinned }
                                    cleared = true
                                }
                            }
                        }
                    }
                    VStack(spacing: 16) {
                        section("位置") {
                            row("「保存到本地」默认打开的文件夹") {
                                HStack(spacing: 8) {
                                    Text(prefs.exportDir.isEmpty ? "~/Downloads" : (prefs.exportDir as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing)
                                    if !prefs.exportDir.isEmpty { pill("默认") { prefs.exportDir = "" } }
                                    pill("选择…") { chooseFolder() }
                                }
                            }
                            row("剪贴板内容临时存放位置") {
                                HStack(spacing: 8) {
                                    Text("SQLite").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
                                    Text((ClipStore.shared.root.appendingPathComponent("pastory.sqlite").path as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12)).foregroundStyle(Color.inkMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 340, alignment: .trailing)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        section("系统") {
                            row("登录时启动") { PaperToggle(isOn: $prefs.launchAtLogin) }
                            if let e = prefs.loginError { Text(e).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)).padding(.horizontal, 16) }
                            row("屏幕录制权限（截图、录屏需要）") {
                                HStack(spacing: 8) {
                                    Text(Permissions.hasScreenRecording ? "已授权" : "未授权")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Permissions.hasScreenRecording ? Color.ink : Color(nsColor: Theme.tagMP4))
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Permissions.hasScreenRecording ? Color.paperBlue : Color.clear, in: Capsule())
                                        .overlay(Capsule().stroke((Permissions.hasScreenRecording ? Color.clear : Color(nsColor: Theme.tagMP4)).opacity(0.7), lineWidth: 1))
                                    pill("系统设置") { Permissions.openSettings("Privacy_ScreenCapture") }
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
                    a.messageText = "把保留期改成 \(days) 天？"
                    a.informativeText = "会立刻清掉 \(doomed) 条未 Pin 的记录。Pin 住的不受影响。"
                    a.addButton(withTitle: "改并清理")
                    a.addButton(withTitle: "取消")
                    return a.runModal() == .alertFirstButtonReturn
                }
                if !go { return }
            }
        }
        prefs.retentionDays = days
    }

    private func removeImported() {
        let n = ClipStore.shared.items.filter { $0.sourceAppName == "导入" }.count
        let go = ShelfPanelController.shared.withDialog { () -> Bool in
            let a = NSAlert()
            a.messageText = "移除 \(n) 条导入的内容？"
            a.informativeText = "只删来源标为「导入」的条目，包括其中已 Pin 的；其他内容不动。"
            a.addButton(withTitle: "移除")
            a.addButton(withTitle: "取消")
            return a.runModal() == .alertFirstButtonReturn
        }
        guard go else { return }
        ClipStore.shared.removeAll { $0.sourceAppName == "导入" }
        importNote = "已移除 \(n) 条"
    }

    /// Pick a .sqlite (or a Pastory folder), count what is inside, ask, import.
    private func importDatabase() {
        let picked: URL? = ShelfPanelController.shared.withDialog {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.prompt = "扫描"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            panel.message = "选另一个剪贴板工具的数据库文件或它的数据文件夹，或另一台机器的 Pastory 文件夹"
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let picked else { return }
        importNote = "扫描中…"
        Task.detached(priority: .userInitiated) {
            let result = Result { try Importer.scan(picked) }
            await MainActor.run {
                switch result {
                case .failure(let e):
                    importNote = e.localizedDescription
                case .success(let scan):
                    let go = ShelfPanelController.shared.withDialog { () -> Bool in
                        let a = NSAlert()
                        a.messageText = "找到 \(scan.texts) 条文本、\(scan.images) 张图片"
                        a.informativeText = "来自 \(picked.lastPathComponent)。已经在 Pastory 里的内容会自动跳过，原来的时间和 Pin 会保留。"
                        a.addButton(withTitle: "导入")
                        a.addButton(withTitle: "取消")
                        return a.runModal() == .alertFirstButtonReturn
                    }
                    guard go else { importNote = nil; return }
                    let n = ClipStore.shared.importEntries(scan.entries)
                    importNote = n == 0 ? "没有新内容（都已存在）" : "已导入 \(n) 条"
                }
            }
        }
    }

    private func chooseFolder() {
        let picked: URL? = ShelfPanelController.shared.withDialog {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "选择"
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
        .help("上下滑动或点箭头调整")
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
