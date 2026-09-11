import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Bottom drawer, Paste-style. Non-activating: the app you were in keeps focus,
/// so what you copy here you can paste right away.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    static let shared = ShelfPanelController()
    private var panel: NSPanel?
    let model = ShelfModel()

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let p = panel ?? makePanel()
        panel = p
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let height = max(320, (screen.frame.height * 0.45).rounded())
        let target = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        let start = target.offsetBy(dx: 0, dy: -height)
        model.reset()
        p.setFrame(start, display: false)
        p.alphaValue = 1
        p.orderFrontRegardless()
        p.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        let end = p.frame.offsetBy(dx: 0, dy: -p.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(end, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { p.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let p = ShelfPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 400),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.delegate = self
        p.contentView = NSHostingView(rootView: ShelfView(model: model))
        return p
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    // MARK: Keys (only while visible)

    fileprivate func handle(_ event: NSEvent) -> Bool {
        let typing = panel?.firstResponder is NSTextView
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            if typing, !model.query.isEmpty { model.query = ""; return true }
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.copySelected(); return true
        case kVK_LeftArrow where !typing: model.move(-1); return true
        case kVK_RightArrow where !typing: model.move(1); return true
        case kVK_ANSI_P where !typing || cmd: model.pinSelected(); return true
        case kVK_ANSI_S where !typing || cmd: model.exportSelected(); return true
        case kVK_Delete where !typing: model.deleteSelected(); return true
        case kVK_ANSI_F where cmd: model.focusSearch += 1; return true
        default: return false
        }
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Shortcuts are handled before the responder chain so the search field cannot swallow ⏎ / ⎋.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, ShelfPanelController.shared.handle(event) { return }
        super.sendEvent(event)
    }
}

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "全部", pinned = "固定", images = "图片", text = "文本"
    var id: String { rawValue }
}

@MainActor
@Observable
final class ShelfModel {
    var query = ""
    var filter: ShelfFilter = .all
    var selectedID: String?
    var focusSearch = 0

    var items: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ClipStore.shared.items.filter { item in
            switch filter {
            case .all: break
            case .pinned: if !item.pinned { return false }
            case .images: if item.kind != .image { return false }
            case .text: if item.kind != .text && item.kind != .url { return false }
            }
            guard !q.isEmpty else { return true }
            return item.snippet.lowercased().contains(q) || (item.ocrText?.lowercased().contains(q) ?? false)
                || (item.sourceAppName?.lowercased().contains(q) ?? false)
        }
    }

    func reset() {
        query = ""
        filter = .all
        selectedID = ClipStore.shared.items.first?.id
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selectedID } ?? -1
        let n = min(max(0, i + delta), list.count - 1)
        selectedID = list[n].id
    }

    private var selected: ClipItem? { items.first { $0.id == selectedID } ?? items.first }

    func copy(_ item: ClipItem) {
        ClipStore.shared.copyToPasteboard(item)
        ShelfPanelController.shared.hide()
    }
    func copySelected() { if let s = selected { copy(s) } }
    func pinSelected() { if let s = selected { ClipStore.shared.togglePin(s.id) } }
    func exportSelected() { if let s = selected { _ = ClipStore.shared.export(s) } }
    func deleteSelected() {
        guard let s = selected else { return }
        let list = items
        let i = list.firstIndex { $0.id == s.id } ?? 0
        ClipStore.shared.remove(s.id)
        let rest = items
        selectedID = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
    }
}
