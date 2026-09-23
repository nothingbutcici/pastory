import AppKit
import ScreenCaptureKit

enum CaptureTarget {
    case display(SCDisplay)
    /// Region in display-local points, origin top-left.
    case region(SCDisplay, CGRect)
    case window(SCWindow)
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

    /// Front-to-back, so the first hit under the pointer is the window the user actually sees.
    /// SCShareableContent does not promise an order; the window server list does.
    /// `also`: our own windows that may be picked (the shelf; it sits above the normal layer, so it needs naming).
    func pickableWindows(also: Set<CGWindowID> = []) -> [SCWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let visible = content.windows.filter {
            $0.isOnScreen && $0.frame.width > 40 && $0.frame.height > 40
                && (($0.owningApplication?.processID != pid && $0.windowLayer == 0) || also.contains($0.windowID))
        }
        var order: [CGWindowID: Int] = [:]
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for (i, info) in list.enumerated() {
                if let n = info[kCGWindowNumber as String] as? CGWindowID, order[n] == nil { order[n] = i }
            }
        }
        return visible.sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
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

}
