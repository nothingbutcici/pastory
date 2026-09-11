import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

enum PickMode { case region, window }

/// Full-screen picker: drag a region, tap a window, F for the whole display.
/// After a pick the mask stays up, the frame grows lime handles (drag to resize; the canvas re-crops),
/// and the brand bar + annotator appear.
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
    private var topBar: TopBar?
    /// Display-local rect (points, origin top-left) → cropped capture. Set by the coordinator.
    var cropProvider: ((CGRect) -> CGImage?)?

    private init() {}

    private var heldWindow: OverlayWindow? { overlays.first { $0.overlayView.heldRect != nil } }
    /// The mask windows, so captures can leave out exactly these and nothing else.
    var ownWindowIDs: [CGWindowID] { overlays.map { CGWindowID($0.windowNumber) } }
    var heldDisplay: SCDisplay? { heldWindow?.display }
    var heldScreenSize: CGSize? { heldWindow?.screenRef.frame.size }
    var heldDisplayLocalRect: CGRect? {
        guard let w = heldWindow, let r = w.overlayView.heldRect else { return nil }
        return CoordinateSpace.displayLocalRect(viewRect: r, screen: w.screenRef)
    }
    /// Screen-space rect of the held selection, for placing side panels.
    var heldScreenRect: CGRect? {
        guard let w = heldWindow, let r = w.overlayView.heldRect else { return nil }
        return w.convertToScreen(r)
    }

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
            o.invalidateCursorRects(for: o.overlayView)
        }
        done?(target)
    }

    /// Place the brand bar and the annotation canvas over the frozen selection.
    func showAnnotator(image: CGImage, delegate: AnnotateDelegate) {
        guard let win = heldWindow, let rect = win.overlayView.heldRect else { return }
        for o in overlays where o !== win { o.ignoresMouseEvents = true }
        let canvas = AnnotateView(frame: rect, image: image)
        canvas.delegate = delegate
        win.overlayView.addSubview(canvas)
        let bar = AnnotateToolbar(canvas: canvas)
        win.overlayView.addSubview(bar)
        let top = TopBar()
        top.onRecord = { [weak canvas] in canvas?.requestRecord() }
        top.onClose = { [weak canvas] in canvas?.cancel() }
        win.overlayView.addSubview(top)
        annotator = canvas
        toolbar = bar
        topBar = top
        layoutChrome()
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(canvas)
    }

    /// Frame handle dragged: re-crop and re-flow the chrome.
    func regionChanged(_ viewRect: CGRect) {
        guard let win = heldWindow, let canvas = annotator else { return }
        win.overlayView.heldRect = viewRect
        win.overlayView.needsDisplay = true
        let local = CoordinateSpace.displayLocalRect(viewRect: viewRect, screen: win.screenRef)
        if let img = cropProvider?(local) { canvas.replaceImage(img, frame: viewRect) }
        layoutChrome()
    }

    /// Slide the whole selection, kept inside the screen; the canvas re-crops as it goes.
    func moveRegion(dx: CGFloat, dy: CGFloat) {
        guard let win = heldWindow, let r = win.overlayView.heldRect else { return }
        let b = win.overlayView.bounds
        var f = r.offsetBy(dx: dx, dy: dy)
        f.origin.x = min(max(b.minX, f.minX), b.maxX - f.width)
        f.origin.y = min(max(b.minY, f.minY), b.maxY - f.height)
        // Round the origin only. `.integral` would round outward and the frame would grow a pixel per drag event.
        f.origin.x.round(); f.origin.y.round()
        regionChanged(f)
    }

    func regionCommit() {
        guard let win = heldWindow else { return }
        win.invalidateCursorRects(for: win.overlayView)
    }

    private func layoutChrome() {
        guard let win = heldWindow, let rect = win.overlayView.heldRect else { return }
        let bounds = win.overlayView.bounds
        if let bar = toolbar {
            bar.frame = Self.toolbarFrame(for: rect, size: bar.fittingSize, in: bounds)
            bar.didLayout()
        }
        if let top = topBar {
            let size = top.fittingSize
            var f = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: bounds.maxY - 28 - size.height, width: size.width, height: size.height)
            if f.intersects(rect.insetBy(dx: -8, dy: -8)) { f.origin.y = bounds.minY + 28 }
            if let bar = toolbar, f.intersects(bar.frame) { f.origin.y = bounds.maxY - 28 - size.height }
            top.frame = f
        }
    }

    private static func toolbarFrame(for rect: CGRect, size: CGSize, in bounds: CGRect) -> CGRect {
        let gap: CGFloat = 12
        var y = rect.minY - size.height - gap
        if y < bounds.minY + 4 {
            y = rect.maxY + gap
            if y + size.height > bounds.maxY - 4 { y = rect.minY + gap }
        }
        var x = rect.midX - size.width / 2
        x = min(max(bounds.minX + 4, x), bounds.maxX - size.width - 4)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// Tear everything down.
    func release() {
        isPresenting = false
        completion = nil
        cropProvider = nil
        HotKeyCenter.shared.unbind("picker.esc")
        annotator?.removeFromSuperview()
        toolbar?.subBar.removeFromSuperview()
        toolbar?.removeFromSuperview()
        topBar?.removeFromSuperview()
        annotator = nil
        toolbar = nil
        topBar = nil
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
    /// After a pick: freeze the drawing; the frame gets handles.
    var held = false
    var heldRect: CGRect?
    private var resizing: (handle: Int, anchor: CGRect)?
    static let handleSize: CGFloat = 9

    override var acceptsFirstResponder: Bool { true }

    /// 8 handles: corners then edge midpoints (index → which sides move).
    private func handles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
         CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY)]
    }

    override func resetCursorRects() {
        if !held { addCursorRect(bounds, cursor: .crosshair); return }
        guard let r = heldRect else { return }
        for h in handles(r) {
            addCursorRect(CGRect(x: h.x - 8, y: h.y - 8, width: 16, height: 16), cursor: .arrow)
        }
    }

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
        NSColor(calibratedWhite: 0, alpha: 0.5).setFill()
        bounds.fill()
        let hole: CGRect? = held ? heldRect : (controller?.mode == .window ? hoveredRectInView : selectionRect)
        guard let hole else { return }
        ctx.compositingOperation = .copy
        NSColor.clear.setFill()
        hole.fill()
        ctx.compositingOperation = .sourceOver
        // Square drop shadow outside the frame only (clipped away from the hole), so the edge reads on white too.
        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(hole)
        outside.windingRule = .evenOdd
        outside.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor(calibratedWhite: 0, alpha: 0.6).setFill()
        NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1)).fill()
        NSGraphicsContext.restoreGraphicsState()
        Theme.purple.setStroke()
        let path = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        path.stroke()
        if held {
            for h in handles(hole) {
                let s = Self.handleSize
                let sq = CGRect(x: h.x - s / 2, y: h.y - s / 2, width: s, height: s)
                Theme.purple.setFill()
                NSBezierPath(roundedRect: sq, xRadius: 1.5, yRadius: 1.5).fill()
                NSColor(calibratedWhite: 0, alpha: 0.35).setStroke()
                let o = NSBezierPath(roundedRect: sq.insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2)
                o.lineWidth = 1
                o.stroke()
            }
        }
        drawBadge(for: hole)
    }

    /// "918 × 502" pill at the top-right, outside the frame when there is room.
    private func drawBadge(for rect: CGRect) {
        let text: String
        if !held, controller?.mode == .window, let w = controller?.hoveredWindow {
            let app = w.owningApplication?.applicationName ?? ""
            let title = w.title ?? ""
            text = title.isEmpty ? app : "\(app) — \(title)"
        } else {
            let s = screenRef.backingScaleFactor
            text = "\(Int((rect.width * s).rounded())) × \(Int((rect.height * s).rounded()))"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium), .foregroundColor: Theme.text
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 9
        var box = CGRect(x: rect.maxX - size.width - pad * 2, y: rect.maxY + 10, width: size.width + pad * 2, height: size.height + 8)
        if box.maxY > bounds.maxY - 4 { box.origin.y = rect.maxY - box.height - 10 }
        box.origin.x = max(4, min(box.origin.x, bounds.maxX - box.width - 4))
        Theme.bg.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + 4), withAttributes: attrs)
    }

    private var overlayWindow: OverlayWindow? { window as? OverlayWindow }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if held {
            guard let r = heldRect,
                  let i = handles(r).firstIndex(where: { abs($0.x - p.x) <= 10 && abs($0.y - p.y) <= 10 }) else { return }
            resizing = (i, r)
            return
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        guard controller?.mode == .region else {
            controller?.updateHover(at: NSEvent.mouseLocation)
            return
        }
        dragStart = p
        dragCurrent = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(0, p.x), bounds.width); p.y = min(max(0, p.y), bounds.height)
        if held {
            guard let (i, a) = resizing else { return }
            var minX = a.minX, maxX = a.maxX, minY = a.minY, maxY = a.maxY
            switch i {
            case 0: minX = p.x; minY = p.y
            case 1: maxX = p.x; minY = p.y
            case 2: minX = p.x; maxY = p.y
            case 3: maxX = p.x; maxY = p.y
            case 4: minY = p.y
            case 5: maxY = p.y
            case 6: minX = p.x
            default: maxX = p.x
            }
            let r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY)).integral
            guard r.width >= 8, r.height >= 8 else { return }
            controller?.regionChanged(r)
            return
        }
        guard controller?.mode == .region, dragStart != nil else { return }
        dragCurrent = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if held {
            if resizing != nil { resizing = nil; controller?.regionCommit() }
            return
        }
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
