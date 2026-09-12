import SwiftUI

/// A paper ticket: header rule, handwritten title, serif body, perforation with side notches, then the stubs.
/// The card that is currently on the pasteboard is the blue one.
struct ClipCardView: View {
    let item: ClipItem
    let selected: Bool
    let onClipboard: Bool
    /// Position in the row: clips and sheet colours alternate strictly, one card yes, next card no.
    var index: Int = 0
    @Binding var renaming: Bool
    let onCopy: () -> Void
    let onCopyAndClose: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void

    static let width: CGFloat = 288
    private static let stubHeight: CGFloat = 96      // caption row + action row below the perforation
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    private var paperPaint: ImagePaint { onClipboard ? Paint.paperBlue : Paint.paper }
    private var ticket: TicketShape { TicketShape(notchFromBottom: index % 2 == 0 ? Self.stubHeight : nil) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if renaming || selected || (item.title?.isEmpty == false) { titleRow }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: (item.kind == .image || item.kind == .video) && (item.title ?? "").isEmpty ? .center : .topLeading)
                .clipped()
            perforation
            captionRow
            actions
        }
        .frame(width: Self.width)
        .clipShape(ticket)
        // The sheet casts the shadow; shadowing the whole subtree (text, thumbnails) re-rasterised every card on every change.
        .background(ticket.fill(paperPaint).shadow(color: .black.opacity(selected ? 0.55 : 0.4), radius: selected ? 14 : 9, x: 2, y: selected ? 9 : 6))
        .overlay(alignment: .top) { decoration }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onCopyAndClose)
        .onTapGesture(count: 1, perform: onCopy)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if let icon = Theme.cardIcon(bundleID: item.sourceBundleID) { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "doc.on.clipboard").font(.system(size: 13)) }
                }
                .frame(width: 22, height: 22)
                Text(item.sourceAppName ?? item.kind.label).font(.serif(16)).foregroundStyle(Color.ink).lineLimit(1)
                Spacer()
                Text(item.createdAt, style: .time).font(.serif(14)).foregroundStyle(Color.ink.opacity(0.75))
            }
            .padding(.horizontal, 18).padding(.top, hasPin ? 34 : 14).padding(.bottom, 8)
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
                        .onSubmit { renaming = false }
                }
                Button { renaming = false } label: {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain).help("保存 ⏎")
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) }
            .onAppear { draftTitle = item.title ?? ""; titleFocused = true }
            .onChange(of: titleFocused) { _, f in if !f, renaming { renaming = false } }
            // Leaving the box, by any route, is the save. An unchanged draft writes nothing.
            .onDisappear {
                let t = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if t != (item.title ?? "") { ClipStore.shared.setTitle(t, for: item.id) }
            }
        } else if let t = item.title, !t.isEmpty {
            Text(t).font(.script(30)).foregroundStyle(Color.ink).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) }
                .contentShape(Rectangle())
                .onTapGesture { renaming = true }
                .help("点击重命名")
        } else {
            HStack(spacing: 0) {
                if selected { Text("+ add title").font(.script(26)).foregroundStyle(Color.inkMuted.opacity(0.8)) }
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 2)
            .overlay(alignment: .bottom) { if selected { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) } }
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
                        .padding(.horizontal, 16).padding(.vertical, 14)
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
            pinAction
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

    /// Pinned = a small torn patch behind the pin: cream patch with a blue pin on the blue card,
    /// blue patch with a cream pin on cream cards.
    private var pinAction: some View {
        Button { ClipStore.shared.togglePin(item.id) } label: {
            Image(systemName: item.pinned ? "pin.fill" : "pin")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(item.pinned ? (onClipboard ? Color.paperBlueDeep : Color.paper) : Color.ink)
                .frame(width: 34, height: 30)
                .background {
                    if item.pinned {
                        TornPaper(top: true, right: true, bottom: true, left: true, seed: 77, amplitude: 1.5, step: 5)
                            .fill(onClipboard ? Paint.paper : Paint.paperBlue)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.pinned ? "取消 Pin" : "Pin 住，不会被自动清理")
    }

    private func action(_ symbol: String, _ tip: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: Stationery

    /// Only the copied card wears the pink pushpin, pushed through its top margin.
    private var hasPin: Bool { onClipboard }

    @ViewBuilder
    private var decoration: some View {
        if hasPin, let img = Theme.pushpin {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(height: 44)
                .shadow(color: .black.opacity(0.28), radius: 2, x: 1, y: 2)      // tight contact shadow, not a blur cloud
                .offset(x: 0, y: -6)
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
}

/// Rounded rectangle with a half-circle notch cut into each side, `notchFromBottom` up from the bottom edge
/// (odd cards are punched, even cards are plain).
struct TicketShape: Shape {
    var notchFromBottom: CGFloat?
    var radius: CGFloat = 5
    var notch: CGFloat = 11
    func path(in r: CGRect) -> Path {
        let y: CGFloat? = notchFromBottom.map { r.maxY - $0 }
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        if let y {
            p.addLine(to: CGPoint(x: r.maxX, y: y - notch))
            p.addArc(center: CGPoint(x: r.maxX, y: y), radius: notch, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        if let y {
            p.addLine(to: CGPoint(x: r.minX, y: y + notch))
            p.addArc(center: CGPoint(x: r.minX, y: y), radius: notch, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct Line: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

