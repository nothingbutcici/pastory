import SwiftUI

/// Settings, rendered in the shelf's right half in the shelf's own look.
struct SettingsPane: View {
    @Bindable var model: ShelfModel
    @State private var prefs = PrefsMirror()
    @State private var cleared = false

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
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        section("快捷键") {
                            row("截图") { ShortcutRecorder(key: Preferences.Key.hotkeyCapture) }
                            row("显示 / 隐藏剪贴板") { ShortcutRecorder(key: Preferences.Key.hotkeyShelf) }
                        }
                        section("剪贴板") {
                            row("未 Pin 的内容保留") {
                                Picker("", selection: $prefs.retentionDays) {
                                    Text("到次日 04:00").tag(1); Text("3 天").tag(3); Text("7 天").tag(7); Text("30 天").tag(30)
                                }
                                .labelsHidden().frame(width: 150)
                            }
                            row("图片自动识别文字（可按文字搜图）") { Toggle("", isOn: $prefs.ocrImages).labelsHidden().toggleStyle(.switch).tint(Color.lime) }
                            row("暂停记录") { Toggle("", isOn: $prefs.paused).labelsHidden().toggleStyle(.switch).tint(Color.lime) }
                            row("\(ClipStore.shared.items.count) 项，其中 Pin \(ClipStore.shared.items.filter(\.pinned).count) 项") {
                                pill(cleared ? "已清空" : "清空未 Pin 的", disabled: cleared) {
                                    ClipStore.shared.removeAll { !$0.pinned }
                                    cleared = true
                                }
                            }
                        }
                    }
                    VStack(spacing: 16) {
                        section("「保存到本地」默认打开的文件夹") {
                            row(prefs.exportDir.isEmpty ? "~/Downloads" : (prefs.exportDir as NSString).abbreviatingWithTildeInPath) {
                                HStack(spacing: 8) {
                                    if !prefs.exportDir.isEmpty { pill("默认") { prefs.exportDir = "" } }
                                    pill("选择…") { chooseFolder() }
                                }
                            }
                        }
                        section("系统") {
                            row("登录时启动") { Toggle("", isOn: $prefs.launchAtLogin).labelsHidden().toggleStyle(.switch).tint(Color.lime) }
                            if let e = prefs.loginError { Text(e).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)).padding(.horizontal, 16) }
                            row("屏幕录制权限（截图、录屏需要）") {
                                HStack(spacing: 8) {
                                    Text(Permissions.hasScreenRecording ? "已授权" : "未授权")
                                        .font(.system(size: 12)).foregroundStyle(Permissions.hasScreenRecording ? Color.lime : Color(nsColor: Theme.tagMP4))
                                    pill("系统设置") { Permissions.openSettings("Privacy_ScreenCapture") }
                                }
                            }
                            row("存储位置") { pill("在 Finder 中打开") { NSWorkspace.shared.open(ClipStore.shared.root) } }
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
