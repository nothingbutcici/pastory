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
    /// The app that was in front when the shelf opened; a single-click copy hands the keyboard back to it so ⌘V lands there.
    private var previousApp: NSRunningApplication?
    private var keepOpenOnResign = false
    private var outsideClickMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func refocus() { if let p = panel, p.isVisible { p.makeKey() } }

    /// Run a system dialog (open / save / alert) from the shelf: the shelf normally floats above everything,
    /// which would bury the dialog and leave the user stuck. Lower it for the duration, keep it open, then restore.
    func withDialog<T>(_ body: () -> T) -> T {
        holdOpen = true
        let level = panel?.level ?? .statusBar
        panel?.level = .normal
        panel?.orderBack(nil)
        // Modern activation first; the legacy call stays as the fallback for macOS 14's cooperative rules.
        NSApp.activate()
        NSApp.activate(ignoringOtherApps: true)
        defer {
            panel?.level = level
            holdOpen = false
            refocus()
        }
        return body()
    }

    func toggle() { isVisible ? hide() : show() }
    /// After onboarding: drop the extra height the welcome card needed.
    func relayoutHeight() { if isVisible { hide(); show() } }

    /// Open (if needed) with the search box focused.
    func showSearch() {
        if !isVisible { show() }
        model.showSettings = false
        model.focusSearch += 1
    }

    /// Build the panel and its SwiftUI tree at launch, so the first ⇧⌘V does not pay for it.
    func prewarm() {
        watchAppSwitches()
        let p = panel ?? makePanel()
        panel = p
        p.setFrame(CGRect(x: 0, y: 0, width: 1200, height: 480), display: false)
        p.contentView?.layoutSubtreeIfNeeded()
        model.prewarmSearch()
    }

    func show() {
        let p = panel ?? makePanel()
        panel = p
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        keepOpenOnResign = false
        // Decode the first row of thumbnails while the shelf slides in.
        ClipStore.shared.items.prefix(10).filter { $0.kind == .image || $0.kind == .video }.forEach { ClipStore.shared.warmThumbnail($0) }
        // A click anywhere else closes the shelf even when it no longer holds the keyboard (after a copy).
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let p = self.panel, p.isVisible, !self.holdOpen else { return }
                    if !p.frame.contains(NSEvent.mouseLocation) { self.hide() }
                }
            }
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        var height = max(384, (screen.frame.height * 0.48).rounded() - 36)      // 48% minus about a centimetre; cards follow the panel
        if model.showWelcome { height = max(height, 540) }                        // the welcome card needs the room; first launch only
        let target = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        model.reset()
        // The window itself never leaves this screen (a display arranged below would otherwise see it slide through);
        // the slide happens to the content inside the window, together with a fade.
        p.setFrame(target, display: false)
        p.alphaValue = 0
        p.contentView?.frame = CGRect(x: 0, y: -Self.slide, width: target.width, height: target.height)
        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(nil)          // keyboard goes to the shelf itself, not into the search box
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.contentView?.animator().frame = CGRect(origin: .zero, size: target.size)
        }
    }
    private static let slide: CGFloat = 28

    func hide() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        keepOpenOnResign = false
        guard let p = panel, p.isVisible else { return }
        let size = p.frame.size
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
            p.contentView?.animator().frame = CGRect(x: 0, y: -Self.slide, width: size.width, height: size.height)
        }, completionHandler: {
            MainActor.assumeIsolated {
                p.orderOut(nil)
                p.contentView?.frame = CGRect(origin: .zero, size: size)
                p.alphaValue = 1
            }
        })
    }

    private func makePanel() -> NSPanel {
        let p = ShelfPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 400),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false      // the system shadow spilled onto a display arranged below the shelf
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.delegate = self
        p.contentView = NSHostingView(rootView: ShelfView(model: model))
        return p
    }

    func windowDidResignKey(_ notification: Notification) {
        if keepOpenOnResign { keepOpenOnResign = false; return }
        if !holdOpen { hide() }
    }

    /// Double-click / ⏎: once the shelf is gone and the previous app has the keyboard again, press ⌘V for the user.
    /// Needs Accessibility; without it (or with the setting off) this is a plain copy-and-close.
    func pasteIntoPreviousApp() {
        guard Preferences.shared.pasteOnDoubleClick, let app = previousApp, !app.isTerminated else { return }
        guard Permissions.hasAccessibility else { Permissions.requestAccessibility(); return }
        app.activate()
        // The hide animation takes 0.18 s; give activation a moment, then confirm the target is actually in front.
        var tries = 0
        func attempt() {
            tries += 1
            if NSWorkspace.shared.frontmostApplication == app { Permissions.sendPaste(); return }
            if tries < 8 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { attempt() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { attempt() }
    }

    /// After copying with a single click: the shelf stays, the keyboard goes back to the app you were in.
    func handBackFocus() {
        guard let p = panel, p.isVisible, let app = previousApp, !app.isTerminated else { return }
        keepOpenOnResign = p.isKeyWindow          // only a real resign should be swallowed
        app.activate()
    }

    /// While the shelf floats without the keyboard (after a copy), switching to yet another app closes it,
    /// the same way a click outside does.
    private func watchAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel, p.isVisible, !p.isKeyWindow, !self.holdOpen,
                      let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app != .current, app != self.previousApp else { return }
                self.hide()
            }
        }
    }

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
        let composing = (fr as? NSTextView)?.hasMarkedText() ?? false      // IME candidate window open: keys belong to it
        let cmd = event.modifierFlags.contains(.command)
        let code = Int(event.keyCode)
        // Settings page: there are no cards to act on; only ⎋ (back) and ⌘F (to the shelf's search) mean anything.
        if model.showSettings {
            if code == kVK_Escape { model.showSettings = false; return true }
            if code == kVK_ANSI_F, cmd { model.showSettings = false; model.focusSearch += 1; return true }
            return false
        }
        switch code {
        case kVK_Escape:
            if typing, !model.query.isEmpty { model.query = ""; return true }
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if composing { return false }
            model.copySelected(); return true          // also from the search box: ⏎ takes the highlighted result
        case kVK_LeftArrow where !typing: model.move(-1); return true
        case kVK_RightArrow where !typing: model.move(1); return true
        case kVK_UpArrow where !composing: model.move(-1); return true      // from the search box too
        case kVK_DownArrow where !composing: model.move(1); return true
        case kVK_ANSI_P where cmd: model.pinSelected(); return true          // ⌘P: letters alone start a search
        case kVK_ANSI_S where cmd: model.exportSelected(); return true
        case kVK_Delete where !typing: model.deleteSelected(); return true
        case kVK_ANSI_F where cmd: model.focusSearch += 1; return true
        case kVK_Space where !typing: toggleQuickLook(); return true
        default:
            // Just start typing: letters go straight into the search box. Function / navigation keys arrive as
            // private-use scalars (U+F700…) and must not.
            if !typing, !cmd, !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
               let chars = event.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse }) {
                model.pendingQuery = chars
                model.focusSearch += 1
                return true
            }
            return false
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
    private let store: ClipStore
    @ObservationIgnored private let searchIndex = ClipSearchIndex()
    @ObservationIgnored private var initialWarmup: Task<Void, Never>?

    init(store: ClipStore? = nil) { self.store = store ?? .shared }

    var query = "" { didSet { if query != oldValue { pickedByHand = false } } }
    /// True once the highlight was moved with the arrow keys or a click. The first search hit is highlighted
    /// automatically; Return on that only copies, it never types into another app.
    @ObservationIgnored private(set) var pickedByHand = false
    var showSettings = false
    /// First launch until 「开始使用」 is pressed; the welcome card leads the row.
    var showWelcome = !Preferences.shared.didWelcome
    var welcomeTried: Set<String> = Preferences.shared.welcomeTried
    func noteWelcomeTried(_ what: String) {
        guard showWelcome, !welcomeTried.contains(what) else { return }
        welcomeTried.insert(what)
        Preferences.shared.welcomeTried = welcomeTried
    }
    func finishWelcome() {
        Preferences.shared.didWelcome = true
        showWelcome = false
        ShelfPanelController.shared.relayoutHeight()
    }
    /// Bumped when a setting that the sidebar shows (retention) changes.
    var prefsTick = 0
    /// Card whose title is being edited inline.
    var renamingID: String?
    var filter: ShelfFilter = .all { didSet { selectAvailableItem() } }
    var selectedID: String? {
        didSet {
            if QLPreviewPanel.sharedPreviewPanelExists() { ShelfPanelController.shared.quickLookSelectionChanged() }
            if let r = renamingID, r != selectedID { renamingID = nil }     // moving on cancels an open title box
        }
    }
    var focusSearch = 0
    /// Characters typed while nothing was focused; the search field takes them once it has focus (so they are not selected-and-replaced).
    var pendingQuery = ""
    /// Bumped when the language changes; the shelf view is keyed on it.
    var langTick = 0
    /// Bumped on every show(); the view uses it to drop keyboard focus so the caret does not sit in the search box.
    var openTick = 0
    /// Card order is frozen while the shelf is open, so copying (which bumps the item in the store)
    /// does not make cards jump around. Rebuilt on every show.
    @ObservationIgnored private var orderSnapshot: [String: Int] = [:]
    @ObservationIgnored private var countCache: (version: Int, counts: [ShelfFilter: Int])?

    /// Totals per filter (ignoring the search box), for the pills — one pass over the store, not five.
    var counts: [ShelfFilter: Int] {
        let version = store.version
        if let cache = countCache, cache.version == version { return cache.counts }
        var c: [ShelfFilter: Int] = [.all: 0, .pinned: 0, .images: 0, .videos: 0, .text: 0]
        for it in store.items {
            c[.all, default: 0] += 1
            if it.pinned { c[.pinned, default: 0] += 1 }
            switch it.kind {
            case .image: c[.images, default: 0] += 1
            case .video: c[.videos, default: 0] += 1
            case .text, .url: c[.text, default: 0] += 1
            case .files: break
            }
        }
        countCache = (version, c)
        return c
    }

    /// Store items in frozen shelf order, re-sorted only when the store or the snapshot changed.
    @ObservationIgnored private var orderedCache: (version: Int, snapshotID: Int, items: [ClipItem]) = (-1, -1, [])
    private var snapshotID = 0
    private func orderedItems() -> [ClipItem] {
        let v = store.version
        if orderedCache.version == v, orderedCache.snapshotID == snapshotID { return orderedCache.items }
        let sorted = store.items.sorted { (orderSnapshot[$0.id] ?? Int.max) < (orderSnapshot[$1.id] ?? Int.max) }   // items array is already date-sorted
        orderedCache = (v, snapshotID, sorted)
        return sorted
    }

    struct SearchRequest: Hashable {
        let query: String
        let version: Int
    }
    var searchRequest: SearchRequest { SearchRequest(query: ClipSearchIndex.normalizedQuery(query), version: store.version) }
    private var searchResult: (request: SearchRequest, ids: Set<String>)?
    var isSearching: Bool { !searchRequest.query.isEmpty && searchResult?.request != searchRequest }

    private struct ListKey: Equatable {
        let request: SearchRequest
        let snapshot: Int
        let filter: ShelfFilter
    }
    @ObservationIgnored private var listCache: (key: ListKey, items: [ClipItem])?

    /// Start at app launch even if the shelf has not appeared yet. The first view-owned search cancels
    /// this task and takes over, retaining any entries that have already been warmed.
    func prewarmSearch() {
        initialWarmup?.cancel()
        let index = searchIndex, items = store.items, directory = store.root.appendingPathComponent("items")
        initialWarmup = Task(priority: .utility) { _ = try? await index.search("", items: items, directory: directory) }
    }

    /// SwiftUI owns this task and cancels it when the query or store changes. An empty query prewarms
    /// the full text in the background; nonempty queries wait briefly for a burst of typing to settle.
    func updateSearch() async {
        initialWarmup?.cancel()
        initialWarmup = nil
        let request = searchRequest
        if searchResult?.request == request { return }
        do {
            if !request.query.isEmpty { try await Task.sleep(nanoseconds: 80_000_000) }
            try Task.checkCancellation()
            let ids = try await searchIndex.search(request.query, items: store.items, directory: store.root.appendingPathComponent("items"))
            try Task.checkCancellation()
            guard searchRequest == request else { return }
            searchResult = (request, ids)
            selectAvailableItem()
        } catch is CancellationError {
            // A newer query owns the result; never publish the obsolete one.
        } catch {
            assertionFailure("Unexpected search error: \(error)")
        }
    }

    private func selectAvailableItem() {
        let list = items
        if !list.contains(where: { $0.id == selectedID }) { selectedID = list.first?.id }
    }

    var items: [ClipItem] {
        let request = searchRequest
        // Hide stale results immediately, including from keyboard actions such as Return-to-paste.
        let matches = searchResult
        if !request.query.isEmpty, matches?.request != request { return [] }
        let key = ListKey(request: request, snapshot: snapshotID, filter: filter)
        if let cached = listCache, cached.key == key { return cached.items }
        let ordered = orderedItems()
        let filtered = ordered.filter { item in
            switch filter {
            case .all: break
            case .pinned: if !item.pinned { return false }
            case .images: if item.kind != .image { return false }
            case .videos: if item.kind != .video { return false }
            case .text: if item.kind != .text && item.kind != .url { return false }
            }
            return request.query.isEmpty || matches?.ids.contains(item.id) == true
        }
        listCache = (key, filtered)
        return filtered
    }

    /// After bulk changes (import, remove-imported) the frozen order is stale: freeze the store's current order again.
    func refreshOrder() {
        orderSnapshot = Dictionary(uniqueKeysWithValues: store.items.enumerated().map { ($1.id, $0) })
        snapshotID += 1
        orderedCache = (store.version, snapshotID, store.items)
    }

    func reset() {
        query = ""
        showSettings = false
        renamingID = nil
        openTick += 1
        refreshOrder()
        filter = .all
        selectedID = store.items.first?.id
        pickedByHand = false
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selectedID } ?? -1
        let n = min(max(0, i + delta), list.count - 1)
        selectedID = list[n].id
        pickedByHand = true
    }

    /// The highlighted card, and only that; keys never fall back to the first card silently.
    private var selected: ClipItem? { items.first { $0.id == selectedID } }
    var selectedItem: ClipItem? { selected }

    /// Single click: copy and stay (the 已复制 tag moves to the card).
    func copy(_ item: ClipItem) {
        store.copyToPasteboard(item)
        selectedID = item.id
        pickedByHand = true
        // The copy and the highlight are immediate. Only the hand-back of the keyboard waits out a possible second
        // click, so a double-click still finds the shelf exactly as it was.
        pendingHandBack?.cancel()
        let work = DispatchWorkItem { ShelfPanelController.shared.handBackFocus() }
        pendingHandBack = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }
    /// ⏎ / double-click: copy, close, and (with Accessibility) paste into the app you came from.
    @ObservationIgnored private var pendingHandBack: DispatchWorkItem?
    func copyAndClose(_ item: ClipItem, paste: Bool = true) {
        copy(item)
        pendingHandBack?.cancel()
        ShelfPanelController.shared.hide()
        if paste { ShelfPanelController.shared.pasteIntoPreviousApp() }
    }
    /// Return: copy and close; paste too only when the setting allows it and the card was picked by hand.
    func copySelected() {
        guard let s = selected else { return }
        copyAndClose(s, paste: Preferences.shared.pasteOnReturn && pickedByHand)
    }
    func previewSelected() { ShelfPanelController.shared.toggleQuickLook() }

    /// Text → our editor window; image → the annotation editor. Saving rewrites the item and copies it.
    func edit(_ item: ClipItem) {
        switch item.kind {
        case .text, .url: TextEditorWindow.open(item)
        case .image: ImageEditorWindow.open(item)
        default: previewSelected()
        }
    }
    func pinSelected() { if let s = selected { store.togglePin(s.id) } }
    func exportSelected() { if let s = selected { Exporter.export(s) } }
    func deleteSelected() {
        // Only a card that is actually highlighted in the current list; never a silent fallback.
        guard let id = selectedID, let s = items.first(where: { $0.id == id }) else { return }
        let list = items
        let i = list.firstIndex { $0.id == s.id } ?? 0
        guard delete(s) else { return }
        let rest = items
        selectedID = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
    }

    /// The one way to delete from the shelf: a pinned card asks first, everything else goes straight away.
    @discardableResult
    func delete(_ item: ClipItem) -> Bool {
        if item.pinned {
            let go = ShelfPanelController.shared.withDialog { () -> Bool in
                let a = NSAlert()
                a.messageText = "这条是 Pin 住的，确定删除？".l
                a.informativeText = "Pin 住的内容不会被自动清理，只有这样手动删除才会消失，而且不能恢复。".l
                a.addButton(withTitle: "删除".l)
                a.addButton(withTitle: "取消".l)
                return a.runModal() == .alertFirstButtonReturn
            }
            guard go else { return false }
        }
        store.remove(item.id)
        return true
    }
}
