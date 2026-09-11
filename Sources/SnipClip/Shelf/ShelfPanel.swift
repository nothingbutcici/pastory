import AppKit
import Carbon.HIToolbox
import Quartz
import SwiftUI

/// Bottom drawer, Paste-style. Non-activating: the app you were in keeps focus,
/// so what you copy here you can paste right away.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    static let shared = ShelfPanelController()
    private var panel: NSPanel?
    let model = ShelfModel()
    /// True while a save dialog is up, so losing key status does not slide the shelf away.
    var holdOpen = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func refocus() { if let p = panel, p.isVisible { p.makeKey() } }

    func toggle() { isVisible ? hide() : show() }

    /// Open (if needed) with the search box focused.
    func showSearch() {
        if !isVisible { show() }
        model.showSettings = false
        model.focusSearch += 1
    }

    func show() {
        let p = panel ?? makePanel()
        panel = p
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let height = max(420, (screen.frame.height * 0.55).rounded())
        let target = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        let start = target.offsetBy(dx: 0, dy: -height)
        Retention.sweep()           // what you see is always post-cleanup
        Retention.reschedule()
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

    func windowDidResignKey(_ notification: Notification) { if !holdOpen { hide() } }

    // MARK: Keys (only while visible)

    fileprivate func handle(_ event: NSEvent) -> Bool {
        // A title box is open: everything goes to it, ⎋ closes it.
        if model.renamingID != nil {
            if Int(event.keyCode) == kVK_Escape { model.renamingID = nil; return true }
            return false
        }
        // "Typing" = any text input owns the keyboard (field editor, SwiftUI text view, NSTextField).
        let fr = panel?.firstResponder
        let typing = fr is NSText || fr is NSTextField || String(describing: type(of: fr as Any)).contains("Text")
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            if typing, !model.query.isEmpty { model.query = ""; return true }
            if model.showSettings { model.showSettings = false; return true }
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if typing { return false }                 // ⏎ inside a text box stays in the text box
            model.copySelected(); return true
        case kVK_LeftArrow where !typing: model.move(-1); return true
        case kVK_RightArrow where !typing: model.move(1); return true
        case kVK_ANSI_P where !typing || cmd: model.pinSelected(); return true
        case kVK_ANSI_S where !typing || cmd: model.exportSelected(); return true
        case kVK_Delete where !typing: model.deleteSelected(); return true
        case kVK_ANSI_F where cmd: model.focusSearch += 1; return true
        case kVK_Space where !typing: toggleQuickLook(); return true
        default: return false
        }
    }

    // MARK: Quick Look (space)

    /// File to preview for the selected card: the payload itself, or the first file of a files item.
    var quickLookURL: URL? {
        guard let item = model.selectedItem else { return nil }
        if item.kind == .files { return ClipStore.shared.fileURLs(of: item).first }
        return ClipStore.shared.payloadURL(item)
    }

    func toggleQuickLook() {
        guard let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible { ql.orderOut(nil); return }
        guard quickLookURL != nil else { return }
        holdOpen = true
        ql.makeKeyAndOrderFront(nil)
    }

    func quickLookSelectionChanged() {
        if let ql = QLPreviewPanel.shared(), ql.isVisible { ql.reloadData() }
    }
}

final class ShelfPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look asks the key window's responder chain who wants the panel.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        let c = ShelfPanelController.shared
        c.holdOpen = false
        c.refocus()
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { ShelfPanelController.shared.quickLookURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        ShelfPanelController.shared.quickLookURL as NSURL?
    }
    /// Arrow keys keep working while the preview is up.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        return ShelfPanelController.shared.handle(event)
    }
    /// Shortcuts are handled before the responder chain so the search field cannot swallow ⏎ / ⎋.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, ShelfPanelController.shared.handle(event) { return }
        super.sendEvent(event)
    }
}

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "全部", pinned = "Pin", images = "图片", videos = "录屏", text = "文本"
    var id: String { rawValue }
}

@MainActor
@Observable
final class ShelfModel {
    var query = ""
    var showSettings = false
    /// Card whose title is being edited inline.
    var renamingID: String?
    var filter: ShelfFilter = .all
    var selectedID: String? {
        didSet {
            ShelfPanelController.shared.quickLookSelectionChanged()
            if let r = renamingID, r != selectedID { renamingID = nil }     // moving on cancels an open title box
        }
    }
    var focusSearch = 0
    /// Card order is frozen while the shelf is open, so copying (which bumps the item in the store)
    /// does not make cards jump around. Rebuilt on every show.
    private var orderSnapshot: [String: Int] = [:]

    /// Totals per filter (ignoring the search box), for the pills.
    func count(for f: ShelfFilter) -> Int {
        let all = ClipStore.shared.items
        switch f {
        case .all: return all.count
        case .pinned: return all.filter(\.pinned).count
        case .images: return all.filter { $0.kind == .image }.count
        case .videos: return all.filter { $0.kind == .video }.count
        case .text: return all.filter { $0.kind == .text || $0.kind == .url }.count
        }
    }

    var items: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let ordered = ClipStore.shared.items.sorted { (orderSnapshot[$0.id] ?? -1) < (orderSnapshot[$1.id] ?? -1) }
        return ordered.filter { item in
            switch filter {
            case .all: break
            case .pinned: if !item.pinned { return false }
            case .images: if item.kind != .image { return false }
            case .videos: if item.kind != .video { return false }
            case .text: if item.kind != .text && item.kind != .url { return false }
            }
            guard !q.isEmpty else { return true }
            return item.snippet.lowercased().contains(q) || (item.ocrText?.lowercased().contains(q) ?? false)
                || (item.sourceAppName?.lowercased().contains(q) ?? false) || (item.title?.lowercased().contains(q) ?? false)
        }
    }

    func reset() {
        query = ""
        showSettings = false
        renamingID = nil
        filter = .all
        orderSnapshot = Dictionary(uniqueKeysWithValues: ClipStore.shared.items.enumerated().map { ($1.id, $0) })
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
    var selectedItem: ClipItem? { selected }

    /// Single click: copy and stay (the 已复制 tag moves to the card).
    func copy(_ item: ClipItem) {
        ClipStore.shared.copyToPasteboard(item)
        selectedID = item.id
    }
    /// ⏎ / double-click: copy and put the shelf away.
    func copyAndClose(_ item: ClipItem) {
        copy(item)
        ShelfPanelController.shared.hide()
    }
    func copySelected() { if let s = selected { copyAndClose(s) } }
    func previewSelected() { ShelfPanelController.shared.toggleQuickLook() }

    /// Text → our editor window; image → the annotation editor. Saving rewrites the item and copies it.
    func edit(_ item: ClipItem) {
        switch item.kind {
        case .text, .url: TextEditorWindow.open(item)
        case .image: ImageEditorWindow.open(item)
        default: previewSelected()
        }
    }
    func pinSelected() { if let s = selected { ClipStore.shared.togglePin(s.id) } }
    func exportSelected() { if let s = selected { Exporter.export(s) } }
    func deleteSelected() {
        // Only a card that is actually highlighted in the current list; never a silent fallback.
        guard let id = selectedID, let s = items.first(where: { $0.id == id }) else { return }
        let list = items
        let i = list.firstIndex { $0.id == s.id } ?? 0
        ClipStore.shared.remove(s.id)
        let rest = items
        selectedID = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
    }
}
