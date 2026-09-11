import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private init() {}

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Snip Clip 设置"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView())
            window = w
        }
        ShelfPanelController.shared.hide()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@Observable
final class PrefsMirror {
    var retentionDays: Int { didSet { Preferences.shared.retentionDays = retentionDays } }
    var exportDir: String { didSet { Preferences.shared.customExportDir = exportDir.isEmpty ? nil : exportDir } }
    var ocrImages: Bool { didSet { Preferences.shared.ocrImages = ocrImages } }
    var paused: Bool { didSet { Preferences.shared.monitoringPaused = paused } }
    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
        }
    }
    var loginError: String?

    init() {
        let p = Preferences.shared
        retentionDays = p.retentionDays; exportDir = p.customExportDir ?? ""
        ocrImages = p.ocrImages; paused = p.monitoringPaused
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @State private var prefs = PrefsMirror()
    @State private var cleared = false

    var body: some View {
        Form {
            Section("快捷键") {
                ShortcutRow(title: "截图", key: Preferences.Key.hotkeyCapture)
                ShortcutRow(title: "显示 / 隐藏剪贴板", key: Preferences.Key.hotkeyShelf)
            }
            Section("剪贴板") {
                Picker("未固定的内容保留", selection: $prefs.retentionDays) {
                    Text("到次日凌晨 4 点").tag(1)
                    Text("3 天").tag(3)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                Toggle("为图片自动识别文字（可按文字搜图）", isOn: $prefs.ocrImages)
                Toggle("暂停记录", isOn: $prefs.paused)
                HStack {
                    Text("\(ClipStore.shared.items.count) 项，其中固定 \(ClipStore.shared.items.filter(\.pinned).count) 项")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(cleared ? "已清空" : "清空未固定的") {
                        ClipStore.shared.removeAll { !$0.pinned }
                        cleared = true
                    }.disabled(cleared)
                }
            }
            Section("「保存到本地」的位置") {
                HStack {
                    Text(prefs.exportDir.isEmpty ? "~/Downloads" : prefs.exportDir)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("选择…") { chooseFolder() }
                    if !prefs.exportDir.isEmpty { Button("默认") { prefs.exportDir = "" } }
                }
            }
            Section("系统") {
                Toggle("登录时启动", isOn: $prefs.launchAtLogin)
                if let e = prefs.loginError { Text(e).font(.caption).foregroundStyle(.orange) }
                PermissionRow(title: "屏幕录制（截图需要）", granted: Permissions.hasScreenRecording) {
                    Permissions.openSettings("Privacy_ScreenCapture")
                }
                HStack {
                    Text("存储位置").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("在 Finder 中打开") { NSWorkspace.shared.open(ClipStore.shared.root) }.controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { prefs.exportDir = url.path }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权").font(.caption).foregroundStyle(.secondary)
            Button("打开设置", action: action).controlSize(.small)
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let key: String
    /// HotKeyCenter binding name for this row.
    var bindingName: String { key == Preferences.Key.hotkeyCapture ? "capture" : "shelf" }
    @State private var shortcut: Shortcut = .none
    @State private var capturing = false
    @State private var monitor: Any?
    @State private var taken = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if taken, !capturing {
                Text("被其他应用占用").font(.caption).foregroundStyle(.orange)
            }
            Button(capturing ? "按下组合键…" : shortcut.display) { capturing ? stop(nil) : startCapture() }
                .frame(minWidth: 130)
                .foregroundStyle(capturing ? Color.accentColor : (taken ? Color.orange : Color.primary))
        }
        .onAppear { shortcut = Preferences.shared.shortcut(key); refreshTaken() }
        .onDisappear { stop(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutBindingChanged)) { _ in refreshTaken() }
    }

    private func refreshTaken() { taken = HotKeyCenter.shared.failed.contains(bindingName) }

    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(nil) }
            else if event.keyCode == 51 { stop(Shortcut.none) }
            else if let s = Shortcut(event: event) { stop(s) }
            return nil
        }
    }

    private func stop(_ newValue: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
        guard let newValue else { return }
        shortcut = newValue
        Preferences.shared.setShortcut(newValue, for: key)
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}
