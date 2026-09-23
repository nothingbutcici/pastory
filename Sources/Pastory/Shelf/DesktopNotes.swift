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
        for entry in Preferences.shared.desktopNotes {
            guard let id = entry["id"] as? String, ClipStore.shared.items.contains(where: { $0.id == id }),
                  let x = entry["x"] as? Double, let y = entry["y"] as? Double else { continue }
            show(id, at: CGPoint(x: x, y: y), persist: false)
        }
        persist()
    }

    /// Put a card on the desktop. `origin` is the window's bottom-left in screen coordinates; nil = a free spot
    /// near the top-right of the main screen, stepped so notes placed one after another do not stack.
    func place(_ id: String, at origin: CGPoint? = nil) {
        guard let item = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
        if !item.pinned { ClipStore.shared.togglePin(id) }        // a note must not vanish with the nightly cleanup
        if let w = windows[id] { w.orderFrontRegardless(); return }
        show(id, at: origin ?? nextFreeSpot(), persist: true)
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

    /// The layer setting changed.
    func applyLayer() { windows.values.forEach { $0.level = Self.level } }

    static var level: NSWindow.Level {
        Preferences.shared.desktopNoteLayer == "top" ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)     // above the icons, below every app window
    }

    // MARK: Tear-out from the shelf

    /// The card is being dragged out of the panel: a note appears under the pointer and follows it.
    func beginTear(_ id: String, at mouse: CGPoint) {
        guard windows[id] == nil else { return }
        tearing = id
        show(id, at: originFor(mouse: mouse, id: id), persist: false)
        windows[id]?.alphaValue = 0.85
    }
    func moveTear(to mouse: CGPoint) {
        guard let id = tearing, let w = windows[id] else { return }
        w.setFrameOrigin(originFor(mouse: mouse, id: id))
    }
    /// Dropped. Over the shelf = changed your mind; anywhere else = it stays, and the card is pinned.
    func endTear(over shelf: CGRect?) {
        guard let id = tearing, let w = windows[id] else { tearing = nil; return }
        tearing = nil
        if let shelf, shelf.intersects(w.frame) { w.orderOut(nil); w.close(); windows[id] = nil; return }
        w.alphaValue = 1
        if let item = ClipStore.shared.items.first(where: { $0.id == id }), !item.pinned { ClipStore.shared.togglePin(id) }
        persist()
    }

    // MARK: Internals

    private func show(_ id: String, at origin: CGPoint, persist: Bool) {
        let w = NoteWindow(id: id)
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
        Preferences.shared.desktopNotes = windows.map { id, w in ["id": id, "x": Double(w.frame.minX), "y": Double(w.frame.minY)] }
    }
}

/// One sticky note. Non-activating, so a click copies without stealing focus from the app you are in.
final class NoteWindow: NSPanel {
    let itemID: String
    private var hosting: NSHostingView<DesktopNoteView>!

    init(id: String) {
        itemID = id
        super.init(contentRect: CGRect(x: 0, y: 0, width: DesktopNoteView.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                                  // the paper draws its own
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = DesktopNotes.level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hosting = NSHostingView(rootView: DesktopNoteView(itemID: id, refit: { [weak self] in self?.refit() }))
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting
        refit()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopNotes.shared.persist() }
        }
    }

    /// Size the window to the card; keep the top edge where it is so a note grows downward.
    func refit() {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let top = frame.maxY
        setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
