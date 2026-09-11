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
        if !ok { failed.insert(name) }
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

    func unbind(_ name: String) {
        guard let entry = refs.removeValue(forKey: name) else { return }
        UnregisterEventHotKey(entry.ref)
        actions.removeValue(forKey: entry.id)
    }
}
