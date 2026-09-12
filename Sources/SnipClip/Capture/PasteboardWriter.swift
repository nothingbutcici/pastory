import AppKit

/// Everything Snip Clip puts on the pasteboard carries `marker` = item id so the
/// monitor bumps the existing item instead of recording a duplicate.
enum PasteboardWriter {
    static let marker = NSPasteboard.PasteboardType("com.cici.snipclip.marker")

    static func writeImage(png: Data, itemID: String) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let cg = Screenshotter.image(fromPNG: png), let tiff = Screenshotter.tiffData(cg) {
            item.setData(tiff, forType: .tiff)
        }
        item.setString(itemID, forType: marker)
        commit([item])
    }

    static func writeText(_ text: String, rtf: Data?, itemID: String) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let rtf { item.setData(rtf, forType: .rtf) }
        if ClipItem.isURLText(text) {
            item.setString(text, forType: .URL)
        }
        item.setString(itemID, forType: marker)
        commit([item])
    }

    /// Animated GIF as image data (chat apps paste it as a moving picture, not an attachment).
    static func writeGIF(_ data: Data, itemID: String) {
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        item.setString(itemID, forType: marker)
        commit([item])
    }

    /// Files the way Finder copies them: NSURL objects plus the legacy filenames list.
    /// Chat apps (WeChat included) look for the latter; a bare public.file-url pastes as text there.
    static func writeFiles(_ urls: [URL], itemID: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        pb.setPropertyList(urls.map(\.path), forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        pb.setString(itemID, forType: marker)
    }

    private static func commit(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items)
    }
}
