import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement
import SwiftUI

/// Settings live inside the shelf now; this shim keeps the old call sites working.
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
    var retentionDays: Int { didSet { Preferences.shared.retentionDays = retentionDays; Task { @MainActor in Retention.sweep(); Retention.reschedule() } } }
    var cleanupHour: Int { didSet { Preferences.shared.cleanupHour = cleanupHour; Task { @MainActor in Retention.reschedule() } } }
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
        retentionDays = p.retentionDays; cleanupHour = p.cleanupHour; exportDir = p.customExportDir ?? ""
        ocrImages = p.ocrImages; paused = p.monitoringPaused
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Click, press a combo. ⎋ cancels, ⌫ clears. A combo held by another app, or already used by one of
/// our own shortcuts, is refused on the spot and the old value stays.
struct ShortcutRecorder: View {
    let key: String
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
    @State private var sawModifiers = false
    @State private var sawKey = false

    private static let names = ["capture": "截图", "shelf": "剪贴板", "search": "搜索剪贴板"]

    var body: some View {
        HStack(spacing: 8) {
            if let notice, !capturing { Text(notice).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)) }
            else if taken, !capturing { Text("被其他应用占用").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)) }
            Button { capturing ? stop(nil) : startCapture() } label: {
                Text(capturing ? "按下组合键，⌫ 清除" : shortcut.display)
                    .font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundStyle(capturing ? Color.onPurple : (shortcut.isSet ? Color.shelfInk : Color.shelfMuted))
                    .frame(minWidth: 110)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(capturing ? Color.purple : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(taken ? Color(nsColor: Theme.tagMP4) : Color.shelfBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // Not everyone wants every shortcut: clear it and the action stays reachable from the menu.
            if shortcut.isSet, !capturing {
                Button { stop(Shortcut.none) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color.shelfMuted)
                }
                .buttonStyle(.plain).help("不设快捷键")
            }
        }
        .onAppear { shortcut = Preferences.shared.shortcut(key); refreshTaken() }
        .onDisappear { stop(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutBindingChanged)) { _ in refreshTaken() }
    }

    private func refreshTaken() { taken = HotKeyCenter.shared.failed.contains(bindingName) }

    private func startCapture() {
        capturing = true
        notice = nil
        sawModifiers = false
        sawKey = false
        HotKeyCenter.shared.suspend()          // otherwise our own combos fire instead of reaching this box
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sawKey = true
            if event.keyCode == 53 { stop(nil) }
            else if event.keyCode == 51 { stop(Shortcut.none) }
            else if let s = Shortcut(event: event) { stop(s) }
            return nil
        }
        // A combo another app already owns as a global hotkey is swallowed before it reaches us: we only ever
        // see the modifiers go down and come back up. That silence is the signal.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if !mods.isEmpty { sawModifiers = true; sawKey = false }
            else if sawModifiers, !sawKey, capturing {
                swallowed()
            }
            return event
        }
        // Feishu / WeChat screenshot hotkeys bring their own UI to the front, so we never even see the
        // modifiers come back up. Losing active status mid-recording with no key received means the same thing.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            if capturing, !sawKey { swallowed() }
        }
    }

    private func swallowed() {
        stop(nil)
        notice = "已被其他应用占用，换一个"
        // If the owner brought itself to the front, we can name it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let app = NSWorkspace.shared.frontmostApplication, app != NSRunningApplication.current, let name = app.localizedName {
                notice = "已被 \(name) 占用，换一个"
            }
        }
    }

    private func stop(_ newValue: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        flagsMonitor = nil
        resignObserver = nil
        capturing = false
        HotKeyCenter.shared.resume()
        guard let newValue else { return }
        notice = nil
        if newValue.isSet {
            let m = newValue.carbonModifiers
            let onlyCmd = m == UInt32(cmdKey), onlyShift = m == UInt32(shiftKey), cmdShift = m == UInt32(cmdKey | shiftKey)
            let isFKey = KeyCodeNames.name(for: newValue.keyCode).hasPrefix("F")
            if (onlyCmd || onlyShift || cmdShift) && !isFKey {
                notice = "会抢走所有应用的 \(newValue.display)，加上 ⌥ 或 ⌃"
                return
            }
            let mine: [(String, String)] = [("capture", Preferences.Key.hotkeyCapture), ("shelf", Preferences.Key.hotkeyShelf), ("search", Preferences.Key.hotkeySearch)]
            if let (owner, _) = mine.first(where: { $0.0 != bindingName && Preferences.shared.shortcut($0.1) == newValue }) {
                notice = "已被 Pastory 的「\(Self.names[owner] ?? owner)」占用，换一个"
                return
            }
            if !HotKeyCenter.shared.isAvailable(newValue) {
                notice = "已被其他应用占用，换一个"
                return
            }
        }
        shortcut = newValue
        Preferences.shared.setShortcut(newValue, for: key)
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }
}
