import AppKit

/// Hotkey → picker → ScreenCaptureKit → annotator → pasteboard + shelf.
@MainActor
final class CaptureCoordinator: AnnotateDelegate {
    static let shared = CaptureCoordinator()
    private var snapshot: ShareableSnapshot?
    private var fullImage: CGImage?
    private var fullScale: CGFloat = 2
    private var recording: RecordingSession?
    private(set) var isBusy = false
    private var ocrToken = UUID()
    /// Bumped by every start(); work resumed from an await belongs to a capture only while it matches.
    private var generation = 0
    static let source = ClipStore.Source(bundleID: "com.cici.snipclip", name: "Pastory")

    private init() {}

    /// Pictures of the displays taken before any of our windows existed; `picked` crops from these.
    private var frozen: [CGDirectDisplayID: CGImage] = [:]

    func start(mode: PickMode = .region) {
        if let recording, recording.isRecording { recording.stop(); return }   // hotkey again = stop recording
        if recording != nil { NSSound.beep(); return }      // preview / encoding is up: decide there first, nothing gets thrown away
        // Hotkey again while the picker or annotator is up: start over, but leave an open 识别文字 panel alone —
        // being able to screenshot that panel is the point.
        if isBusy { finish(keepOCRPanel: true) }
        OCRPanelController.shared.sinkBelowPicker()
        ocrToken = UUID()                    // a panel left over from the last capture is not this capture's text
        guard Permissions.ensureScreenRecording() else { return }
        isBusy = true
        generation += 1
        let gen = generation
        ShelfPanelController.shared.holdOpen = true      // the shelf may be what you want to capture
        Task { @MainActor in
            do {
                let snap = try await ShareableSnapshot.fetch()
                guard gen == generation else { return }      // the hotkey was pressed again meanwhile
                snapshot = snap
                // Photograph the screen under the pointer *before* any picker window exists: an open menu or drop-down
                // closes the instant another window appears, but by then it is already in the picture.
                var shots: [CGDirectDisplayID: CGImage] = [:]
                let mouse = NSEvent.mouseLocation
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main, let display = snap.display(for: screen),
                   let img = try? await Screenshotter.captureDisplay(display, excluding: [], backingScale: screen.backingScaleFactor, colorSpaceName: screen.colorSpace?.cgColorSpace?.name) {
                    shots[display.displayID] = img
                }
                guard gen == generation else { return }
                frozen = shots
                SelectionOverlayController.shared.present(snapshot: snap, mode: mode, frozen: shots) { [weak self] target in
                    self?.picked(target)
                }
            } catch {
                guard gen == generation else { return }
                NSSound.beep()
                finish()
            }
        }
    }

    private func picked(_ target: CaptureTarget?) {
        guard target != nil, let snapshot else { finish(); return }
        let overlay = SelectionOverlayController.shared
        guard let display = overlay.heldDisplay else { finish(); return }
        if overlay.wantsRecording { annotateRequestRecord(); return }      // 录屏 was chosen on the bar: straight to recording
        let screen = snapshot.screen(for: display)
        let gen = generation
        Task { @MainActor in
            do {
                let colorSpaceName = screen?.colorSpace?.cgColorSpace?.name
                let image: CGImage
                if let ready = frozen[display.displayID] { image = ready }     // the picture the user was looking at
                else { image = try await Screenshotter.captureDisplay(display, excluding: Set(overlay.ownWindowIDs), backingScale: screen?.backingScaleFactor, colorSpaceName: colorSpaceName) }
                guard gen == generation else { return }      // a newer capture owns the overlay now
                fullImage = image
                fullScale = CGFloat(image.width) / (screen?.frame.width ?? CGFloat(image.width))
                overlay.cropProvider = { [weak self] local in self?.crop(local) }
                guard let local = overlay.heldDisplayLocalRect, let cropped = crop(local) else { finish(); return }
                overlay.showAnnotator(image: cropped, delegate: self)
            } catch {
                guard gen == generation else { return }
                NSSound.beep()
                finish()
            }
        }
    }

    /// Display-local points (origin top-left) → pixels of the full capture.
    private func crop(_ local: CGRect) -> CGImage? {
        guard let fullImage else { return nil }
        let px = CGRect(x: local.minX * fullScale, y: local.minY * fullScale,
                        width: local.width * fullScale, height: local.height * fullScale).integral
        return fullImage.cropping(to: px.intersection(CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)))
    }

    func cancel() { if let recording { recording.cancel() } else { finish() } }

    // MARK: AnnotateDelegate

    func annotateDidFinish(_ image: CGImage) {
        guard let png = Screenshotter.pngData(image) else { finish(); return }
        let ocr = OCRPanelController.shared.token == ocrToken ? OCRPanelController.shared.currentText : nil
        let item = ClipStore.shared.insertImage(png: png, source: Self.source, ocrText: ocr)
        ShelfPanelController.shared.model.noteWelcomeTried("capture")
        PasteboardWriter.writeImage(png: png, itemID: item?.id ?? "")
        finish()
    }

    func annotateDidCancel() { finish() }

    func annotateMoveRegion(dx: CGFloat, dy: CGFloat) { SelectionOverlayController.shared.moveRegion(dx: dx, dy: dy) }

    func annotateRequestRecord() {
        // Record whatever the (possibly resized) frame covers now.
        let overlay = SelectionOverlayController.shared
        guard let rect = overlay.heldScreenRect, let display = overlay.heldDisplay, let local = overlay.heldDisplayLocalRect else { finish(); return }
        let target: CaptureTarget = local.size == overlay.heldScreenSize ? .display(display) : .region(display, local)
        OCRPanelController.shared.close()
        SelectionOverlayController.shared.release()
        let session = RecordingSession(target: target, regionScreenRect: rect)
        session.onFinish = { [weak self] in
            self?.recording = nil
            self?.finish()
        }
        recording = session
        session.start()
    }

    func annotateRequestOCR(_ image: CGImage) {
        let anchor = SelectionOverlayController.shared.heldScreenRect ?? .zero
        ocrToken = UUID()
        OCRPanelController.shared.show(near: anchor, image: image, token: ocrToken) { [weak self] text in
            let item = ClipStore.shared.insertText(text, rtf: nil, source: Self.source)
            PasteboardWriter.writeText(text, rtf: nil, itemID: item?.id ?? "")
            self?.finish()
        }
    }

    private func finish(keepOCRPanel: Bool = false) {
        if let recording { recording.cancel(); return }   // teardown calls back into finish()
        fullImage = nil
        frozen = [:]
        ShelfPanelController.shared.holdOpen = false
        if !keepOCRPanel { OCRPanelController.shared.close() }
        SelectionOverlayController.shared.release()
        snapshot = nil
        isBusy = false
    }
}
