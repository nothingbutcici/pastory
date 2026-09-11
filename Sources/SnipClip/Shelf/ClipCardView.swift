import SwiftUI

/// One shelf card: app + time, the content, a caption, and three big actions. Tapping copies.
struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    /// This item is what the pasteboard holds right now.
    let onClipboard: Bool
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onPreview: () -> Void

    static let width: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            captionRow
            Divider().overlay(Color.shelfBorder)
            actions
        }
        .frame(width: Self.width)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? Color.lime : Color.shelfBorder, lineWidth: selected ? 2.5 : 1))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
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
            Text(item.sourceAppName ?? item.kind.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.shelfInk).lineLimit(1)
            Spacer()
            Text(item.createdAt, style: .time).font(.system(size: 13).monospacedDigit()).foregroundStyle(Color.shelfMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image, .video:
            if let img = ClipStore.shared.thumbnail(of: item) {
                VStack(spacing: 0) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.shelfBorder, lineWidth: 1))
                        .overlay {
                            if item.kind == .video {
                                ZStack {
                                    Circle().fill(.black.opacity(0.55)).frame(width: 52, height: 52)
                                    Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white).offset(x: 2)
                                }
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if item.kind == .video {
                                Text("\(item.ext.uppercased()) · \(durationText)")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                                    .padding(8)
                            }
                        }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo").font(.largeTitle).foregroundStyle(Color.shelfMuted.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.snippet.split(separator: "\n").prefix(8), id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill").font(.system(size: 13)).foregroundStyle(Color.shelfMuted)
                        Text(line).font(.system(size: 14)).foregroundStyle(Color.shelfInk).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 2)
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                if let host = URL(string: item.snippet)?.host { Text(host).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.shelfInk) }
                Text(item.snippet).font(.system(size: 14)).foregroundStyle(Color(nsColor: NSColor(srgbRed: 0.16, green: 0.52, blue: 0.94, alpha: 1))).lineLimit(6)
            }
            .padding(.horizontal, 16).padding(.top, 2)
        case .text:
            Text(item.snippet)
                .font(.system(size: 15))
                .foregroundStyle(Color.shelfInk)
                .lineSpacing(5)
                .lineLimit(11)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16).padding(.top, 2)
        }
    }

    private var captionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if onClipboard {
                Text("已复制").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.shelfInk)
                    .padding(.horizontal, 12).padding(.vertical, 5).background(Color.lime, in: Capsule())
            }
            Text(caption).font(.system(size: 13)).foregroundStyle(Color.shelfMuted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var caption: String {
        switch item.kind {
        case .image: return "图片 · \(item.snippet.replacingOccurrences(of: "×", with: " × "))"
        case .text: return "文本 · \(charCount) 字"
        case .url: return "链接"
        case .files: return "文件 · \(item.snippet.split(separator: "\n").count) 项"
        case .video: return "录屏 · \(durationText)"
        }
    }

    private var charCount: Int { item.snippet.count >= 400 ? item.byteCount / 3 : item.snippet.count }

    private var durationText: String {
        let s = Int((item.duration ?? 0).rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 预览 · Pin · (保存，仅图片 / 录屏) · 删除
    private var actions: some View {
        HStack {
            Spacer()
            action("eye", "预览完整内容", onPreview)
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
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color.shelfInk)
                .frame(width: 40, height: 36)
                .background(active ? Color.lime : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
