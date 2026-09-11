import AppKit

/// Hotkey → picker → ScreenCaptureKit → annotator → pasteboard + shelf.
@MainActor
final class CaptureCoordinator: AnnotateDelegate {
    static let shared = CaptureCoordinator()
    private var snapshot: ShareableSnapshot?
    private(set) var isBusy = false
    static let source = ClipStore.Source(bundleID: "com.cici.snipclip", name: "Snip Clip")

    private init() {}

    func start(mode: PickMode = .region) {
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
        Task { @MainActor in
            do {
                let image = try await Screenshotter.capture(target, snapshot: snapshot)
                SelectionOverlayController.shared.showAnnotator(image: image, delegate: self)
            } catch {
                NSSound.beep()
                finish()
            }
        }
    }

    func cancel() { finish() }

    // MARK: AnnotateDelegate

    func annotateDidFinish(_ image: CGImage) {
        guard let png = Screenshotter.pngData(image) else { finish(); return }
        let ocr = OCRPanelController.shared.currentText
        let item = ClipStore.shared.insertImage(png: png, source: Self.source, ocrText: ocr)
        PasteboardWriter.writeImage(png: png, itemID: item?.id ?? "")
        finish()
    }

    func annotateDidCancel() { finish() }

    func annotateRequestOCR(_ image: CGImage) {
        let anchor = SelectionOverlayController.shared.heldScreenRect ?? .zero
        OCRPanelController.shared.show(near: anchor, image: image) { [weak self] text in
            let item = ClipStore.shared.insertText(text, rtf: nil, source: Self.source)
            PasteboardWriter.writeText(text, rtf: nil, itemID: item?.id ?? "")
            self?.finish()
        }
    }

    private func finish() {
        OCRPanelController.shared.close()
        SelectionOverlayController.shared.release()
        snapshot = nil
        isBusy = false
    }
}
