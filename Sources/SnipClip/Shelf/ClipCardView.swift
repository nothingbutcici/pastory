import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    let onCopy: () -> Void
    @State private var hovering = false

    private var tint: Color {
        switch item.kind {
        case .text: return Color(nsColor: NSColor(srgbRed: 0.45, green: 0.50, blue: 0.62, alpha: 1))
        case .url: return Color(nsColor: NSColor(srgbRed: 0.10, green: 0.50, blue: 0.95, alpha: 1))
        case .image: return Color(nsColor: NSColor(srgbRed: 0.56, green: 0.42, blue: 1.00, alpha: 1))
        case .files: return Color(nsColor: NSColor(srgbRed: 0.95, green: 0.60, blue: 0.15, alpha: 1))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            body_
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.9))
            footer
        }
        .frame(width: 230)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? tint : .white.opacity(0.12), lineWidth: selected ? 2.5 : 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) { if hovering { actions } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
            Text(item.sourceAppName ?? item.kind.label).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer()
            if item.pinned { Image(systemName: "pin.fill").font(.caption2) }
            Text(item.createdAt, style: .time).font(.caption2).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tint)
    }

    @ViewBuilder
    private var body_: some View {
        switch item.kind {
        case .image:
            if let img = ClipStore.shared.thumbnail(of: item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
            }
        case .files:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.snippet.split(separator: "\n").prefix(6), id: \.self) { line in
                    HStack(spacing: 6) {
                        Image(systemName: "doc").foregroundStyle(.secondary).font(.caption)
                        Text(line).font(.callout).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .text, .url:
            VStack(alignment: .leading) {
                Text(item.snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(item.kind == .url ? .blue : .primary)
                    .lineLimit(14)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if item.kind == .image, item.ocrText?.isEmpty == false {
                Image(systemName: "text.viewfinder").font(.caption2).foregroundStyle(.secondary).help("已识别文字")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }

    private var footerText: String {
        switch item.kind {
        case .image: return "图片 · \(item.snippet)"
        case .text: return "文本 · \(item.byteCount) 字节"
        case .url: return "链接"
        case .files: return "文件 · \(item.snippet.split(separator: "\n").count) 项"
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            act(item.pinned ? "pin.slash" : "pin", item.pinned ? "取消固定" : "固定") { ClipStore.shared.togglePin(item.id) }
            act("square.and.arrow.down", "保存到本地") { _ = ClipStore.shared.export(item) }
            act("trash", "删除") { ClipStore.shared.remove(item.id) }
        }
        .padding(4)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .padding(.top, 30).padding(.trailing, 6)
    }

    private func act(_ symbol: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).frame(width: 22, height: 20)
        }
        .buttonStyle(.plain).help(tip)
    }

    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
