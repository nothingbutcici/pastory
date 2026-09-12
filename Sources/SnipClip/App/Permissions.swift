import AppKit
import CoreGraphics

enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }
    /// The system's own dialog is shown at most once per launch; after that it is our alert, which can relaunch.
    private static var askedSystemThisLaunch = false

    @discardableResult
    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        guard !askedSystemThisLaunch else { return false }
        askedSystemThisLaunch = true
        return CGRequestScreenCaptureAccess()
    }

    static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Gate before every screenshot. A grant made while we are running only takes effect after a relaunch,
    /// so the alert offers exactly that instead of sending people back to Settings again and again.
    @MainActor
    static func ensureScreenRecording() -> Bool {
        if hasScreenRecording { return true }
        _ = requestScreenRecording()
        if hasScreenRecording { return true }
        let alert = NSAlert()
        alert.messageText = "Pastory 还没有屏幕录制权限"
        alert.informativeText = "在「系统设置 › 隐私与安全性 › 屏幕录制」里打开 Pastory。已经打开了的话，权限要重新启动后才生效。"
        alert.addButton(withTitle: "我已打开，重新启动 Pastory")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: relaunch()
        case .alertSecondButtonReturn: openSettings("Privacy_ScreenCapture")
        default: break
        }
        return false
    }

    /// Start a fresh copy of ourselves, then quit this one.
    @MainActor
    static func relaunch() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, error in
            if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }      // if the new copy did not start, stay alive
        }
    }
}
