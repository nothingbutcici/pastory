import AppKit

/// Hotkey → picker → ScreenCaptureKit → annotator → pasteboard + shelf.
@MainActor
final class CaptureCoordinator: AnnotateDelegate {
    static let shared = CaptureCoordinator()
    private var snapshot: ShareableSnapshot?
    private var pickedTarget: CaptureTarget?
    private var fullImage: CGImage?
    private var fullScale: CGFloat = 2
    private var recording: RecordingSession?
    private(set) var isBusy = false
    static let source = ClipStore.Source(bundleID: "com.cici.snipclip", name: "Snip Clip")

    private init() {}

    func start(mode: PickMode = .region) {
        if let recording, recording.isRecording { recording.stop(); return }   // hotkey again = stop recording
        if isBusy { cancel(); return }      // pressing the hotkey again backs out
        guard Permissions.ensureScreenRecording() else { return }
        isBusy = true
        ShelfPanelController.shared.hide()
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
        guard let target, let snapshot else { finish(); return }
        pickedTarget = target
        let overlay = SelectionOverlayController.shared
        guard let display = overlay.heldDisplay else { finish(); return }
        let screen = snapshot.screen(for: display)
        Task { @MainActor in
            do {
                let colorSpaceName = screen?.colorSpace?.cgColorSpace?.name
                let image = try await Screenshotter.captureDisplay(display, colorSpaceName: colorSpaceName)
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
        let ocr = OCRPanelController.shared.currentText
        let item = ClipStore.shared.insertImage(png: png, source: Self.source, ocrText: ocr)
        PasteboardWriter.writeImage(png: png, itemID: item?.id ?? "")
        finish()
    }

    func annotateDidCancel() { finish() }

    func annotateRequestRecord() {
        // Record whatever the (possibly resized) frame covers now.
        let overlay = SelectionOverlayController.shared
        guard let rect = overlay.heldScreenRect, let display = overlay.heldDisplay, let local = overlay.heldDisplayLocalRect else { finish(); return }
        let target: CaptureTarget = local.size == overlay.heldScreenSize ? .display(display) : .region(display, local)
        _ = pickedTarget
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
        OCRPanelController.shared.show(near: anchor, image: image) { [weak self] text in
            let item = ClipStore.shared.insertText(text, rtf: nil, source: Self.source)
            PasteboardWriter.writeText(text, rtf: nil, itemID: item?.id ?? "")
            self?.finish()
        }
    }

    func cancelRecording() { recording?.cancel() }

    private func finish() {
        if let recording { recording.cancel(); return }   // teardown calls back into finish()
        pickedTarget = nil
        fullImage = nil
        OCRPanelController.shared.close()
        SelectionOverlayController.shared.release()
        snapshot = nil
        isBusy = false
    }
}
