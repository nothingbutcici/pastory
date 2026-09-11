import AppKit
import CoreGraphics

enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Gate before every screenshot.
    @MainActor
    static func ensureScreenRecording() -> Bool {
        if hasScreenRecording { return true }
        _ = requestScreenRecording()
        if hasScreenRecording { return true }
        let alert = NSAlert()
        alert.messageText = "Snip Clip 还没有屏幕录制权限"
        alert.informativeText = "打开「系统设置 › 隐私与安全性 › 屏幕录制」，勾选 Snip Clip，然后重新启动。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openSettings("Privacy_ScreenCapture") }
        return false
    }
}
