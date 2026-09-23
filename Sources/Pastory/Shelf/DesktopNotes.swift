import AppKit
import SwiftUI

/// Cards pinned to the desktop as sticky notes. A note is the same paper card, in its own borderless window,
/// sitting either just above the desktop (below every app window) or above everything, per the setting.
/// Where you drop it is where it stays: positions are remembered and restored at launch.
@MainActor
final class DesktopNotes {
    static let shared = DesktopNotes()
    private var windows: [String: NoteWindow] = [:]
    private(set) var tearing: String?

    func isOnDesktop(_ id: String) -> Bool { windows[id] != nil }

    // MARK: Lifecycle

    /// Launch: bring back every note whose card still exists, where it was.
    func restore() {
        guard !ClipStore.shared.loadFailed else { return }      // an unreadable store must not erase every placement
        for entry in Preferences.shared.desktopNotes {
            guard let id = entry["id"] as? String, ClipStore.shared.items.contains(where: { $0.id == id }),
                  let x = entry["x"] as? Double, let y = entry["y"] as? Double else { continue }
            let size = (entry["w"] as? Double).flatMap { w in (entry["h"] as? Double).map { CGSize(width: w, height: $0) } }
            show(id, at: CGPoint(x: x, y: y), size: size, persist: false)
            if entry["top"] as? Bool == false { setOnTop(id, false) }
        }
        persist()
    }

    /// Put a card on the desktop. `origin` is the window's bottom-left in screen coordinates; nil = a free spot
    /// near the top-right of the main screen, stepped so notes placed one after another do not stack.
    func place(_ id: String, at origin: CGPoint? = nil) {
        guard let item = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
        if !item.pinned { ClipStore.shared.togglePin(id, welcome: false) }    // a note must not vanish with the nightly cleanup
        if let w = windows[id] { w.orderFrontRegardless(); return }
        show(id, at: origin ?? nextFreeSpot(), size: nil, persist: true)
        ShelfPanelController.shared.model.noteWelcomeTried("desktop")
    }

    func close(_ id: String) {
        windows[id]?.orderOut(nil)
        windows[id]?.close()
        windows[id] = nil
        persist()
    }

    func bringToFront(_ id: String) { windows[id]?.orderFrontRegardless() }

    /// Cards deleted from the shelf take their notes with them.
    func itemsGone(_ ids: [String]) { for id in ids where windows[id] != nil { close(id) } }

    /// Per note: floating above every window, or just above the desktop icons, below every app window.
    static func level(top: Bool) -> NSWindow.Level {
        top ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    func isOnTop(_ id: String) -> Bool { windows[id]?.onTop ?? true }
    func setOnTop(_ id: String, _ top: Bool) {
        guard let w = windows[id] else { return }
        w.onTop = top
        w.level = Self.level(top: top)
        if top { w.orderFrontRegardless() }
        persist()
    }

    // MARK: Tear-out from the shelf

    /// The card is being dragged out of the panel: a note appears under the pointer and follows it.
    func beginTear(_ id: String, at mouse: CGPoint) {
        guard windows[id] == nil else { return }
        tearing = id
        show(id, at: originFor(mouse: mouse, id: id), size: nil, persist: false)
        windows[id]?.alphaValue = 0.85
    }
    func moveTear(to mouse: CGPoint) {
        guard let id = tearing, let w = windows[id] else { return }
        w.setFrameOrigin(originFor(mouse: mouse, id: id))
    }
    /// Dropped. The pointer decides, not the note's frame: a long note hangs down over the shelf while its
    /// header is up on the desktop, and that is a valid drop. Pointer still over the shelf = changed your mind.
    func endTear(over shelf: CGRect?) {
        guard let id = tearing, let w = windows[id] else { tearing = nil; return }
        tearing = nil
        if let shelf, shelf.contains(NSEvent.mouseLocation) { w.orderOut(nil); w.close(); windows[id] = nil; return }
        w.setFrameOrigin(Self.clamp(w.frame.origin, size: w.frame.size))
        w.alphaValue = 1
        if let item = ClipStore.shared.items.first(where: { $0.id == id }), !item.pinned { ClipStore.shared.togglePin(id, welcome: false) }
        ShelfPanelController.shared.model.noteWelcomeTried("desktop")
        persist()
    }

    // MARK: Internals

    private func show(_ id: String, at origin: CGPoint, size: CGSize?, persist: Bool) {
        let w = NoteWindow(id: id, size: size)
        w.setFrameOrigin(Self.clamp(origin, size: w.frame.size))
        w.orderFrontRegardless()
        windows[id] = w
        if persist { self.persist() }
    }

    private func originFor(mouse: CGPoint, id: String) -> CGPoint {
        let size = windows[id]?.frame.size ?? CGSize(width: DesktopNoteView.width, height: 200)
        return CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height + 28)      // pointer on the header
    }

    private func nextFreeSpot() -> CGPoint {
        let vf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let n = windows.count
        return CGPoint(x: vf.maxX - DesktopNoteView.width - 40 - CGFloat(n % 6) * 24, y: vf.maxY - 320 - CGFloat(n % 6) * 24)
    }

    static func clamp(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let screen = frames.first(where: { $0.contains(CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)) }) ?? frames.first else { return origin }
        return CGPoint(x: min(max(screen.minX, origin.x), screen.maxX - size.width), y: min(max(screen.minY, origin.y), screen.maxY - size.height))
    }

    func persist() {
        guard tearing == nil else { return }      // a note still being torn out is not placed yet (the drop may cancel it)
        Preferences.shared.desktopNotes = windows.map { id, w in
            ["id": id, "x": Double(w.frame.minX), "y": Double(w.frame.minY), "w": Double(w.frame.width), "h": Double(w.frame.height), "top": w.onTop] }
    }
}

/// One sticky note. Non-activating, so a click copies without stealing focus from the app you are in.
/// Moving and resizing are handled here, at the window level, so no SwiftUI gesture inside can swallow them:
/// drag anywhere to move; drag the bottom-right corner to resize.
final class NoteWindow: NSPanel {
    let itemID: String
    let geometry = NoteGeometry()
    /// A note always arrives on top (so a tear-out is visibly there); the user can sink it to the desktop afterwards.
    var onTop = true
    private var hosting: NSHostingView<DesktopNoteView>!
    private var downAt: CGPoint?
    private var mode: Mode = .idle
    private enum Mode { case idle, deciding, moving, resizing(origin: CGPoint, size: CGSize) }
    static let minSize = CGSize(width: 220, height: 150)
    static let grip: CGFloat = 22

    init(id: String, size: CGSize?) {
        itemID = id
        super.init(contentRect: CGRect(x: 0, y: 0, width: DesktopNoteView.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                                  // the paper draws its own
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = DesktopNotes.level(top: true)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hosting = NSHostingView(rootView: DesktopNoteView(itemID: id, geometry: geometry))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor      // the margin band around the paper must be see-through
        hosting.layer?.isOpaque = false
        contentView = hosting
        if let size { apply(size: size) } else { fitToContent() }
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopNotes.shared.persist() }
        }
    }
    private var moveObserver: NSObjectProtocol?
    deinit { if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) } }

    /// First appearance: the natural size of the card for this content.
    func fitToContent() {
        let probe = NSHostingView(rootView: DesktopNoteView(itemID: itemID, geometry: NoteGeometry(), measuring: true))
        probe.sizingOptions = [.intrinsicContentSize]
        var s = probe.fittingSize
        let cap = (NSScreen.main?.visibleFrame.height ?? 900) * 0.6
        s.height = min(max(s.height, Self.minSize.height), cap)
        s.width = max(s.width, DesktopNoteView.width + DesktopNoteView.margin * 2)
        apply(size: s)
    }

    private func apply(size: CGSize) {
        let top = frame.maxY
        setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        geometry.size = CGSize(width: size.width - DesktopNoteView.margin * 2, height: size.height - DesktopNoteView.margin * 2)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            downAt = NSEvent.mouseLocation
            let p = event.locationInWindow
            let inGrip = p.x >= frame.width - DesktopNoteView.margin - Self.grip && p.y <= DesktopNoteView.margin + Self.grip
            mode = inGrip ? .resizing(origin: frame.origin, size: frame.size) : .deciding
            if inGrip { return }
        case .leftMouseDragged:
            guard let down = downAt else { break }
            let now = NSEvent.mouseLocation
            switch mode {
            case .deciding:
                if hypot(now.x - down.x, now.y - down.y) > 4 { mode = .moving; performDrag(with: event) }
                return
            case .moving: return
            case .resizing(let origin, let size):
                let dx = now.x - down.x, dy = now.y - down.y
                let w = max(Self.minSize.width, size.width + dx), h = max(Self.minSize.height, size.height - dy)
                setFrame(CGRect(x: origin.x, y: origin.y + size.height - h, width: w, height: h), display: true)
                geometry.size = CGSize(width: w - DesktopNoteView.margin * 2, height: h - DesktopNoteView.margin * 2)
                return
            case .idle: break
            }
        case .leftMouseUp:
            let was = mode
            mode = .idle; downAt = nil
            if case .resizing = was { DesktopNotes.shared.persist(); return }
            if case .moving = was { return }
        default: break
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The card's current size, driven by the window; the view lays out to it.
@Observable final class NoteGeometry {
    var size = CGSize(width: DesktopNoteView.width, height: 200)
}
