import AppKit
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

/// Click, press a combo. ⎋ cancels, ⌫ clears.
struct ShortcutRecorder: View {
    let key: String
    var bindingName: String { key == Preferences.Key.hotkeyCapture ? "capture" : "shelf" }
    @State private var shortcut: Shortcut = .none
    @State private var capturing = false
    @State private var monitor: Any?
    @State private var taken = false

    var body: some View {
        HStack(spacing: 8) {
            if taken, !capturing { Text("被其他应用占用").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.tagMP4)) }
            Button { capturing ? stop(nil) : startCapture() } label: {
                Text(capturing ? "按下组合键…" : shortcut.display)
                    .font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundStyle(capturing ? Color.onPurple : Color.shelfInk)
                    .frame(minWidth: 110)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(capturing ? Color.purple : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(taken ? Color(nsColor: Theme.tagMP4) : Color.shelfBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
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
