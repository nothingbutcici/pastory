import SwiftUI

/// One shelf card: dark frame, cream "paper" for the content, caption, three big actions. Tapping copies.
struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    /// This item is what the pasteboard holds right now.
    let onClipboard: Bool
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void

    static let width: CGFloat = 268

    var body: some View {
        VStack(spacing: 0) {
            header
            paper
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
            captionRow
            Divider().overlay(Color.shelfBorder)
            actions
        }
        .frame(width: Self.width)
        .background(Color.shelfCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? Color.purple : Color.shelfBorder, lineWidth: selected ? 2.5 : 1))
        .shadow(color: .black.opacity(selected ? 0.35 : 0.2), radius: 10, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(count: 2, perform: onCopyAndClose)
        .onTapGesture(count: 1, perform: onCopy)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = appIcon { Image(nsImage: icon).resizable() }
                else { Image(systemName: "doc.on.clipboard").font(.system(size: 14)).foregroundStyle(Color.shelfMuted) }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(item.sourceAppName ?? item.kind.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.shelfInk).lineLimit(1)
            Spacer()
            Text(item.createdAt, style: .time).font(.system(size: 13).monospacedDigit()).foregroundStyle(Color.shelfMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// Cream panel holding the content; images fill it edge to edge.
    @ViewBuilder
    private var paper: some View {
        switch item.kind {
        case .image, .video:
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Color.cream)
                if let img = ClipStore.shared.thumbnail(of: item) {
                    VStack(spacing: 0) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                } else {
                    Image(systemName: item.kind == .video ? "film" : "photo").font(.largeTitle).foregroundStyle(Color.creamInk.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if item.kind == .video {
                    ZStack {
                        Circle().fill(.black.opacity(0.5)).frame(width: 54, height: 54)
                        Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white).offset(x: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .files:
            paperBox {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(item.snippet.split(separator: "\n").prefix(8), id: \.self) { line in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill").font(.system(size: 13)).foregroundStyle(Color.creamInk.opacity(0.55))
                            Text(line).font(.system(size: 14)).foregroundStyle(Color.creamInk).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        case .url:
            paperBox {
                VStack(alignment: .leading, spacing: 6) {
                    if let host = URL(string: item.snippet)?.host { Text(host).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.creamInk) }
                    Text(item.snippet).font(.system(size: 14)).foregroundStyle(Color(nsColor: NSColor(srgbRed: 0.20, green: 0.40, blue: 0.80, alpha: 1))).lineLimit(6)
                }
            }
        case .text:
            paperBox {
                Text(item.snippet)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.creamInk)
                    .lineSpacing(5)
                    .lineLimit(10)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func paperBox<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color.cream)
            content().padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// One left-aligned row: [✓ 已复制] [类型] [备注]
    private var captionRow: some View {
        HStack(spacing: 6) {
            if onClipboard {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    Text("已复制").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Color.onPurple)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.purple, in: Capsule())
            }
            Text(note.map { "\(kindLabel) · \($0)" } ?? kindLabel)
                .font(.system(size: 13)).foregroundStyle(Color.shelfMuted).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func tag(_ text: String, color: Color, ink: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 12.5)).foregroundStyle(ink ?? color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(Capsule().stroke(color, lineWidth: 1))
            .lineLimit(1)
    }

    private var kindLabel: String {
        switch item.kind {
        case .image: return "图片"
        case .text: return "文本"
        case .url: return "链接"
        case .files: return "文件"
        case .video: return item.ext.uppercased()
        }
    }

    private var note: String? {
        switch item.kind {
        case .image: return item.snippet.replacingOccurrences(of: "×", with: " × ")
        case .text: return "\(charCount) 字"
        case .url: return nil
        case .files: return "\(item.snippet.split(separator: "\n").count) 项"
        case .video: return durationText
        }
    }

    private var tagColor: NSColor {
        switch item.kind {
        case .image: return Theme.tagImage
        case .text: return Theme.tagText
        case .url: return Theme.tagLink
        case .files: return Theme.tagFiles
        case .video: return item.ext == "gif" ? Theme.tagGIF : Theme.tagMP4
        }
    }

    private var charCount: Int { item.snippet.count >= 400 ? item.byteCount / 3 : item.snippet.count }

    private var durationText: String {
        let s = Int((item.duration ?? 0).rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 编辑（文本 / 链接 / 图片）或预览（录屏 / 文件） · Pin · (保存，仅图片 / 录屏) · 删除
    private var actions: some View {
        HStack {
            Spacer()
            if item.kind == .text || item.kind == .url || item.kind == .image {
                action("pencil", item.kind == .image ? "编辑标注" : "编辑文字", onEdit)
            } else {
                action("eye", "预览", onPreview)
            }
            Spacer()
            action("pin", "Pin 住，不会被自动清理", active: item.pinned) { ClipStore.shared.togglePin(item.id) }
            Spacer()
            if item.kind == .image || item.kind == .video {
                action("arrow.down.to.line", "保存到本地…") { Exporter.export(item) }
                Spacer()
            }
            action("trash", "删除") { ClipStore.shared.remove(item.id) }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func action(_ symbol: String, _ tip: String, active: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: active ? "pin.fill" : symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(active ? Color(nsColor: Theme.onLime) : Color.shelfInk)
                .frame(width: 44, height: 38)
                .background(active ? Color.lime : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    private var appIcon: NSImage? {
        if item.sourceBundleID == "com.cici.snipclip" { return Theme.logo }
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
