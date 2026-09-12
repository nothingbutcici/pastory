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
    static let source = ClipStore.Source(bundleID: "com.cici.snipclip", name: "Pastory")

    private init() {}

    func start(mode: PickMode = .region) {
        if let recording, recording.isRecording { recording.stop(); return }   // hotkey again = stop recording
        if recording != nil { NSSound.beep(); return }      // preview / encoding is up: decide there first, nothing gets thrown away
        // Hotkey again while the picker or annotator is up: start over, but leave an open 识别文字 panel alone —
        // being able to screenshot that panel is the point.
        if isBusy { finish(keepOCRPanel: true) }
        ocrToken = UUID()                    // a panel left over from the last capture is not this capture's text
        guard Permissions.ensureScreenRecording() else { return }
        isBusy = true
        ShelfPanelController.shared.holdOpen = true      // the shelf may be what you want to capture
        Task { @MainActor in
            do {
                let snap = try await ShareableSnapshot.fetch()
                snapshot = snap
                SelectionOverlayController.shared.present(snapshot: snap, mode: mode) { [weak self] target in
                    self?.picked(target)
                }
            } catch {
                NSSound.beep()
                finish()
            }
        }
    }

    private func picked(_ target: CaptureTarget?) {
        guard target != nil, let snapshot else { finish(); return }
        let overlay = SelectionOverlayController.shared
        guard let display = overlay.heldDisplay else { finish(); return }
        let screen = snapshot.screen(for: display)
        Task { @MainActor in
            do {
                let colorSpaceName = screen?.colorSpace?.cgColorSpace?.name
                let image = try await Screenshotter.captureDisplay(display, excluding: Set(overlay.ownWindowIDs), screen: screen, colorSpaceName: colorSpaceName)
                fullImage = image
                fullScale = CGFloat(image.width) / (screen?.frame.width ?? CGFloat(image.width))
                overlay.cropProvider = { [weak self] local in self?.crop(local) }
                guard let local = overlay.heldDisplayLocalRect, let cropped = crop(local) else { finish(); return }
                overlay.showAnnotator(image: cropped, delegate: self)
            } catch {
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
        ShelfPanelController.shared.holdOpen = false
        if !keepOCRPanel { OCRPanelController.shared.close() }
        SelectionOverlayController.shared.release()
        snapshot = nil
        isBusy = false
    }
}
