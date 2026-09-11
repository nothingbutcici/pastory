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
        if let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme) {
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

    static func writeFiles(_ urls: [URL], itemID: String) {
        var items: [NSPasteboardItem] = []
        for (i, url) in urls.enumerated() {
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if i == 0 { item.setString(itemID, forType: marker) }
            items.append(item)
        }
        commit(items)
    }

    private static func commit(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items)
    }
}
