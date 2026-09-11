import AppKit
import Carbon.HIToolbox

/// A Carbon-registerable shortcut.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let none = Shortcut(keyCode: 0, carbonModifiers: 0)
    var isSet: Bool { carbonModifiers != 0 }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
    }

    var display: String {
        guard isSet else { return "未设置" }
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCodeNames.name(for: keyCode)
    }

    var encoded: String { "\(keyCode):\(carbonModifiers)" }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]) else { return nil }
        keyCode = k
        carbonModifiers = m
    }
}

enum KeyCodeNames {
    private static let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
    static func name(for code: UInt32) -> String { table[code] ?? "Key\(code)" }
}

/// UserDefaults-backed settings.
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    enum Key {
        static let hotkeyCapture = "hotkeyCapture"
        static let hotkeyShelf = "hotkeyShelf"
        static let retentionDays = "retentionDays"
        static let exportDir = "exportDir"
        static let monitoringPaused = "monitoringPaused"
        static let ocrImages = "ocrImages"
    }

    private init() {
        d.register(defaults: [
            Key.hotkeyCapture: Shortcut(keyCode: 1, carbonModifiers: UInt32(optionKey | cmdKey)).encoded,  // ⌥⌘S（⌃⌘A 被微信占用）
            Key.hotkeyShelf: Shortcut(keyCode: 9, carbonModifiers: UInt32(shiftKey | cmdKey)).encoded,     // ⇧⌘V
            Key.retentionDays: 1,
            Key.monitoringPaused: false,
            Key.ocrImages: true
        ])
    }

    func shortcut(_ key: String) -> Shortcut {
        guard let raw = d.string(forKey: key), let s = Shortcut(encoded: raw) else { return .none }
        return s
    }
    func setShortcut(_ s: Shortcut, for key: String) { d.set(s.encoded, forKey: key) }

    /// Unpinned items older than this many "days" (4 am boundary) are cleared. 1 = clear yesterday's.
    var retentionDays: Int {
        get { max(1, d.integer(forKey: Key.retentionDays)) }
        set { d.set(max(1, newValue), forKey: Key.retentionDays) }
    }
    var monitoringPaused: Bool { get { d.bool(forKey: Key.monitoringPaused) } set { d.set(newValue, forKey: Key.monitoringPaused) } }
    var ocrImages: Bool { get { d.bool(forKey: Key.ocrImages) } set { d.set(newValue, forKey: Key.ocrImages) } }

    var customExportDir: String? {
        get { d.string(forKey: Key.exportDir) }
        set { d.set(newValue, forKey: Key.exportDir) }
    }
    /// ~/Downloads unless overridden. Created on demand.
    func exportDirectory() -> URL {
        let fm = FileManager.default
        let dir: URL
        if let p = customExportDir, !p.isEmpty {
            dir = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        }
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("snipclip.shortcutsChanged")
    /// Posted after (re)binding, so the settings UI can show which ones were refused.
    static let shortcutBindingChanged = Notification.Name("snipclip.shortcutBindingChanged")
}
