import SwiftUI

extension Color {
    static let lime = Color(nsColor: Theme.lime)
    static let limeSoft = Color(nsColor: Theme.limeSoft)
    static let shelfBG = Color(nsColor: Theme.shelfBG)
    static let shelfSide = Color(nsColor: Theme.shelfSide)
    static let shelfInk = Color(nsColor: Theme.shelfInk)
    static let shelfMuted = Color(nsColor: Theme.shelfMuted)
    static let shelfBorder = Color(nsColor: Theme.shelfBorder)
}

struct ShelfView: View {
    @Bindable var model: ShelfModel
    @FocusState private var searchFocused: Bool
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollVisible: CGFloat = 1

    var body: some View {
        let items = model.items
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                if items.isEmpty { empty } else { cards(items) }
                footer
            }
            .padding(.horizontal, 24)
        }
        .background(Color.shelfBG)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                if let logo = Theme.logo { Image(nsImage: logo).resizable().scaledToFit().frame(width: 72, height: 72) }
                Text("Snip Clip").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.shelfInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
            .padding(.bottom, 34)
            Text("剪贴板").font(.system(size: 13)).foregroundStyle(Color.shelfMuted)
            Text("今日暂存").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.shelfInk).padding(.top, 2)
            Text("未 Pin 内容\n\(retentionText)").font(.system(size: 13)).foregroundStyle(Color.shelfMuted).lineSpacing(3).padding(.top, 14)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(Color.shelfInk)
                Text("Pin 后一直保留").font(.system(size: 13)).foregroundStyle(Color.shelfMuted)
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 26)
        .frame(width: 200, alignment: .leading)
        .background(Color.shelfSide)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(0.05)).frame(width: 1) }
    }

    private var retentionText: String {
        let d = Preferences.shared.retentionDays
        return d <= 1 ? "次日 04:00 清理" : "\(d) 天后 04:00 清理"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ForEach(ShelfFilter.allCases) { f in
                let on = model.filter == f
                Button { model.filter = f } label: {
                    Text(f.rawValue)
                        .font(.system(size: 14, weight: on ? .semibold : .medium))
                        .foregroundStyle(Color.shelfInk)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(on ? Color.lime : Color.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : Color.shelfBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.shelfMuted)
                TextField("搜索剪贴板", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Color.shelfInk).focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.shelfMuted) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shelfBorder, lineWidth: 1))
            .frame(width: 350)
            Button { SettingsWindowController.shared.show() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 16))
                    Text("设置").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.shelfInk).padding(.horizontal, 6).frame(height: 36)
            }
            .buttonStyle(.plain).help("设置")
            Button { ShelfPanelController.shared.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.shelfInk).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).help("关闭 ⎋")
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: Cards

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        ClipCardView(item: item, selected: item.id == model.selectedID, onClipboard: item.id == ClipStore.shared.items.first?.id,
                                     onCopy: { model.selectedID = item.id; model.copy(item) })
                            .id(item.id)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
            .onScrollGeometryChange(for: CGPoint.self, of: { g in
                let w = max(1, g.contentSize.width - g.containerSize.width)
                return CGPoint(x: min(1, max(0, g.contentOffset.x / w)), y: min(1, g.containerSize.width / max(1, g.contentSize.width)))
            }, action: { _, v in scrollFraction = v.x; scrollVisible = v.y })
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Color.shelfMuted.opacity(0.6))
            Text(model.query.isEmpty
                 ? "还没有内容。复制点什么，或者按 \(Preferences.shared.shortcut(Preferences.Key.hotkeyCapture).display) 截个图。"
                 : "没有匹配的内容")
                .font(.system(size: 14)).foregroundStyle(Color.shelfMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button { model.move(-3) } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.shelfMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06))
                    Capsule().fill(Color.black.opacity(0.18))
                        .frame(width: max(40, geo.size.width * scrollVisible))
                        .offset(x: (geo.size.width - max(40, geo.size.width * scrollVisible)) * scrollFraction)
                }
            }
            .frame(height: 6)
            Button { model.move(3) } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.shelfMuted)
            Text("点按复制 · 空格预览").font(.system(size: 13)).foregroundStyle(Color.shelfMuted).padding(.leading, 12)
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制") { model.copy(item) }
        Button("预览（空格）") { model.selectedID = item.id; ShelfPanelController.shared.toggleQuickLook() }
        Button(item.pinned ? "取消 Pin" : "Pin") { ClipStore.shared.togglePin(item.id) }
        Button("保存到本地…") { Exporter.export(item) }
        if item.kind == .files {
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(ClipStore.shared.fileURLs(of: item)) }
        }
        if item.kind == .video {
            Button("打开") { NSWorkspace.shared.open(ClipStore.shared.payloadURL(item)) }
        }
        if item.kind == .image, let t = item.ocrText, !t.isEmpty {
            Button("复制识别出的文字") {
                let it = ClipStore.shared.insertText(t, rtf: nil, source: CaptureCoordinator.source)
                PasteboardWriter.writeText(t, rtf: nil, itemID: it?.id ?? "")
                ShelfPanelController.shared.hide()
            }
        }
        Divider()
        Button("删除", role: .destructive) { ClipStore.shared.remove(item.id) }
    }
}
