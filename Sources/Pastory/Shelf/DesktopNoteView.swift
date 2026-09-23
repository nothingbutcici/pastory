import SwiftUI

/// The card as a sticky note: same paper, full content, two actions (edit, close). Single click copies,
/// double-click pastes into the app in front. Width matches the shelf card; height follows the content.
struct DesktopNoteView: View {
    let itemID: String
    var geometry = NoteGeometry()
    /// Measuring pass: natural size for the content, used once to pick the window's first size.
    var measuring = false
    static let width: CGFloat = 288
    static let margin: CGFloat = 14          // shadow and pushpin live in this band around the paper
    private static let side: CGFloat = 18
    @State private var copiedTick = 0
    @State private var showCopied = false
    @State private var layerTick = 0
    @State private var noteText = ""

    private var item: ClipItem? { ClipStore.shared.items.first { $0.id == itemID } }

    var body: some View {
        if let item {
            let _ = layerTick
            VStack(spacing: 0) {
                header(item)
                if let t = item.title, !t.isEmpty {
                    Text(t).font(.script(20)).foregroundStyle(Color.ink).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Self.side).padding(.top, 6).padding(.bottom, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, Self.side) }
                }
                content(item)
                perforation
                HStack(spacing: 8) {
                    Text(kindLabel(item)).font(.serif(13)).foregroundStyle(Color.inkMuted).lineLimit(1)
                    Spacer(minLength: 0)
                    if showCopied {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            Text("已复制".l).font(.serif(13))
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Color.ink.opacity(0.8), lineWidth: 1))
                        .transition(.opacity)
                    }
                    if item.kind == .text || item.kind == .url || item.kind == .image {
                        action("pencil", "编辑".l) { edit(item) }
                    }
                    if !measuring {
                        let top = DesktopNotes.shared.isOnTop(itemID)
                        action(top ? "square.3.layers.3d.top.filled" : "square.3.layers.3d.bottom.filled",
                               top ? "浮于窗口上（点击改为仅桌面显示）".l : "仅桌面显示（点击改为浮于窗口上）".l) {
                            DesktopNotes.shared.setOnTop(itemID, !top); layerTick += 1
                        }
                    }
                    action("xmark", "从桌面关闭".l) { DesktopNotes.shared.close(itemID) }
                }
                .padding(.leading, Self.side).padding(.trailing, 8)
                .frame(height: 40)
            }
            .frame(width: measuring ? Self.width : geometry.size.width)
            .frame(height: measuring ? nil : geometry.size.height, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 1, y: 3)
            )
            .overlay(alignment: .top) {
                if let img = Theme.pushpin {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(height: 40)
                        .shadow(color: .black.opacity(0.28), radius: 2, x: 1, y: 2).offset(y: -6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !measuring {
                    // Resize grip: three short diagonal strokes in the corner.
                    Path { p in
                        for k in stride(from: 4.0, through: 12.0, by: 4.0) { p.move(to: CGPoint(x: 16 - k, y: 16)); p.addLine(to: CGPoint(x: 16, y: 16 - k)) }
                    }
                    .stroke(Color.ink.opacity(0.35), lineWidth: 1)
                    .frame(width: 16, height: 16)
                    .padding(6)
                }
            }
            .padding(Self.margin)
            .contentShape(Rectangle())
            .onTapGesture { (NSApp.currentEvent?.clickCount ?? 1) >= 2 ? paste(item) : copy(item) }
            .contextMenu {
                if item.kind == .text || item.kind == .url || item.kind == .image { Button("编辑".l) { edit(item) } }
                Button("保存到本地…".l) { Exporter.export(item) }
                Button(DesktopNotes.shared.isOnTop(itemID) ? "改为仅桌面显示".l : "改为浮于窗口上".l) { DesktopNotes.shared.setOnTop(itemID, !DesktopNotes.shared.isOnTop(itemID)); layerTick += 1 }
                Divider()
                Button("从桌面关闭".l) { DesktopNotes.shared.close(itemID) }
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    // MARK: Pieces

    private func header(_ item: ClipItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if let icon = Theme.cardIcon(bundleID: item.sourceBundleID) { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "doc.on.clipboard").font(.system(size: 13)) }
                }
                .frame(width: 20, height: 20)
                Text(item.sourceAppName ?? "Pastory").font(.serif(15)).foregroundStyle(Color.ink).lineLimit(1)
                Spacer()
                Text(ClipCardView.when(item.createdAt)).font(.serif(13)).foregroundStyle(Color.ink.opacity(0.7))
            }
            .padding(.horizontal, Self.side).padding(.top, 26).padding(.bottom, 8)
            Rectangle().fill(Color.ink.opacity(0.7)).frame(height: 1).padding(.horizontal, Self.side)
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            // The measuring probe needs the text right now; a live note loads it once per content change instead of
            // re-reading the payload from disk every time the store changes.
            let text = measuring ? (ClipStore.shared.text(of: item) ?? item.snippet) : noteText
            ScrollView(.vertical, showsIndicators: true) {
                Text(text).font(.serif(14)).foregroundStyle(Color.ink).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: measuring ? Self.naturalHeight(of: text) : nil)
            .task(id: item.contentHash) { if !measuring { noteText = ClipStore.shared.text(of: item) ?? item.snippet } }
            .frame(maxHeight: measuring ? nil : .infinity)
            .padding(.horizontal, Self.side).padding(.vertical, 12)
        case .url:
            VStack(alignment: .leading, spacing: 6) {
                if let host = URL(string: item.snippet)?.host { Text(host).font(.serif(15, bold: true)).foregroundStyle(Color.ink) }
                Text(item.snippet).font(.serif(13)).foregroundStyle(Color.paperBlueDeep).lineLimit(8).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.side).padding(.vertical, 12)
            .frame(maxHeight: measuring ? nil : .infinity, alignment: .top)
        case .files:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.snippet.split(separator: "\n").prefix(12), id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(Color.inkMuted)
                        Text(line).font(.serif(14)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.side).padding(.vertical, 12)
            .frame(maxHeight: measuring ? nil : .infinity, alignment: .top)
        case .image, .video:
            Group {
                if let img = ClipStore.shared.thumbnail(of: item) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(6).background(Color.white)
                        .overlay {
                            if item.kind == .video {
                                ZStack {
                                    Circle().fill(.black.opacity(0.5)).frame(width: 44, height: 44)
                                    Image(systemName: "play.fill").font(.system(size: 16)).foregroundStyle(.white).offset(x: 2)
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 1, y: 3)
                } else {
                    Image(systemName: item.kind == .video ? "film" : "photo").font(.largeTitle).foregroundStyle(Color.inkMuted.opacity(0.5))
                        .frame(height: 120)
                }
            }
            .padding(.horizontal, Self.side).padding(.vertical, 14)
            .frame(maxHeight: measuring ? nil : .infinity, alignment: .top)
        }
    }

    private var perforation: some View {
        Line().stroke(Color.ink.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(height: 1).padding(.horizontal, Self.side)
    }

    private func action(_ symbol: String, _ tip: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular)).foregroundStyle(Color.ink)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(tip)
    }

    /// Height of the whole text at note width, capped so a long note never exceeds 60% of the screen.
    private static func naturalHeight(of text: String) -> CGFloat {
        let inner = Self.width - Self.side * 2
        let cap = (NSScreen.main?.visibleFrame.height ?? 900) * 0.6
        let h = ceil((text as NSString).boundingRect(with: CGSize(width: inner, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: Theme.serif(size: 14), .paragraphStyle: paragraph]).height) + 2
        return min(h, cap)
    }
    private static let paragraph: NSParagraphStyle = { let p = NSMutableParagraphStyle(); p.lineSpacing = 5; return p }()

    private func kindLabel(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: return "图片".l + " · " + item.snippet.replacingOccurrences(of: "×", with: " × ")
        case .text: return "文本".l
        case .url: return "链接".l
        case .files: return "文件".l
        case .video: return item.ext.uppercased()
        }
    }

    // MARK: Actions

    private func copy(_ item: ClipItem) {
        ClipStore.shared.copyToPasteboard(item)
        copiedTick += 1
        let tick = copiedTick
        withAnimation(.easeOut(duration: 0.12)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copiedTick == tick { withAnimation { showCopied = false } } }
    }

    /// Double-click: copy, then ⌘V into the app in front (the note never took focus from it).
    private func paste(_ item: ClipItem) {
        copy(item)
        guard Preferences.shared.pasteOnDoubleClick, Permissions.hasAccessibility else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Permissions.sendPaste() }
    }

    private func edit(_ item: ClipItem) {
        switch item.kind {
        case .text, .url: TextEditorWindow.open(item)
        case .image: ImageEditorWindow.open(item)
        default: break
        }
    }
}
