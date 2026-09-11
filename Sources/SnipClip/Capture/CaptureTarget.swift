import AppKit
import ScreenCaptureKit

enum CaptureKind { case region, display, window }

enum CaptureTarget {
    case display(SCDisplay)
    /// Region in display-local points, origin top-left.
    case region(SCDisplay, CGRect)
    case window(SCWindow)

    var kindName: String {
        switch self {
        case .display: return "display"
        case .region: return "region"
        case .window: return "window"
        }
    }
}

struct ShareableSnapshot {
    let content: SCShareableContent
    let ownWindows: [SCWindow]

    static func fetch() async throws -> ShareableSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        return ShareableSnapshot(content: content,
                                 ownWindows: content.windows.filter { $0.owningApplication?.processID == pid })
    }

    func display(for screen: NSScreen) -> SCDisplay? {
        guard let n = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return nil }
        return content.displays.first { $0.displayID == CGDirectDisplayID(n.uint32Value) }
    }

    func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }
    }

    var pickableWindows: [SCWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter {
            $0.isOnScreen && $0.owningApplication?.processID != pid
                && $0.frame.width > 40 && $0.frame.height > 40 && $0.windowLayer == 0
        }
    }
}

enum CoordinateSpace {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// CG global (top-left origin) → Cocoa global (bottom-left origin).
    static func cocoaRect(fromCG r: CGRect) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }

    /// Overlay-view rect → display-local top-left points.
    static func displayLocalRect(viewRect: CGRect, screen: NSScreen) -> CGRect {
        CGRect(x: viewRect.origin.x.rounded(), y: (screen.frame.height - viewRect.maxY).rounded(),
               width: viewRect.width.rounded(), height: viewRect.height.rounded())
    }

    /// The captured area in Cocoa global points — what the cursor tracker normalizes against.
    static func cocoaCaptureRect(_ target: CaptureTarget, snapshot: ShareableSnapshot) -> CGRect {
        switch target {
        case .display(let d):
            return snapshot.screen(for: d)?.frame ?? cocoaRect(fromCG: d.frame)
        case .region(let d, let local):
            let s = snapshot.screen(for: d)?.frame ?? cocoaRect(fromCG: d.frame)
            return CGRect(x: s.minX + local.minX, y: s.maxY - local.minY - local.height,
                          width: local.width, height: local.height)
        case .window(let w):
            return cocoaRect(fromCG: w.frame)
        }
    }
}
