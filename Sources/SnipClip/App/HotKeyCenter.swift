import AppKit
import Carbon.HIToolbox

/// Global shortcuts via Carbon RegisterEventHotKey — no Accessibility permission needed.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [String: (id: UInt32, ref: EventHotKeyRef)] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    /// Names whose last bind was refused (another app owns the combo).
    private(set) var failed: Set<String> = []

    private init() {}

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard status == noErr else { return status }
            let id = hkID.id
            DispatchQueue.main.async { HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    @discardableResult
    func bind(_ shortcut: Shortcut, name: String, action: @escaping () -> Void) -> Bool {
        unbind(name)
        failed.remove(name)
        guard shortcut.isSet else { return true }
        let ok = bindRaw(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, name: name, action: action)
        if ok { shortcuts[name] = shortcut } else { failed.insert(name) }
        return ok
    }

    /// Modifier-less keys allowed (used for Esc while the picker is up). Unbind promptly.
    @discardableResult
    func bindRaw(keyCode: UInt32, modifiers: UInt32, name: String, action: @escaping () -> Void) -> Bool {
        unbind(name)
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_434C), id: id) // SNCL
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        actions[id] = action
        refs[name] = (id, ref)
        return true
    }

    /// Can this combo be registered right now (i.e. no other app holds it)? Registers and releases immediately.
    /// Our own bindings are released around the probe so they do not count as "taken".
    func isAvailable(_ shortcut: Shortcut) -> Bool {
        guard shortcut.isSet else { return true }
        installHandlerIfNeeded()
        let held = refs.filter { $0.value.ref != nil }
        var ownsSame = false
        for (name, entry) in refs {
            _ = name
            if let s = shortcuts[name], s == shortcut { ownsSame = true }
            _ = entry
        }
        if ownsSame { return true }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x534E_434C), id: 0xFFFF)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { UnregisterEventHotKey(ref); return true }
        _ = held
        return false
    }

    /// Which of our own bindings already uses this combo (for "和「截图」重复" messages).
    func ownerName(of shortcut: Shortcut) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }
    private var shortcuts: [String: Shortcut] = [:]

    private var suspended: [(name: String, shortcut: Shortcut, action: () -> Void)] = []

    /// Release every binding (recorder is listening); `resume()` puts them back.
    func suspend() {
        suspended = refs.keys.compactMap { name in
            guard let s = shortcuts[name], let id = refs[name]?.id, let action = actions[id] else { return nil }
            return (name, s, action)
        }
        for name in refs.keys.map({ $0 }) { unbind(name) }
    }
    func resume() {
        let list = suspended
        suspended = []
        for b in list { _ = bind(b.shortcut, name: b.name, action: b.action) }
    }

    func unbind(_ name: String) {
        shortcuts[name] = nil
        guard let entry = refs.removeValue(forKey: name) else { return }
        UnregisterEventHotKey(entry.ref)
        actions.removeValue(forKey: entry.id)
    }
}
