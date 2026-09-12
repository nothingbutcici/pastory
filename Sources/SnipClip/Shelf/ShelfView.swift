import SwiftUI

// Paper theme tokens. `shelfInk` & co. are what the settings pane paints its paper sections with.
extension Color {
    static let brown = Color(nsColor: Theme.brown)
    static let brownDeep = Color(nsColor: Theme.brownDeep)
    static let paper = Color(nsColor: Theme.paper)
    static let paperDim = Color(nsColor: Theme.paperDim)
    static let paperBlue = Color(nsColor: Theme.paperBlue)
    static let paperBlueDeep = Color(nsColor: Theme.paperBlueDeep)
    static let ink = Color(nsColor: Theme.ink)
    static let inkMuted = Color(nsColor: Theme.inkMuted)
    static let onBrown = Color(nsColor: Theme.onBrown)
    static let onBrownMuted = Color(nsColor: Theme.onBrownMuted)
    // legacy names still used by the settings pane
    static let shelfBG = brown
    static let shelfSide = brownDeep
    static let shelfCard = paper
    static let shelfInk = ink
    static let shelfMuted = inkMuted
    static let shelfBorder = Color(nsColor: Theme.ink).opacity(0.22)
    static let purple = paperBlueDeep
    static let onPurple = ink
    static let lime = Color(nsColor: Theme.lime)
    static let cream = paper
    static let creamInk = ink
}

extension Font {
    static func serif(_ size: CGFloat, bold: Bool = false) -> Font { Font(Theme.serif(size: size, bold: bold)) }
    static func script(_ size: CGFloat) -> Font { Font(Theme.script(size: size)) }
}

/// Grain overlay; multiply on paper, soft-light on the ground.
struct Grain: View {
    var opacity: Double = 0.06
    var body: some View {
        Image(nsImage: Theme.noiseTile).resizable(resizingMode: .tile)
            .opacity(opacity).blendMode(.multiply).allowsHitTesting(false)
    }
}

struct ShelfView: View {
    @Bindable var model: ShelfModel
    @FocusState private var searchFocused: Bool
    @State private var scrollFraction: CGFloat = 0
    @State private var scrollVisible: CGFloat = 1
    @State private var scrollRange: CGFloat = 0
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
                .padding(.horizontal, 20)
            }
        }
        .background(ZStack { Color.brown; Grain(opacity: 0.16) })
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pastory").font(.script(34)).foregroundStyle(Color.onBrown)
                .padding(.leading, 22).padding(.top, 14).padding(.bottom, 26)
            navRow(icon: "clipboard", "剪贴板", active: !model.showSettings) { model.showSettings = false }
            navRow(icon: "gearshape", "设置", active: model.showSettings) { model.showSettings = true }
            Spacer()
            Rectangle().fill(Color.onBrown.opacity(0.25)).frame(height: 1).padding(.horizontal, 22)
            Text("今日暂存").font(.serif(15)).foregroundStyle(Color.onBrown).padding(.leading, 22).padding(.top, 14)
            Text("Pin 后长期保存").font(.serif(12)).foregroundStyle(Color.onBrownMuted).padding(.leading, 22).padding(.top, 4).padding(.bottom, 18)
        }
        .frame(width: 162, alignment: .leading)
        .background(Color.brownDeep.opacity(0.6))
    }

    /// Active row: a light-blue paper tab running off the left edge.
    private func navRow(icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                Text(title).font(.serif(17))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? Color.ink : Color.onBrown)
            .padding(.leading, 22)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                if active { PaperPatch(right: true, seed: 11).padding(.trailing, 8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Header — paper tabs, search, close

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(ShelfFilter.allCases) { f in
                let on = model.filter == f
                Button { model.filter = f } label: {
                    HStack(spacing: 14) {
                        Text(f.rawValue).font(.serif(16))
                        Text("\(model.count(for: f))").font(.serif(15))
                    }
                    .foregroundStyle(on ? Color.ink : Color.onBrown)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background {
                        if on { PaperPatch(top: true, right: true, bottom: true, seed: 23) }
                    }
                    .overlay {
                        if !on { Rectangle().stroke(Color.onBrown.opacity(0.35), lineWidth: 1) }
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.onBrownMuted)
                ZStack(alignment: .leading) {
                    if model.query.isEmpty && !searchFocused {
                        Text("搜索剪贴板").font(.serif(15)).foregroundColor(Color.onBrownMuted).allowsHitTesting(false)
                    }
                    TextField("", text: $model.query)
                        .textFieldStyle(.plain).font(.serif(15))
                        .foregroundColor(Color.onBrown).tint(Color.paperBlue)
                        .focused($searchFocused)
                }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.onBrownMuted) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(width: 400, height: 40)
            .overlay(Rectangle().stroke(Color.onBrown.opacity(0.35), lineWidth: 1))
            Button { ShelfPanelController.shared.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .regular)).foregroundStyle(Color.onBrown).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).help("关闭 ⎋")
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: Cards

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        ClipCardView(item: item, selected: item.id == model.selectedID, onClipboard: item.id == ClipStore.shared.items.first?.id,
                                     renaming: Binding(get: { model.renamingID == item.id },
                                                       set: { if $0 { model.selectedID = item.id; model.renamingID = item.id } else if model.renamingID == item.id { model.renamingID = nil } }),
                                     onCopy: { model.copy(item) },
                                     onCopyAndClose: { model.copyAndClose(item) },
                                     onPreview: { model.selectedID = item.id; model.previewSelected() },
                                     onEdit: { model.selectedID = item.id; model.edit(item) })
                            .id(item.id)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.vertical, 6)
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
                .font(.system(size: 34, weight: .light)).foregroundStyle(Color.onBrownMuted.opacity(0.7))
            Text(model.query.isEmpty
                 ? "还没有内容。复制点什么，或者按 \(Preferences.shared.shortcut(Preferences.Key.hotkeyCapture).display) 截个图。"
                 : "没有匹配的内容")
                .font(.serif(15)).foregroundStyle(Color.onBrownMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer — thin paper-coloured scrollbar

    private var footer: some View {
        HStack(spacing: 14) {
            Button { model.move(-3) } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .regular)) }
                .buttonStyle(.plain).foregroundStyle(Color.onBrownMuted)
            GeometryReader { geo in
                let thumb = max(40, geo.size.width * scrollVisible)
                let travel = geo.size.width - thumb
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.onBrown.opacity(0.12))
                    Capsule().fill(Color.onBrown.opacity(0.55))
                        .frame(width: thumb)
                        .offset(x: travel * scrollFraction)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = travel > 0 ? min(1, max(0, (v.location.x - thumb / 2) / travel)) : 0
                    scrollPos.scrollTo(x: f * scrollRange)
                })
            }
            .frame(height: 14)
            Button { model.move(3) } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .regular)) }
                .buttonStyle(.plain).foregroundStyle(Color.onBrownMuted)
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制") { model.copy(item) }
        Button("复制并关闭") { model.copyAndClose(item) }
        Button(item.title == nil ? "命名…" : "重命名…") { model.selectedID = item.id; model.renamingID = item.id }
        if item.title != nil { Button("去掉标题") { ClipStore.shared.setTitle(nil, for: item.id) } }
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

/// A rectangle whose chosen edges are torn: small irregular teeth, fixed per `seed` so it never shimmers.
struct TornPaper: Shape {
    var top = false, right = false, bottom = false, left = false
    var seed: UInt64 = 7
    var amplitude: CGFloat = 3
    var step: CGFloat = 7

    func path(in r: CGRect) -> Path {
        var g = Seeded(seed)
        func jitter() -> CGFloat { CGFloat(Double(g.next() % 1000) / 1000.0 - 0.5) * 2 * amplitude }
        var p = Path()
        // top-left → top-right
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        if top {
            var x = r.minX + step
            while x < r.maxX { p.addLine(to: CGPoint(x: x, y: r.minY + jitter())); x += step }
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        if right {
            var y = r.minY + step
            while y < r.maxY { p.addLine(to: CGPoint(x: r.maxX + jitter(), y: y)); y += step }
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        if bottom {
            var x = r.maxX - step
            while x > r.minX { p.addLine(to: CGPoint(x: x, y: r.maxY + jitter())); x -= step }
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        if left {
            var y = r.maxY - step
            while y > r.minY { p.addLine(to: CGPoint(x: r.minX + jitter(), y: y)); y -= step }
        }
        p.closeSubpath()
        return p
    }
}

/// Paper with grain, torn where asked, with a soft drop shadow.
struct PaperPatch: View {
    var color: Color = .paperBlue
    var top = false, right = false, bottom = false, left = false
    var seed: UInt64 = 7
    var body: some View {
        let shape = TornPaper(top: top, right: right, bottom: bottom, left: left, seed: seed)
        ZStack { color; Grain(opacity: 0.12) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.4), radius: 5, x: 1, y: 3)
    }
}
