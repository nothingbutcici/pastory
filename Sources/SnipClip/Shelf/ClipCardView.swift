import SwiftUI

/// A paper ticket: header rule, handwritten title, serif body, perforation with side notches, then the stubs.
/// The card that is currently on the pasteboard is the blue one.
struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    let onClipboard: Bool
    @Binding var renaming: Bool
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void

    static let width: CGFloat = 288
    private static let stubHeight: CGFloat = 96      // caption row + action row below the perforation
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    private var paperColor: Color { onClipboard ? .paperBlue : .paper }

    var body: some View {
        VStack(spacing: 0) {
            header
            titleRow
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            perforation
            captionRow
            actions
        }
        .frame(width: Self.width)
        .background(ZStack { paperColor; Grain(opacity: 0.11) })
        .clipShape(TicketShape(notchFromBottom: Self.stubHeight))
        .shadow(color: .black.opacity(selected ? 0.55 : 0.4), radius: selected ? 14 : 9, x: 2, y: selected ? 9 : 6)
        // A whiter sheet behind, a hair larger and barely turned, peeking out along the top edge only.
        .background {
            let seed = stableSeed
            let tilt = Double(seed % 3) - 1.0                       // -1, 0, 1 degree
            ZStack { Color.white.opacity(0.85); Grain(opacity: 0.08) }
                .padding(.horizontal, -3).padding(.top, -6).padding(.bottom, -2)
                .rotationEffect(.degrees(tilt == 0 ? 0.6 : tilt), anchor: .bottom)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
        }
        .overlay(alignment: .topTrailing) { decoration }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onCopyAndClose)
        .onTapGesture(count: 1, perform: onCopy)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if let icon = appIcon { Image(nsImage: icon).resizable().saturation(0).contrast(1.2) }
                    else { Image(systemName: "doc.on.clipboard").font(.system(size: 13)) }
                }
                .frame(width: 22, height: 22)
                Text(item.sourceAppName ?? item.kind.label).font(.serif(16)).foregroundStyle(Color.ink).lineLimit(1)
                Spacer()
                Text(item.createdAt, style: .time).font(.serif(14)).foregroundStyle(Color.ink.opacity(0.75))
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
            Rectangle().fill(Color.ink.opacity(0.7)).frame(height: 1).padding(.horizontal, 18)
        }
    }

    // MARK: Title (handwritten) — click to rename; entry only on the selected card

    @ViewBuilder
    private var titleRow: some View {
        if renaming {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if draftTitle.isEmpty && !titleFocused {
                        Text("输入标题").font(.script(26)).foregroundColor(Color.inkMuted).allowsHitTesting(false)
                    }
                    TextField("", text: $draftTitle)
                        .textFieldStyle(.plain).font(.script(26))
                        .foregroundColor(Color.ink).tint(Color.ink)
                        .focused($titleFocused)
                        .onSubmit { ClipStore.shared.setTitle(draftTitle, for: item.id); renaming = false }
                }
                Button { ClipStore.shared.setTitle(draftTitle, for: item.id); renaming = false } label: {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain).help("保存 ⏎")
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) }
            .onAppear { draftTitle = item.title ?? ""; titleFocused = true }
            .onChange(of: titleFocused) { _, f in if !f, renaming { renaming = false } }
        } else if let t = item.title, !t.isEmpty {
            Text(t).font(.script(30)).foregroundStyle(Color.ink).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) }
                .contentShape(Rectangle())
                .onTapGesture { renaming = true }
                .help("点击重命名")
        } else {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("起个标题").font(.serif(13))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            .foregroundStyle(Color.inkMuted)
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 2)
            .contentShape(Rectangle())
            .onTapGesture { if selected { renaming = true } else { onCopy() } }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image, .video:
            if let img = ClipStore.shared.thumbnail(of: item) {
                VStack(spacing: 0) {
                    // Photo print: white border, a little tilt, soft shadow.
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(7)
                        .background(Color.white)
                        .overlay {
                            if item.kind == .video {
                                ZStack {
                                    Circle().fill(.black.opacity(0.5)).frame(width: 48, height: 48)
                                    Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).offset(x: 2)
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 1, y: 4)
                        .rotationEffect(.degrees(-1.6))
                        .padding(.horizontal, 16).padding(.top, 14)
                    Spacer(minLength: 0)
                }
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo").font(.largeTitle).foregroundStyle(Color.inkMuted.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.snippet.split(separator: "\n").prefix(8), id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(Color.inkMuted)
                        Text(line).font(.serif(15)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 14)
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                if let host = URL(string: item.snippet)?.host { Text(host).font(.serif(16, bold: true)).foregroundStyle(Color.ink) }
                Text(item.snippet).font(.serif(14)).foregroundStyle(Color.paperBlueDeep).lineLimit(6)
            }
            .padding(.horizontal, 18).padding(.top, 14)
        case .text:
            Text(item.snippet)
                .font(.serif(15))
                .foregroundStyle(Color.ink)
                .lineSpacing(6)
                .lineLimit(9)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 18).padding(.top, 14)
        }
    }

    // MARK: Perforation + stubs

    private var perforation: some View {
        Line().stroke(Color.ink.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private var captionRow: some View {
        HStack(spacing: 8) {
            Text(note.map { "\(kindLabel) · \($0)" } ?? kindLabel).font(.serif(14)).foregroundStyle(Color.ink).lineLimit(1)
            Spacer(minLength: 0)
            if onClipboard {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    Text("已复制").font(.serif(13))
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(Capsule().stroke(Color.ink.opacity(0.8), lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.7)).frame(height: 1).padding(.horizontal, 18) }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if item.kind == .text || item.kind == .url || item.kind == .image {
                action("pencil", item.kind == .image ? "编辑标注" : "编辑文字", onEdit)
            } else {
                action("eye", "预览", onPreview)
            }
            divider
            action(item.pinned ? "pin.fill" : "pin", "Pin 住，不会被自动清理", active: item.pinned) { ClipStore.shared.togglePin(item.id) }
            if item.kind == .image || item.kind == .video {
                divider
                action("arrow.down.to.line", "保存到本地…") { Exporter.export(item) }
            }
            divider
            action("trash", "删除") { ClipStore.shared.remove(item.id) }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.stubHeight - 44)
    }

    private var divider: some View { Rectangle().fill(Color.ink.opacity(0.35)).frame(width: 1, height: 22) }

    private func action(_ symbol: String, _ tip: String, active: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(active ? Color.ink.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: Stationery

    private var stableSeed: UInt64 { UInt64(truncatingIfNeeded: stableHash(Data(item.id.utf8))) }

    /// Photo cards get a binder clip; text cards take turns between a paper clip, a strip of tape, or nothing.
    @ViewBuilder
    private var decoration: some View {
        if item.kind == .image || item.kind == .video {
            BinderClip().frame(width: 34, height: 30)
                .offset(x: -(Self.width / 2 - 17), y: 70)
        } else {
            switch stableSeed % 3 {
            case 0: PaperClip().frame(width: 22, height: 62).rotationEffect(.degrees(-8)).offset(x: -18, y: 58)
            case 1: TapeStrip().frame(width: 74, height: 20).rotationEffect(.degrees(-4)).offset(x: -Self.width / 2 + 37, y: -7)
            default: EmptyView()
            }
        }
    }

    // MARK: Text bits

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
    private var charCount: Int { item.snippet.count >= 400 ? item.byteCount / 3 : item.snippet.count }
    private var durationText: String {
        let s = Int((item.duration ?? 0).rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    private var appIcon: NSImage? {
        if item.sourceBundleID == "com.cici.snipclip" { return Theme.logo }
        guard let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Rounded rectangle with a half-circle notch cut into each side, `notchFromBottom` up from the bottom edge.
struct TicketShape: Shape {
    var notchFromBottom: CGFloat
    var radius: CGFloat = 5
    var notch: CGFloat = 11
    func path(in r: CGRect) -> Path {
        let y = r.maxY - notchFromBottom
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: y - notch))
        p.addArc(center: CGPoint(x: r.maxX, y: y), radius: notch, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: y + notch))
        p.addArc(center: CGPoint(x: r.minX, y: y), radius: notch, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct Line: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

/// Two nested loops of grey wire.
struct PaperClip: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let outer = Path { p in
                p.move(to: CGPoint(x: w * 0.2, y: h * 0.42))
                p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.12))
                p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.12), radius: w * 0.3, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.82))
                p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.82), radius: w * 0.3, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.42))
                p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.42), radius: w * 0.3, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.7))
            }
            var shadow = ctx
            shadow.translateBy(x: 1, y: 2)
            shadow.stroke(outer, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.stroke(outer, with: .color(Color(red: 0.62, green: 0.63, blue: 0.66)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.stroke(outer, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Black spring clip with two wire handles, as on the photo in the reference.
struct BinderClip: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let body = Path { p in
                p.move(to: CGPoint(x: w * 0.1, y: h * 0.55)); p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.98)); p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.98)); p.closeSubpath()
            }
            var shadow = ctx; shadow.translateBy(x: 1, y: 2)
            shadow.fill(body, with: .color(.black.opacity(0.3)))
            ctx.fill(body, with: .color(Color(red: 0.13, green: 0.12, blue: 0.12)))
            ctx.fill(Path(CGRect(x: w * 0.1, y: h * 0.5, width: w * 0.8, height: h * 0.12)), with: .color(Color(red: 0.32, green: 0.31, blue: 0.31)))
            let handle = Path { p in
                p.move(to: CGPoint(x: w * 0.32, y: h * 0.55)); p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.08))
                p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.08), radius: w * 0.28, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.55))
            }
            ctx.stroke(handle, with: .color(Color(red: 0.6, green: 0.61, blue: 0.64)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// A strip of translucent tape.
struct TapeStrip: View {
    var body: some View {
        TornPaper(right: true, left: true, seed: 3, amplitude: 1.2, step: 4)
            .fill(Color(red: 0.96, green: 0.94, blue: 0.86).opacity(0.55))
            .overlay(Grain(opacity: 0.25))
            .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            .allowsHitTesting(false)
    }
}
