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
        guard isSet else { return "未设置".l }
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCodeNames.name(for: keyCode)
    }

    /// One string per key, modifiers first: ["⌃", "⌘", "Z"].
    var keycaps: [String] {
        guard isSet else { return [] }
        var caps: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { caps.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { caps.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { caps.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { caps.append("⌘") }
        caps.append(KeyCodeNames.name(for: keyCode))
        return caps
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
    /// Self-tests (PASTORY_STORE set) get a throwaway suite so they never touch the user's real preferences.
    private let d: UserDefaults = {
        if Sandbox.store != nil, let suite = UserDefaults(suiteName: "com.cici.snipclip.selftest") {
            suite.removePersistentDomain(forName: "com.cici.snipclip.selftest")
            return suite
        }
        return .standard
    }()

    enum Key {
        static let hotkeyCapture = "hotkeyCapture"
        static let hotkeyShelf = "hotkeyShelf"
        static let hotkeySearch = "hotkeySearch"
        static let retentionDays = "retentionDays"
        static let cleanupHour = "cleanupHour"
        static let exportDir = "exportDir"
        static let monitoringPaused = "monitoringPaused"
    }

    private init() {
        d.register(defaults: [
            Key.hotkeyCapture: Shortcut(keyCode: 1, carbonModifiers: UInt32(optionKey | cmdKey)).encoded,  // ⌥⌘S（⌃⌘A 被微信占用）
            Key.hotkeyShelf: Shortcut(keyCode: 9, carbonModifiers: UInt32(shiftKey | cmdKey)).encoded,     // ⇧⌘V
            Key.hotkeySearch: Shortcut(keyCode: 3, carbonModifiers: UInt32(optionKey | cmdKey)).encoded,   // ⌥⌘F
            Key.retentionDays: 0,          // keep everything until the user picks a schedule; a stored value means they did
            Key.cleanupHour: 4,
            Key.monitoringPaused: false,
        ])
    }

    /// Notes on the desktop: [{id, x, y, w, h, top}] in screen coordinates; `top` = floats above windows.
    var desktopNotes: [[String: Any]] {
        get { d.array(forKey: "desktopNotes") as? [[String: Any]] ?? [] }
        set { d.set(newValue, forKey: "desktopNotes") }
    }

    /// One-time hint after the first Pin: cards can be dragged out onto the desktop.
    var sawDragHint: Bool { get { d.bool(forKey: "sawDragHint") } set { d.set(newValue, forKey: "sawDragHint") } }
    /// Onboarding checklist: which of the two shortcuts has actually been used once.
    var welcomeTried: Set<String> {
        get { Set(d.stringArray(forKey: "welcomeTried") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "welcomeTried") }
    }

    func shortcut(_ key: String) -> Shortcut {
        guard let raw = d.string(forKey: key), let s = Shortcut(encoded: raw) else { return .none }
        return s
    }
    func setShortcut(_ s: Shortcut, for key: String) { d.set(s.encoded, forKey: key) }

    /// Calendar days kept for unpinned items. 1 = yesterday and earlier go at the cleanup hour. 0 = never clean up.
    var retentionDays: Int {
        get { max(0, d.integer(forKey: Key.retentionDays)) }
        set { d.set(max(0, newValue), forKey: Key.retentionDays) }
    }
    var neverCleans: Bool { retentionDays == 0 }
    /// Hour of day (0–23) when expired items are cleared.
    var cleanupHour: Int {
        get { min(23, max(0, d.integer(forKey: Key.cleanupHour))) }
        set { d.set(min(23, max(0, newValue)), forKey: Key.cleanupHour) }
    }
    var monitoringPaused: Bool { get { d.bool(forKey: Key.monitoringPaused) } set { d.set(newValue, forKey: Key.monitoringPaused) } }
    /// How new screenshots are stored: "heic" (quality 0.9, about a third of the size, default) or "png" (lossless).
    var imageStorage: String { get { d.string(forKey: "imageStorage") ?? "heic" } set { d.set(newValue, forKey: "imageStorage") } }
    var storesHEIC: Bool { imageStorage == "heic" }
    /// Off: copies made in password managers (and anything marked concealed) are never recorded.
    var recordPasswordManagers: Bool { get { d.bool(forKey: "recordPasswordManagers") } set { d.set(newValue, forKey: "recordPasswordManagers") } }
    /// Double-click also sends ⌘V to the app you came from (needs Accessibility). On by default; falls back to copy-only.
    /// "off" | "double" | "return". Until it is chosen, the legacy on/off switch decides between "off" and "double",
    /// so nobody's Return key starts typing into other apps after an update.
    var pasteMode: String {
        get {
            if let m = d.string(forKey: "pasteMode"), ["off", "double", "return"].contains(m) { return m }
            return (d.object(forKey: "pasteOnDoubleClick") as? Bool ?? true) ? "double" : "off"
        }
        set { d.set(newValue, forKey: "pasteMode") }
    }
    var pasteOnDoubleClick: Bool { pasteMode != "off" }
    var pasteOnReturn: Bool { pasteMode == "return" }
    /// Daily update check against GitHub Releases (the app's only network request). On by default.
    var checkForUpdates: Bool { get { d.object(forKey: "checkForUpdates") as? Bool ?? true } set { d.set(newValue, forKey: "checkForUpdates") } }
    var lastUpdateCheck: Date? { get { d.object(forKey: "lastUpdateCheck") as? Date } set { d.set(newValue, forKey: "lastUpdateCheck") } }
    var skippedVersion: String? { get { d.string(forKey: "skippedVersion") } set { d.set(newValue, forKey: "skippedVersion") } }
    /// Recordings: H.264 (compatible) or HEVC (smaller). Resolution is always the display's own.
    var recordHEVC: Bool { get { d.bool(forKey: "recordHEVC") } set { d.set(newValue, forKey: "recordHEVC") } }
    /// "system" (follow macOS), "zh" or "en".
    var language: String { get { d.string(forKey: "language") ?? "system" } set { d.set(newValue, forKey: "language"); L.languageChanged() } }
    /// First launch on this Mac: the shelf opens once by itself, so a menu-bar-only app does not look like it failed to start.
    var didWelcome: Bool { get { d.bool(forKey: "didWelcome") } set { d.set(newValue, forKey: "didWelcome") } }

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
    static let shortcutsChanged = Notification.Name("pastory.shortcutsChanged")
    /// Posted after (re)binding, so the settings UI can show which ones were refused.
    static let shortcutBindingChanged = Notification.Name("pastory.shortcutBindingChanged")
}
