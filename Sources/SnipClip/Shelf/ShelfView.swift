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
    @State private var scrollRange: CGFloat = 0      // content width minus container width
    @State private var scrollPos = ScrollPosition(edge: .leading)

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

    // MARK: Sidebar — brand row, nav (剪贴板 / 设置), mascot + pin note

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let logo = Theme.logo { Image(nsImage: logo).resizable().scaledToFit().frame(width: 56, height: 56) }
                Text("Snip Clip").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.shelfInk)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 26)
            navRow(icon: "clipboard", "剪贴板", active: !model.showSettings) { model.showSettings = false }
            navRow(icon: "gearshape", "设置", active: model.showSettings) { model.showSettings = true }
            Spacer()
            // 今日暂存: the two rules that matter, under the mascot.
            VStack(alignment: .leading, spacing: 10) {
                if let m = Theme.mascot { Image(nsImage: m).resizable().scaledToFit().frame(width: 44, height: 44) }
                Text("今日暂存").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.shelfInk).padding(.top, 2)
                rule(icon: "pin.fill", tint: Color(nsColor: Theme.yellow), "Pin 后一直保留")
                rule(icon: "clock", tint: Color(nsColor: Theme.yellow), retentionShort)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 214, alignment: .leading)
        .background(ZStack { Color.shelfSide; GridPattern() })
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }

    /// Active: purple bar on the left edge + tinted pill that is flush left and rounded on the right.
    private func navRow(icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 16, weight: active ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.shelfInk)
            .padding(.leading, 22)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                if active {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.purple).frame(width: 3)
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 27, topTrailingRadius: 27)
                            .fill(Color.purple.opacity(0.22))
                    }
                    .padding(.trailing, 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var retentionShort: String {
        let d = Preferences.shared.retentionDays
        return d <= 1 ? "未 Pin 次日 04:00 清理" : "未 Pin \(d) 天后清理"
    }

    private func rule(icon: String, tint: Color, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
            Text(text).font(.system(size: 13)).foregroundStyle(Color.shelfInk).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    // MARK: Header — filter pills, search, close on one row

    private var header: some View {
        HStack(spacing: 10) {
            ForEach(ShelfFilter.allCases) { f in
                let on = model.filter == f
                Button { model.filter = f } label: {
                    HStack(spacing: 6) {
                        Text(f.rawValue).font(.system(size: 14.5, weight: on ? .semibold : .medium))
                        Text("\(model.count(for: f))")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(on ? Color.onPurple.opacity(0.7) : Color.shelfMuted)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((on ? Color.black.opacity(0.12) : Color.white.opacity(0.07)), in: Capsule())
                    }
                    .foregroundStyle(on ? Color.onPurple : Color.shelfInk)
                    .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 8)
                    .background(on ? Color.purple : Color.shelfCard, in: Capsule())
                    .overlay(Capsule().stroke(on ? Color.clear : Color.shelfBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.shelfMuted)
                ZStack(alignment: .leading) {
                    if model.query.isEmpty && !searchFocused {
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
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.shelfCard, in: Capsule())
            .overlay(Capsule().stroke(Color.shelfBorder, lineWidth: 1))
            .frame(width: 300)
            Button { ShelfPanelController.shared.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.shelfInk).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).help("关闭 ⎋")
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
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
            .scrollPosition($scrollPos)
            .onScrollGeometryChange(for: [CGFloat].self, of: { g in
                let w = max(0, g.contentSize.width - g.containerSize.width)
                return [min(1, max(0, g.contentOffset.x / max(1, w))), min(1, g.containerSize.width / max(1, g.contentSize.width)), w]
            }, action: { _, v in scrollFraction = v[0]; scrollVisible = v[1]; scrollRange = v[2] })
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
                let thumb = max(40, geo.size.width * scrollVisible)
                let travel = geo.size.width - thumb
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(Color.white.opacity(0.28))
                        .frame(width: thumb)
                        .offset(x: travel * scrollFraction)
                }
                .frame(height: 14)               // fatter hit area than the 6 pt line
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    // Drag anywhere on the track: put the thumb's centre under the pointer.
                    let f = travel > 0 ? min(1, max(0, (v.location.x - thumb / 2) / travel)) : 0
                    scrollPos.scrollTo(x: f * scrollRange)
                })
            }
            .frame(height: 14)
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
