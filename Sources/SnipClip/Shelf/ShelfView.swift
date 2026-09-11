import SwiftUI

extension Color {
    static let lime = Color(nsColor: Theme.lime)
    static let shelfBG = Color(nsColor: Theme.shelfBG)
    static let shelfSide = Color(nsColor: Theme.shelfSide)
    static let shelfCard = Color(nsColor: Theme.shelfCard)
    static let shelfInk = Color(nsColor: Theme.shelfInk)
    static let shelfMuted = Color(nsColor: Theme.shelfMuted)
    static let shelfBorder = Color(nsColor: Theme.shelfBorder)
    static let cream = Color(nsColor: Theme.cream)
    static let creamInk = Color(nsColor: Theme.creamInk)
    static let purple = Color(nsColor: Theme.purple)
    static let onPurple = Color(nsColor: Theme.onPurple)
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
            if model.showSettings {
                SettingsPane(model: model).padding(.horizontal, 24)
            } else {
                VStack(spacing: 0) {
                    header
                    if items.isEmpty { empty } else { cards(items) }
                    footer
                }
                .padding(.horizontal, 24)
            }
        }
        .background(ZStack { Color.shelfBG; GridPattern() })
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Everything in the sidebar hangs off the same left edge.
            VStack(alignment: .leading, spacing: 10) {
                if let logo = Theme.logo { Image(nsImage: logo).resizable().scaledToFit().frame(width: 64, height: 64) }
                Text("Snip Clip").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.shelfInk)
            }
            .padding(.top, 26)
            .padding(.bottom, 38)
            Text("今日暂存").font(.system(size: 27, weight: .bold)).foregroundStyle(Color.shelfInk)
            Text("未 Pin 内容\n\(retentionText)").font(.system(size: 13.5)).foregroundStyle(Color.shelfMuted).lineSpacing(4).padding(.top, 14)
            Spacer()
            if let m = Theme.mascot {
                Image(nsImage: m).resizable().scaledToFit().frame(width: 64, height: 64)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 14)
            }
            sideRow(icon: "pin.fill", tint: Color.lime, "Pin 后一直保留", active: false) { model.showSettings = false }
            sideRow(icon: "gearshape", tint: Color.shelfInk, "设置", active: model.showSettings) { model.showSettings.toggle() }
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
        .frame(width: 210, alignment: .leading)
        .background(ZStack { Color.shelfSide; GridPattern() })
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }

    private func sideRow(icon: String, tint: Color, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(active ? Color(nsColor: Theme.onLime) : tint)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(active ? Color(nsColor: Theme.onLime) : Color.shelfInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(active ? Color.lime : Color.shelfCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.clear : Color.shelfBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
                        .font(.system(size: 14.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Color(nsColor: Theme.onLime) : Color.shelfInk)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(on ? Color.lime : Color.shelfCard, in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : Color.shelfBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.shelfMuted)
                ZStack(alignment: .leading) {
                    // macOS ignores prompt colours on a plain TextField; draw the placeholder ourselves.
                    if model.query.isEmpty {
                        Text("搜索剪贴板").font(.system(size: 14)).foregroundColor(Color.shelfMuted).allowsHitTesting(false)
                    }
                    TextField("", text: $model.query)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .foregroundColor(Color.shelfInk).tint(Color.purple)
                        .focused($searchFocused)
                }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.shelfMuted) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.shelfCard, in: Capsule())
            .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
            .frame(width: 350)
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
                                     onCopy: { model.copy(item) },
                                     onCopyAndClose: { model.copyAndClose(item) },
                                     onPreview: { model.selectedID = item.id; model.previewSelected() },
                                     onEdit: { model.selectedID = item.id; model.edit(item) })
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
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(Color.white.opacity(0.28))
                        .frame(width: max(40, geo.size.width * scrollVisible))
                        .offset(x: (geo.size.width - max(40, geo.size.width * scrollVisible)) * scrollFraction)
                }
            }
            .frame(height: 6)
            Button { model.move(3) } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.shelfMuted)
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制") { model.copy(item) }
        Button("复制并关闭") { model.copyAndClose(item) }
        if item.kind == .text || item.kind == .url || item.kind == .image {
            Button("编辑") { model.selectedID = item.id; model.edit(item) }
        }
        Button("预览") { model.selectedID = item.id; model.previewSelected() }
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

/// Faint square grid over the dark ground, like graph paper.
struct GridPattern: View {
    var step: CGFloat = 28
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Color(nsColor: Theme.shelfGrid)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
