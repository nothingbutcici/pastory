import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

enum PickMode { case region, window }

/// Full-screen picker: drag a region, tap a window, F for the whole display.
/// After a pick the mask stays up and the annotator is placed over the frozen capture.
@MainActor
final class SelectionOverlayController {
    static let shared = SelectionOverlayController()
    private var overlays: [OverlayWindow] = []
    private var completion: ((CaptureTarget?) -> Void)?
    private var previousApp: NSRunningApplication?
    private(set) var isPresenting = false
    private(set) var mode: PickMode = .region
    private(set) var hoveredWindow: SCWindow?
    private(set) var annotator: AnnotateView?
    private var toolbar: AnnotateToolbar?

    private init() {}

    var ownWindowIDs: [CGWindowID] { overlays.map { CGWindowID($0.windowNumber) } }

    func present(snapshot: ShareableSnapshot, mode: PickMode, completion: @escaping (CaptureTarget?) -> Void) {
        if isPresenting || !overlays.isEmpty { release() }
        isPresenting = true
        // Esc must work even when macOS refuses to give us keyboard focus.
        HotKeyCenter.shared.bindRaw(keyCode: 53, modifiers: 0, name: "picker.esc") {
            MainActor.assumeIsolated { CaptureCoordinator.shared.cancel() }
        }
        self.completion = completion
        self.mode = mode
        hoveredWindow = nil
        previousApp = NSWorkspace.shared.frontmostApplication

        let pickable = snapshot.pickableWindows
        for screen in NSScreen.screens {
            guard let display = snapshot.display(for: screen) else { continue }
            let w = OverlayWindow(screen: screen, display: display)
            w.overlayView.controller = self
            w.overlayView.candidates = pickable.map { ($0, CoordinateSpace.cocoaRect(fromCG: $0.frame)) }
            overlays.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        overlays.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let key = overlays.first { $0.screenRef.frame.contains(mouse) } ?? overlays.first
        key?.makeKeyAndOrderFront(nil)
        key?.makeFirstResponder(key?.overlayView)
        if mode == .window { updateHover(at: mouse) }
        refreshAll()
    }

    func toggleMode() {
        mode = mode == .region ? .window : .region
        hoveredWindow = nil
        if mode == .window { updateHover(at: NSEvent.mouseLocation) }
        refreshAll()
    }

    func updateHover(at p: CGPoint) {
        guard mode == .window, let overlay = overlays.first else { return }
        let hit = overlay.overlayView.candidates.first { $0.1.contains(p) }?.0
        if hit?.windowID != hoveredWindow?.windowID {
            hoveredWindow = hit
            refreshAll()
        }
    }

    func refreshAll() { overlays.forEach { $0.overlayView.needsDisplay = true } }

    /// A target was picked on `window`; `viewRect` is where it sits in that overlay (nil = whole screen).
    func finish(_ target: CaptureTarget?, viewRect: CGRect?, on window: OverlayWindow?) {
        guard isPresenting else { return }
        isPresenting = false
        let done = completion
        completion = nil
        guard let target else { release(); done?(nil); return }
        for o in overlays {
            o.overlayView.held = true
            o.overlayView.heldRect = o === window ? (viewRect ?? o.overlayView.bounds) : nil
            o.overlayView.needsDisplay = true
        }
        done?(target)
    }

    /// Place the annotation canvas over the frozen selection.
    func showAnnotator(image: CGImage, delegate: AnnotateDelegate) {
        guard let win = overlays.first(where: { $0.overlayView.heldRect != nil }),
              let rect = win.overlayView.heldRect else { return }
        // Now that the picture is taken, keep the mouse from seeing the other screens' masks as pickable.
        for o in overlays where o !== win { o.ignoresMouseEvents = true }
        let canvas = AnnotateView(frame: rect, image: image)
        canvas.delegate = delegate
        win.overlayView.addSubview(canvas)
        let bar = AnnotateToolbar(canvas: canvas)
        bar.frame = Self.toolbarFrame(for: rect, size: bar.fittingSize, in: win.overlayView.bounds)
        win.overlayView.addSubview(bar)
        bar.didLayout()
        annotator = canvas
        toolbar = bar
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(canvas)
    }

    private static func toolbarFrame(for rect: CGRect, size: CGSize, in bounds: CGRect) -> CGRect {
        let gap: CGFloat = 8
        var y = rect.minY - size.height - gap
        if y < bounds.minY + 4 {
            y = rect.maxY + gap
            if y + size.height > bounds.maxY - 4 { y = rect.minY + gap }
        }
        var x = rect.maxX - size.width
        x = min(max(bounds.minX + 4, x), bounds.maxX - size.width - 4)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Screen-space rect of the held selection, for placing side panels.
    var heldScreenRect: CGRect? {
        guard let win = overlays.first(where: { $0.overlayView.heldRect != nil }),
              let r = win.overlayView.heldRect else { return nil }
        return win.convertToScreen(r)
    }

    /// Tear everything down.
    func release() {
        isPresenting = false
        completion = nil
        HotKeyCenter.shared.unbind("picker.esc")
        annotator?.removeFromSuperview()
        toolbar?.subBar.removeFromSuperview()
        toolbar?.removeFromSuperview()
        annotator = nil
        toolbar = nil
        overlays.forEach { $0.orderOut(nil); $0.close() }
        overlays.removeAll()
        previousApp?.activate()
        previousApp = nil
    }
}

final class OverlayWindow: NSWindow {
    let screenRef: NSScreen
    let display: SCDisplay
    let overlayView: OverlayView

    init(screen: NSScreen, display: SCDisplay) {
        screenRef = screen
        self.display = display
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        overlayView.screenRef = screen
        overlayView.display = display
        // NSWindow defaults to releasing itself on close(); ARC releases it again → double free.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = overlayView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayView: NSView {
    weak var controller: SelectionOverlayController?
    var screenRef: NSScreen!
    var display: SCDisplay!
    var candidates: [(SCWindow, CGRect)] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    /// After a pick: freeze the drawing, no hints, no crosshair.
    var held = false
    var heldRect: CGRect?
    private let accent = NSColor(calibratedRed: 0.56, green: 0.42, blue: 1.0, alpha: 1.0)

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { if !held { addCursorRect(bounds, cursor: .crosshair) } }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    private var selectionRect: CGRect? {
        guard let a = dragStart, let b = dragCurrent else { return nil }
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        return r.width < 2 || r.height < 2 ? nil : r
    }

    private var hoveredRectInView: CGRect? {
        guard let h = controller?.hoveredWindow,
              let g = candidates.first(where: { $0.0.windowID == h.windowID })?.1 else { return nil }
        return windowRectInView(g)
    }

    func windowRectInView(_ global: CGRect) -> CGRect? {
        let local = CGRect(x: global.origin.x - screenRef.frame.origin.x, y: global.origin.y - screenRef.frame.origin.y,
                           width: global.width, height: global.height)
        let clipped = local.intersection(bounds)
        return clipped.isEmpty ? nil : clipped
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        NSColor(calibratedWhite: 0, alpha: 0.45).setFill()
        bounds.fill()
        let hole: CGRect? = held ? heldRect : (controller?.mode == .window ? hoveredRectInView : selectionRect)
        if let hole {
            ctx.compositingOperation = .copy
            NSColor.clear.setFill()
            hole.fill()
            ctx.compositingOperation = .sourceOver
            accent.setStroke()
            let path = NSBezierPath(rect: hole.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1.5
            path.stroke()
            if !held { drawBadge(for: hole) }
        }
    }

    private func drawBadge(for rect: CGRect) {
        let text: String
        if controller?.mode == .window, let w = controller?.hoveredWindow {
            let app = w.owningApplication?.applicationName ?? ""
            let title = w.title ?? ""
            text = title.isEmpty ? app : "\(app) — \(title)"
        } else {
            let s = screenRef.backingScaleFactor
            text = "\(Int(rect.width * s)) × \(Int(rect.height * s)) px"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 8
        var box = CGRect(x: rect.minX, y: rect.maxY + 8, width: size.width + pad * 2, height: size.height + pad)
        if box.maxY > bounds.maxY - 4 { box.origin.y = rect.minY - box.height - 8 }
        if box.maxX > bounds.maxX - 4 { box.origin.x = bounds.maxX - box.width - 4 }
        box.origin.x = max(4, box.origin.x); box.origin.y = max(4, box.origin.y)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2), withAttributes: attrs)
    }

    private var overlayWindow: OverlayWindow? { window as? OverlayWindow }

    override func mouseDown(with event: NSEvent) {
        guard !held else { return }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        guard controller?.mode == .region else {
            controller?.updateHover(at: NSEvent.mouseLocation)
            return
        }
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !held, controller?.mode == .region, dragStart != nil else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(0, p.x), bounds.width); p.y = min(max(0, p.y), bounds.height)
        dragCurrent = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !held else { return }
        if controller?.mode == .window {
            controller?.updateHover(at: NSEvent.mouseLocation)
            if let w = controller?.hoveredWindow {
                let r = windowRectInView(CoordinateSpace.cocoaRect(fromCG: w.frame))
                controller?.finish(.window(w), viewRect: r, on: overlayWindow)
            } else {
                controller?.finish(nil, viewRect: nil, on: nil)
            }
            return
        }
        defer { dragStart = nil; dragCurrent = nil }
        guard let rect = selectionRect, rect.width >= 8, rect.height >= 8 else {
            controller?.finish(nil, viewRect: nil, on: nil)      // a plain click is the escape hatch
            return
        }
        let snapped = rect.integral
        controller?.finish(.region(display, CoordinateSpace.displayLocalRect(viewRect: snapped, screen: screenRef)),
                           viewRect: snapped, on: overlayWindow)
    }

    override func rightMouseUp(with event: NSEvent) { if !held { controller?.finish(nil, viewRect: nil, on: nil) } }

    override func mouseMoved(with event: NSEvent) {
        guard !held else { return }
        if controller?.mode == .window { controller?.updateHover(at: NSEvent.mouseLocation) }
    }

    override func keyDown(with event: NSEvent) {
        guard !held else { super.keyDown(with: event); return }
        switch Int(event.keyCode) {
        case kVK_Escape: controller?.finish(nil, viewRect: nil, on: nil)
        case kVK_Space: controller?.toggleMode()
        case kVK_ANSI_F, kVK_Return, kVK_ANSI_KeypadEnter:
            controller?.finish(.display(display), viewRect: bounds, on: overlayWindow)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { if !held { controller?.finish(nil, viewRect: nil, on: nil) } }
}
