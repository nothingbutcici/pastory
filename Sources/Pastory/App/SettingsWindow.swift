import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement
import SwiftUI

/// Settings live inside the shelf; this opens the shelf on its settings page.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    func show() {
        let shelf = ShelfPanelController.shared
        if !shelf.isVisible { shelf.show() }
        shelf.model.showSettings = true
    }
}

@Observable
final class PrefsMirror {
    var retentionDays: Int { didSet { Preferences.shared.retentionDays = retentionDays; Task { @MainActor in Retention.sweep(); Retention.reschedule(); ShelfPanelController.shared.model.prefsTick += 1 } } }
    var cleanupHour: Int { didSet { Preferences.shared.cleanupHour = cleanupHour; Task { @MainActor in Retention.reschedule() } } }
    var exportDir: String { didSet { Preferences.shared.customExportDir = exportDir.isEmpty ? nil : exportDir } }
    var paused: Bool { didSet { Preferences.shared.monitoringPaused = paused } }
    var imageStorage: String { get { access(keyPath: \.imageStorage); return Preferences.shared.imageStorage } set { withMutation(keyPath: \.imageStorage) { Preferences.shared.imageStorage = newValue } } }
    var pasteMode: String { get { access(keyPath: \.pasteMode); return Preferences.shared.pasteMode } set { withMutation(keyPath: \.pasteMode) { Preferences.shared.pasteMode = newValue } } }
    var checkForUpdates: Bool { get { access(keyPath: \.checkForUpdates); return Preferences.shared.checkForUpdates } set { withMutation(keyPath: \.checkForUpdates) { Preferences.shared.checkForUpdates = newValue } } }
    var recordPasswordManagers: Bool { get { access(keyPath: \.recordPasswordManagers); return Preferences.shared.recordPasswordManagers } set { withMutation(keyPath: \.recordPasswordManagers) { Preferences.shared.recordPasswordManagers = newValue } } }
    var recordHEVC: Bool { get { access(keyPath: \.recordHEVC); return Preferences.shared.recordHEVC } set { withMutation(keyPath: \.recordHEVC) { Preferences.shared.recordHEVC = newValue } } }
    var desktopNoteLayer: String { get { access(keyPath: \.desktopNoteLayer); return Preferences.shared.desktopNoteLayer } set { withMutation(keyPath: \.desktopNoteLayer) { Preferences.shared.desktopNoteLayer = newValue; Task { @MainActor in DesktopNotes.shared.applyLayer() } } } }
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
        retentionDays = p.retentionDays; cleanupHour = p.cleanupHour; exportDir = p.customExportDir ?? ""
        paused = p.monitoringPaused
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Click, press a combo. ⎋ cancels, ⌫ clears. A combo held by another app, or already used by one of
/// our own shortcuts, is refused on the spot and the old value stays.
struct ShortcutRecorder: View {
    let key: String
    /// Welcome card: one paper keycap per key instead of the compact capsule.
    var keycaps = false
    /// Welcome card: notices ("taken", "at least two keys"…) go to the row's own status line instead of inline.
    var status: Binding<String?>? = nil
    var bindingName: String {
        switch key {
        case Preferences.Key.hotkeyCapture: return "capture"
        case Preferences.Key.hotkeySearch: return "search"
        default: return "shelf"
        }
    }
    @State private var shortcut: Shortcut = .none
    @State private var capturing = false
    @State private var monitor: Any?
    @State private var taken = false
    @State private var notice: String?
    @State private var flagsMonitor: Any?
    @State private var resignObserver: Any?
    @State private var clickMonitor: Any?
    @State private var keyLossObserver: Any?
    @State private var lastCancel = Date.distantPast
    @State private var sawModifiers = false
    @State private var sawKey = false

    private static let names = ["capture": "截图", "shelf": "剪贴板", "search": "搜索剪贴板"]      // translated at use

    var body: some View {
        if keycaps { keycapBody } else { capsuleBody }
    }

    private var keycapBody: some View {
        HStack(spacing: 10) {
            if status == nil, let notice, !capturing { Text(notice).font(.serif(12)).foregroundStyle(Color.inkMuted) }
            Button {
                if !capturing, Date().timeIntervalSince(lastCancel) > 0.4 { startCapture() }
            } label: {
                HStack(spacing: 6) {
                    if capturing || !shortcut.isSet {
                        Text(capturing ? "按下组合键".l : "立即设置".l).font(.serif(13)).foregroundStyle(Color.ink)
                            .padding(.horizontal, 12).frame(height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ink.opacity(capturing ? 0.9 : 0.4), lineWidth: 1))
                    } else {
                        ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in keycap(cap) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if shortcut.isSet, !capturing {
                Button { stop(Shortcut.none) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.inkMuted)
                        .frame(width: 20, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("不设快捷键".l)
            }
        }
        .onAppear { shortcut = Preferences.shared.shortcut(key); refreshTaken(); publishStatus() }
        .onDisappear { stop(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutBindingChanged)) { _ in refreshTaken(); publishStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutsChanged)) { _ in if !capturing { shortcut = Preferences.shared.shortcut(key) } }
        .onChange(of: notice) { _, _ in publishStatus() }
        .onChange(of: capturing) { _, _ in publishStatus() }
        .onChange(of: taken) { _, _ in publishStatus() }
    }

    private func publishStatus() {
        guard let status else { return }
        let text: String? = capturing ? nil : (notice ?? (taken ? "被其他应用占用，点击换一个".l : nil))
        if status.wrappedValue != text { status.wrappedValue = text }
    }

    private func keycap(_ s: String) -> some View {
        Text(s).font(.system(size: s.count > 1 ? 11 : 13, weight: .medium)).foregroundStyle(Color.ink)
            .frame(minWidth: 28, minHeight: 28).padding(.horizontal, s.count > 1 ? 7 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Color.paper)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink.opacity(0.18), lineWidth: 1))
    }

    private var capsuleBody: some View {
        HStack(spacing: 8) {
            if let notice, !capturing { Text(notice).font(.system(size: 12)).foregroundStyle(Color.inkMuted) }
            else if taken, !capturing { Text("被其他应用占用".l).font(.system(size: 12)).foregroundStyle(Color.inkMuted) }
            HStack(spacing: 6) {
                Button {
                    // The click-anywhere monitor already cancelled on mouse-down; do not re-arm on the mouse-up.
                    if !capturing, Date().timeIntervalSince(lastCancel) > 0.4 { startCapture() }
                } label: {
                    Text(capturing ? "按下组合键".l : shortcut.display)
                        .font(.system(size: 13, weight: .medium).monospaced())
                        .foregroundStyle(shortcut.isSet || capturing ? Color.ink : Color.inkMuted)
                        .frame(minWidth: 96)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Clear lives inside the box, gray; the action then stays reachable from the menu.
                if shortcut.isSet, !capturing {
                    Button { stop(Shortcut.none) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color.inkMuted)
                    }
                    .buttonStyle(.plain).help("不设快捷键".l)
                }
            }
            .padding(.leading, 12).padding(.trailing, shortcut.isSet && !capturing ? 8 : 12).padding(.vertical, 7)
            .background(capturing ? Color.paperBlue : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
        }
        .onAppear { shortcut = Preferences.shared.shortcut(key); refreshTaken() }
        .onDisappear { stop(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutBindingChanged)) { _ in refreshTaken() }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutsChanged)) { _ in if !capturing { shortcut = Preferences.shared.shortcut(key) } }
    }

    private func refreshTaken() { taken = HotKeyCenter.shared.failed.contains(bindingName) }

    private func startCapture() {
        capturing = true
        notice = nil
        sawModifiers = false
        sawKey = false
        HotKeyCenter.shared.suspend()          // otherwise our own combos fire instead of reaching this box
        // Any click while waiting = never mind.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            DispatchQueue.main.async { if capturing { stop(nil) } }
            return event
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sawKey = true
            if event.keyCode == 53 { stop(nil) }
            else if event.keyCode == 51 { stop(Shortcut.none) }
            else if let s = Shortcut(event: event) { stop(s) }
            else { stop(nil); notice = "至少两个键：⌘ ⌥ ⌃ ⇧ 中的一个加一个键".l }
            return nil
        }
        // A combo another app already owns as a global hotkey is swallowed before it reaches us: we only ever
        // see the modifiers go down and come back up. That silence is the signal.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if !mods.isEmpty { sawModifiers = true; sawKey = false }
            else if sawModifiers, !sawKey, capturing {
                notice = "没收到按键。如果对方应用弹出来了，说明这个组合已被它占用".l
            }
            return event
        }
        // Feishu / WeChat screenshot hotkeys bring their own UI to the front, so we never even see the
        // modifiers come back up. Losing active status mid-recording with no key received means the same thing.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            if capturing, sawModifiers, !sawKey { swallowed() }
        }
        // The shelf itself going away (clicked another app) must end recording, or our hotkeys stay suspended.
        keyLossObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { n in
            let isShelf = (n.object as? NSWindow) is ShelfPanel
            MainActor.assumeIsolated {
                if capturing, isShelf, !ShelfPanelController.shared.holdOpen { stop(nil) }
            }
        }
    }

    private func swallowed() {
        stop(nil)
        notice = "已被其他应用占用，换一个".l
        // If the owner brought itself to the front, we can name it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let app = NSWorkspace.shared.frontmostApplication, app != NSRunningApplication.current, let name = app.localizedName {
                notice = String(format: "已被 %@ 占用，换一个".l, name)
            }
        }
    }

    private func stop(_ newValue: Shortcut?) {
        guard capturing || newValue != nil else { return }      // onDisappear on an idle recorder must not touch the hotkey suspend count
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyLossObserver { NotificationCenter.default.removeObserver(keyLossObserver) }
        keyLossObserver = nil
        clickMonitor = nil
        if newValue == nil { lastCancel = Date() }
        monitor = nil
        flagsMonitor = nil
        resignObserver = nil
        capturing = false
        HotKeyCenter.shared.resume()
        guard let newValue else { return }
        notice = nil
        if newValue.isSet {
            let mine: [(String, String)] = [("capture", Preferences.Key.hotkeyCapture), ("shelf", Preferences.Key.hotkeyShelf), ("search", Preferences.Key.hotkeySearch)]
            if let (owner, _) = mine.first(where: { $0.0 != bindingName && Preferences.shared.shortcut($0.1) == newValue }) {
                notice = String(format: "已被 Pastory 的「%@」占用，换一个".l, (Self.names[owner] ?? owner).l)
                return
            }
            if !HotKeyCenter.shared.isAvailable(newValue) {
                notice = "已被其他应用占用，换一个".l
                return
            }
        }
        shortcut = newValue
        Preferences.shared.setShortcut(newValue, for: key)
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
        // Saved. A bare ⌘/⇧ combo is legal but global: say so once instead of refusing.
        if newValue.isSet {
            let m = newValue.carbonModifiers
            if m == UInt32(cmdKey) || m == UInt32(shiftKey) || m == UInt32(cmdKey | shiftKey) {
                notice = String(format: "已设置。注意：所有应用里的 %@ 都会变成这个功能".l, newValue.display)
            }
        }
    }
}
