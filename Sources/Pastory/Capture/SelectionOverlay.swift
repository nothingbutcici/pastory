import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

enum PickMode { case region, window }

/// Full-screen picker: drag a region, tap a window, F for the whole display.
/// After a pick the mask stays up, the frame grows paper handles (drag to resize; the canvas re-crops),
/// and the brand bar + annotator appear.
@MainActor
final class SelectionOverlayController {
    static let shared = SelectionOverlayController()
    private var overlays: [OverlayWindow] = []
    private var completion: ((CaptureTarget?) -> Void)?
    private(set) var isPresenting = false
    private(set) var mode: PickMode = .region
    private(set) var hoveredWindow: SCWindow?
    private(set) var annotator: AnnotateView?
    private var toolbar: AnnotateToolbar?
    private var topBar: TopBar?
    private var recordBar: RecordReadyBar?
    private var appToRestore: NSRunningApplication?
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

    func present(snapshot: ShareableSnapshot, mode: PickMode, frozen: [CGDirectDisplayID: CGImage] = [:], completion: @escaping (CaptureTarget?) -> Void) {
        if isPresenting || !overlays.isEmpty { release() }
        isPresenting = true
        // While picking, the overlay is NOT the key window: taking key focus from the front app closes its menus,
        // drop-downs and popovers before we can photograph them. Keys come in through system-wide hooks instead
        // (unbound the moment the annotator takes over).
        HotKeyCenter.shared.bindRaw(keyCode: 53, modifiers: 0, name: "picker.esc") {
            MainActor.assumeIsolated { CaptureCoordinator.shared.cancel() }
        }
        HotKeyCenter.shared.bindRaw(keyCode: 49, modifiers: 0, name: "picker.space") {
            MainActor.assumeIsolated { SelectionOverlayController.shared.toggleMode() }
        }
        for (code, name) in [(3, "picker.f"), (36, "picker.return"), (76, "picker.enter")] {
            HotKeyCenter.shared.bindRaw(keyCode: UInt32(code), modifiers: 0, name: name) {
                MainActor.assumeIsolated { SelectionOverlayController.shared.pickWholeScreen() }
            }
        }
        self.completion = completion
        self.mode = mode
        hoveredWindow = nil

        let pickable = snapshot.pickableWindows(also: Set([ShelfPanelController.shared.windowID].compactMap { $0 }))
        for screen in NSScreen.screens {
            guard let display = snapshot.display(for: screen) else { continue }
            let w = OverlayWindow(screen: screen, display: display)
            w.overlayView.controller = self
            w.overlayView.backdrop = frozen[display.displayID]
            w.overlayView.candidates = pickable.map { ($0, CoordinateSpace.cocoaRect(fromCG: $0.frame)) }
            overlays.append(w)
        }
        overlays.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        // The screen under the pointer was photographed before this point, so whatever the app in front closes when it
        // loses focus is already in the picture. Becoming the active app is what makes the crosshair possible: macOS
        // ignores cursor changes from background apps. Focus goes back to that app in release().
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { appToRestore = front }      // on a restart we are frontmost: keep the one we have
        NSApp.activate(ignoringOtherApps: true)
        (overlays.first(where: { $0.screenRef.frame.contains(mouse) }) ?? overlays.first)?.makeKey()
        overlays.forEach { $0.invalidateCursorRects(for: $0.overlayView) }
        // The 截屏 / 录屏 bar is up from the first frame, on the screen under the pointer.
        if let host = overlays.first(where: { $0.screenRef.frame.contains(mouse) }) ?? overlays.first {
            let top = TopBar()
            top.onClose = { [weak self] in self?.finish(nil, viewRect: nil, on: nil) }
            let size = top.fittingSize
            let b = host.overlayView.bounds
            top.frame = CGRect(x: (b.midX - size.width / 2).rounded(), y: b.maxY - 28 - size.height, width: size.width, height: size.height)
            host.overlayView.addSubview(top)
            topBar = top
        }
        updateHover(at: mouse)
        NSCursor.crosshair.set()
        refreshAll()
    }

    /// 录屏 chosen on the bar before the selection was made.
    var wantsRecording: Bool { topBar?.wantsRecording ?? false }

    /// F / ⏎ during picking: the whole display under the pointer.
    func pickWholeScreen() {
        guard isPresenting, let w = overlays.first(where: { $0.screenRef.frame.contains(NSEvent.mouseLocation) }) ?? overlays.first else { return }
        finish(.display(w.display), viewRect: w.overlayView.bounds, on: w)
    }

    private static let pickerHooks = ["picker.esc", "picker.space", "picker.f", "picker.return", "picker.enter"]
    private func unbindPickerHooks() { Self.pickerHooks.forEach { HotKeyCenter.shared.unbind($0) } }

    func toggleMode() {
        mode = mode == .region ? .window : .region
        hoveredWindow = nil
        updateHover(at: NSEvent.mouseLocation)
        refreshAll()
    }

    /// The window under the pointer is lit in both modes: in region mode a plain click takes it, a drag takes a region.
    func updateHover(at p: CGPoint) {
        guard let overlay = overlays.first else { return }
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
        // Keep the bar that has been up since the picker opened; re-add so it sits above the canvas that was just added.
        let top = topBar ?? TopBar()
        top.removeFromSuperview(); win.overlayView.addSubview(top)
        top.immediateRecord = true
        top.onRecord = { [weak self] in self?.enterRecordMode() }
        top.onShot = { [weak self] in self?.leaveRecordMode() }
        top.onClose = { [weak canvas] in canvas?.cancel() }
        annotator = canvas
        toolbar = bar
        topBar = top
        if top.wantsRecording { enterRecordMode() }          // 录屏 was chosen before the pick: land in the record-ready frame
        // The picture is taken; from here the canvas owns the keyboard (⎋ deselects, leaves the text box, then cancels).
        unbindPickerHooks()
        layoutChrome()
        NSCursor.arrow.set()
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(canvas)
    }

    /// 录屏 on the top bar: keep the frame and its handles, hide the annotation tools, offer 开始录制.
    private func enterRecordMode() {
        guard let win = heldWindow, let canvas = annotator, recordBar == nil else { return }
        canvas.recordMode = true
        toolbar?.isHidden = true
        toolbar?.subBar.isHidden = true
        let bar = RecordReadyBar()
        bar.onStart = { [weak canvas] in canvas?.requestRecord() }
        bar.onCancel = { [weak canvas] in canvas?.cancel() }
        win.overlayView.addSubview(bar)
        recordBar = bar
        layoutChrome()
    }

    /// 截屏 on the top bar: back to the annotation tools.
    private func leaveRecordMode() {
        guard let canvas = annotator, recordBar != nil else { return }
        recordBar?.removeFromSuperview(); recordBar = nil
        canvas.recordMode = false
        toolbar?.isHidden = false
        toolbar?.subBar.isHidden = false
        layoutChrome()
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
        if let rb = recordBar { rb.frame = Self.toolbarFrame(for: rect, size: rb.fittingSize, in: bounds) }
        if let top = topBar {
            let size = top.fittingSize
            var f = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: bounds.maxY - 28 - size.height, width: size.width, height: size.height)
            if f.intersects(rect.insetBy(dx: -8, dy: -8)) { f.origin.y = bounds.minY + 28 }
            let below: CGRect? = recordBar?.frame ?? toolbar?.frame
            if let below, f.intersects(below) { f.origin.y = bounds.maxY - 28 - size.height }
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

    /// A picked window is captured live: give the front app its focus back first, so it is drawn active.
    func reactivateFrontApp() { if let app = appToRestore, !app.isTerminated { app.activate() } }

    /// Tear everything down. `restoreFocus: false` is the restart path (hotkey pressed again mid-capture): the picker
    /// comes straight back, and the app to return to must survive until the capture really ends.
    func release(restoreFocus: Bool = true) {
        isPresenting = false
        completion = nil
        cropProvider = nil
        unbindPickerHooks()
        NSCursor.arrow.set()
        annotator?.removeFromSuperview()
        toolbar?.subBar.removeFromSuperview()
        recordBar?.removeFromSuperview()
        recordBar = nil
        toolbar?.removeFromSuperview()
        topBar?.removeFromSuperview()
        annotator = nil
        toolbar = nil
        topBar = nil
        overlays.forEach { $0.orderOut(nil); $0.close() }
        overlays.removeAll()
        guard restoreFocus else { return }
        // Hand the keyboard back, unless one of our own titled windows (image editor, text editor, recording preview,
        // OCR panel) has it.
        if let app = appToRestore, !app.isTerminated, NSApp.keyWindow?.styleMask.contains(.titled) != true { app.activate() }
        appToRestore = nil
    }
}

final class OverlayWindow: NSPanel {
    let screenRef: NSScreen
    let display: SCDisplay
    let overlayView: OverlayView

    init(screen: NSScreen, display: SCDisplay) {
        screenRef = screen
        self.display = display
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlayView.screenRef = screen
        overlayView.display = display
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))      // above other tools' floating bars (they use screenSaver+)
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = overlayView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    // Becoming main would activate the app: the menu bar would switch to Pastory's (empty) one and end up in the picture.
    override var canBecomeMain: Bool { false }
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
    /// The screen as it was the instant the hotkey was pressed. Drawn under the mask, so whatever closes when our
    /// windows appear (menus, drop-downs) is still there to be framed.
    var backdrop: CGImage?
    private var resizing: (handle: Int, anchor: CGRect)?
    static let handleSize: CGFloat = 9

    override var acceptsFirstResponder: Bool { true }
    /// The very first press must start the drag even when macOS has not made us key yet.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
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
        if let backdrop {
            ctx.cgContext.interpolationQuality = .none
            ctx.cgContext.draw(backdrop, in: bounds)
        }
        NSColor(calibratedWhite: 0, alpha: 0.5).setFill()
        bounds.fill()
        let hole: CGRect? = held ? heldRect : (dragStart != nil ? selectionRect : hoveredRectInView)
        guard let hole else { return }
        if let backdrop {
            // Punch the hole in the dimming only: the frozen picture shows through undimmed.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: hole).addClip()
            ctx.cgContext.interpolationQuality = .none
            ctx.cgContext.draw(backdrop, in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            ctx.compositingOperation = .copy
            NSColor.clear.setFill()
            hole.fill()
            ctx.compositingOperation = .sourceOver
        }
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
        Theme.paperBlue.setStroke()
        let path = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
        path.lineWidth = 2
        path.stroke()
        if held {
            for h in handles(hole) {
                let s = Self.handleSize
                let sq = CGRect(x: h.x - s / 2, y: h.y - s / 2, width: s, height: s)
                Theme.paper.setFill()
                NSBezierPath(roundedRect: sq, xRadius: 1.5, yRadius: 1.5).fill()
                Theme.ink.withAlphaComponent(0.7).setStroke()
                let o = NSBezierPath(roundedRect: sq.insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2)
                o.lineWidth = 1
                o.stroke()
            }
        }
        if held || dragStart != nil { drawBadge(for: hole) }      // hovering a window shows no label, just the light
    }

    /// "918 × 502" pill at the top-right, outside the frame when there is room.
    private func drawBadge(for rect: CGRect) {
        let text: String
        if !held, dragStart == nil, let w = controller?.hoveredWindow {
            let app = w.owningApplication?.applicationName ?? ""
            let title = w.title ?? ""
            text = title.isEmpty ? app : "\(app) — \(title)"
        } else {
            let s = screenRef.backingScaleFactor
            text = "\(Int((rect.width * s).rounded())) × \(Int((rect.height * s).rounded()))"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.serif(size: 13), .foregroundColor: Theme.onBrown
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 9
        var box = CGRect(x: rect.maxX - size.width - pad * 2, y: rect.maxY + 10, width: size.width + pad * 2, height: size.height + 8)
        if box.maxY > bounds.maxY - 4 { box.origin.y = rect.maxY - box.height - 10 }
        box.origin.x = max(4, min(box.origin.x, bounds.maxX - box.width - 4))
        Theme.drawDesk(NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4))
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
        guard controller?.mode == .region else {
            controller?.updateHover(at: NSEvent.mouseLocation)
            return
        }
        dragStart = p
        dragCurrent = p
        needsDisplay = true          // the hovered window's highlight gives way to the region as soon as the drag moves
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
            // A plain click takes the window under the pointer; on bare desktop it cancels.
            controller?.updateHover(at: NSEvent.mouseLocation)
            if let w = controller?.hoveredWindow {
                let r = windowRectInView(CoordinateSpace.cocoaRect(fromCG: w.frame))
                controller?.finish(.window(w), viewRect: r, on: overlayWindow)
            } else {
                controller?.finish(nil, viewRect: nil, on: nil)
            }
            return
        }
        let snapped = rect.integral
        controller?.finish(.region(display, CoordinateSpace.displayLocalRect(viewRect: snapped, screen: screenRef)),
                           viewRect: snapped, on: overlayWindow)
    }

    override func rightMouseUp(with event: NSEvent) { if !held { controller?.finish(nil, viewRect: nil, on: nil) } }

    override func mouseMoved(with event: NSEvent) {
        guard !held else { return }
        let p = convert(event.locationInWindow, from: nil)
        if subviews.contains(where: { $0 is TopBar && $0.frame.contains(p) }) { NSCursor.arrow.set(); return }
        NSCursor.crosshair.set()
        controller?.updateHover(at: NSEvent.mouseLocation)
    }
    override func mouseEntered(with event: NSEvent) { if !held { NSCursor.crosshair.set() } }

    override func keyDown(with event: NSEvent) {
        guard !held else { super.keyDown(with: event); return }
        switch Int(event.keyCode) {
        case kVK_Escape: controller?.finish(nil, viewRect: nil, on: nil)
        case kVK_Space: controller?.toggleMode()
        case kVK_ANSI_F, kVK_Return, kVK_ANSI_KeypadEnter:
            controller?.finish(.display(display), viewRect: bounds, on: overlayWindow)
        default: break          // we are the key window now; an unbound key is ignored, not beeped at
        }
    }

    override func cancelOperation(_ sender: Any?) { if !held { controller?.finish(nil, viewRect: nil, on: nil) } }
}


/// The bar under the frame while record-ready: a hint, 开始录制 (⏎) and 取消.
final class RecordReadyBar: NSView {
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let hint = NSTextField(labelWithString: "拖动边框调整录制范围".l)
        hint.font = Theme.serif(size: 13)
        hint.textColor = Theme.onBrownMuted
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(Theme.deskDivider(height: 24))
        let cancel = Theme.paperButton("取消".l, onGround: true, target: self, action: #selector(cancelTapped))
        let start = Theme.paperButton("开始录制 ⏎".l, primary: true, target: self, action: #selector(startTapped))
        stack.addArrangedSubview(cancel)
        stack.addArrangedSubview(start)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: CGSize { CGSize(width: stack.fittingSize.width, height: 56) }
    override func draw(_ dirtyRect: NSRect) { Theme.drawDesk(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Theme.paperRadius, yRadius: Theme.paperRadius)) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    @objc private func startTapped() { onStart?() }
    @objc private func cancelTapped() { onCancel?() }
}
