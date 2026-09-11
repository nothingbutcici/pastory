import SwiftUI

/// One shelf card. Quiet surface, thin tinted top edge per kind, content fills the card,
/// actions live in the footer (no hover tricks). Tapping the card copies.
struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    let onCopy: () -> Void

    static let width: CGFloat = 240
    private static let accent = Color(nsColor: AnnotatePalette.accent)

    private var tint: Color {
        switch item.kind {
        case .text: return Color(nsColor: NSColor(srgbRed: 0.55, green: 0.58, blue: 0.66, alpha: 1))
        case .url: return Color(nsColor: NSColor(srgbRed: 0.16, green: 0.52, blue: 0.94, alpha: 1))
        case .image: return Self.accent
        case .video: return Color(nsColor: NSColor(srgbRed: 0.86, green: 0.26, blue: 0.40, alpha: 1))
        case .files: return Color(nsColor: NSColor(srgbRed: 0.95, green: 0.60, blue: 0.15, alpha: 1))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(tint).frame(height: 3)
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Self.accent : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(selected ? 0.16 : 0.08), radius: selected ? 12 : 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 1, perform: onCopy)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
            Text(item.sourceAppName ?? item.kind.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Self.accent) }
            Text(item.createdAt, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image, .video:
            if let img = ClipStore.shared.thumbnail(of: item) {
                // Whole picture, width-fitted, top-aligned: a wide screenshot stays recognisable.
                VStack(spacing: 0) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .overlay(alignment: .bottomLeading) {
                            if item.kind == .video {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.system(size: 9))
                                    Text(item.ext.uppercased()).font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(6)
                            }
                        }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo").font(.largeTitle).foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.snippet.split(separator: "\n").prefix(8), id: \.self) { line in
                    HStack(spacing: 7) {
                        Image(systemName: "doc.fill").font(.system(size: 11)).foregroundStyle(tint.opacity(0.8))
                        Text(line).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                if let host = URL(string: item.snippet)?.host {
                    Text(host).font(.system(size: 13, weight: .semibold))
                }
                Text(item.snippet).font(.system(size: 12)).foregroundStyle(tint).lineLimit(6)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        case .text:
            Text(item.snippet)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .lineLimit(13)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12).padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(tint)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())
                .lineLimit(1)
            Spacer(minLength: 6)
            action(item.pinned ? "pin.fill" : "pin", item.pinned ? "取消固定" : "固定，不会被自动清理", active: item.pinned) {
                ClipStore.shared.togglePin(item.id)
            }
            action("square.and.arrow.down", "保存到本地…") { Exporter.export(item) }
            action("trash", "删除") { ClipStore.shared.remove(item.id) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035))
    }

    private var footerText: String {
        switch item.kind {
        case .image: return "图片 \(item.snippet)"
        case .video: return item.snippet
        case .text: return "文本 · \(item.byteCount) 字节"
        case .url: return "链接"
        case .files: return "文件 · \(item.snippet.split(separator: "\n").count) 项"
        }
    }

    private func action(_ symbol: String, _ tip: String, active: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Self.accent : Color.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
