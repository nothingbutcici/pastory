import SwiftUI

/// Settings, rendered in the shelf's right half in the shelf's own look.
struct SettingsPane: View {
    @Bindable var model: ShelfModel
    @State private var prefs = PrefsMirror()
    @State private var cleared = false
    @State private var storeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("设置").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.shelfInk)
                Spacer()
                Button { model.showSettings = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("返回剪贴板").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.shelfInk)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.shelfCard, in: Capsule())
                    .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { ShelfPanelController.shared.hide() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.shelfInk).frame(width: 36, height: 36)
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
                            row("未 Pin 的内容保留") {
                                HStack(spacing: 4) {
                                    ForEach([(1, "1 天"), (3, "3 天"), (7, "7 天"), (30, "30 天"), (365, "一年")], id: \.0) { days, label in
                                        let on = prefs.retentionDays == days
                                        Button { prefs.retentionDays = days } label: {
                                            Text(label).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                                .foregroundStyle(on ? Color.onPurple : Color.shelfInk)
                                                .padding(.horizontal, 11).padding(.vertical, 6)
                                                .background(on ? Color.purple : Color.white.opacity(0.06), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .background(Color.black.opacity(0.25), in: Capsule())
                                .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
                            }
                            row("当日清理时间") { HourWheel(hour: $prefs.cleanupHour) }
                            row("图片自动识别文字（可按文字搜图）") { Toggle("", isOn: $prefs.ocrImages).labelsHidden().toggleStyle(.switch).tint(Color.purple) }
                            row("暂停同步至剪贴板") { Toggle("", isOn: $prefs.paused).labelsHidden().toggleStyle(.switch).tint(Color.purple) }
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
                                        .font(.system(size: 12)).foregroundStyle(Color.shelfMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing)
                                    if !prefs.exportDir.isEmpty { pill("默认") { prefs.exportDir = "" } }
                                    pill("选择…") { chooseFolder() }
                                }
                            }
                            row("剪贴板内容临时存放位置") {
                                HStack(spacing: 8) {
                                    Text((ClipStore.shared.root.path as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12)).foregroundStyle(Color.shelfMuted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing)
                                    if Preferences.shared.customStoreDir != nil { pill("默认") { relocateStore(to: nil) } }
                                    pill("选择…") { chooseStoreFolder() }
                                    pill("打开") { NSWorkspace.shared.open(ClipStore.shared.root) }
                                }
                            }
                            if let e = storeError { Text(e).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)).padding(.horizontal, 16) }
                        }
                        section("系统") {
                            row("登录时启动") { Toggle("", isOn: $prefs.launchAtLogin).labelsHidden().toggleStyle(.switch).tint(Color.purple) }
                            if let e = prefs.loginError { Text(e).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)).padding(.horizontal, 16) }
                            row("屏幕录制权限（截图、录屏需要）") {
                                HStack(spacing: 8) {
                                    Text(Permissions.hasScreenRecording ? "已授权" : "未授权")
                                        .font(.system(size: 12)).foregroundStyle(Permissions.hasScreenRecording ? Color.purple : Color(nsColor: Theme.tagMP4))
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
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.shelfMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .background(Color.shelfCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.shelfBorder, lineWidth: 1))
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.shelfInk).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.shelfInk)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.shelfInk)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func chooseStoreFolder() {
        let shelf = ShelfPanelController.shared
        shelf.holdOpen = true
        defer { shelf.holdOpen = false; shelf.refocus() }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "用这个文件夹"
        panel.message = "现有内容会复制过去；原文件夹保留，可以自己删。"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { relocateStore(to: url) }
    }

    private func relocateStore(to url: URL?) {
        do { try ClipStore.shared.relocate(to: url); storeError = nil }
        catch { storeError = "搬不过去：\(error.localizedDescription)" }
    }

    private func chooseFolder() {
        let shelf = ShelfPanelController.shared
        shelf.holdOpen = true
        defer { shelf.holdOpen = false; shelf.refocus() }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "选择"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { prefs.exportDir = url.path }
    }
}

/// One-line hour control: scroll up / down over it (trackpad or wheel) to change; tiny ▲▼ for clicking.
struct HourWheel: View {
    @Binding var hour: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(Color.shelfInk)
                .frame(width: 58)
            VStack(spacing: 0) {
                Button { hour = (hour + 23) % 24 } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 11) }
                Button { hour = (hour + 1) % 24 } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 11) }
            }
            .buttonStyle(.plain).foregroundStyle(Color.shelfMuted)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
        .background(Color.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
        .overlay(ScrollSteps { step in hour = (hour + step + 24) % 24 }.allowsHitTesting(true))
        .help("上下滑动或点箭头调整")
    }
}

/// Transparent view that turns scroll-wheel motion into +1 / -1 steps.
struct ScrollSteps: NSViewRepresentable {
    let onStep: (Int) -> Void
    func makeNSView(context: Context) -> StepView { let v = StepView(); v.onStep = onStep; return v }
    func updateNSView(_ v: StepView, context: Context) { v.onStep = onStep }
    final class StepView: NSView {
        var onStep: ((Int) -> Void)?
        private var acc: CGFloat = 0
        override func scrollWheel(with event: NSEvent) {
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
