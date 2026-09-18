import SwiftUI

// Paper theme tokens, shared by the shelf, its settings pane and the cards.
extension Color {
    static let brownDeep = Color(nsColor: Theme.brownDeep)
    static let paper = Color(nsColor: Theme.paper)
    static let paperDim = Color(nsColor: Theme.paperDim)
    static let paperBlue = Color(nsColor: Theme.paperBlue)
    static let paperBlueDeep = Color(nsColor: Theme.paperBlueDeep)
    static let ink = Color(nsColor: Theme.ink)
    static let inkMuted = Color(nsColor: Theme.inkMuted)
    static let onBrown = Color(nsColor: Theme.onBrown)
    static let onBrownMuted = Color(nsColor: Theme.onBrownMuted)
}

extension Font {
    static func serif(_ size: CGFloat, bold: Bool = false) -> Font { Font(Theme.serif(size: size, bold: bold)) }
    static func script(_ size: CGFloat) -> Font { Font(Theme.script(size: size)) }
}

/// Pre-grained paints (see `Theme.paperTile`): fill shapes with these instead of colour + a blended grain layer.
enum Paint {
    static let paper = ImagePaint(image: Image(nsImage: Theme.paperTile))
    static let paperBlue = ImagePaint(image: Image(nsImage: Theme.paperBlueTile))
    static let desk = ImagePaint(image: Image(nsImage: Theme.deskTile))
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
                    if items.isEmpty && !model.showWelcome { empty } else { cards(items) }
                    footer
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Rectangle().fill(Paint.desk)
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = false; NSApp.keyWindow?.makeFirstResponder(nil) })
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .id(model.langTick)                 // language switch rebuilds the whole shelf
        .onChange(of: model.focusSearch) { _, _ in
            searchFocused = true
            if !model.pendingQuery.isEmpty {
                let typed = model.pendingQuery; model.pendingQuery = ""
                DispatchQueue.main.async { model.query += typed }      // after focus, so the field's select-all does not eat it
            }
        }
        .onChange(of: model.openTick) { _, _ in searchFocused = false }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pastory").font(.script(42)).foregroundStyle(Color.onBrown)
                .padding(.leading, 22).padding(.top, 10).padding(.bottom, 22)
            navRow(icon: "clipboard", "剪贴板".l, active: !model.showSettings) { model.showSettings = false }
            navRow(icon: "gearshape", "设置".l, active: model.showSettings) { model.showSettings = true }
            Spacer()
            Rectangle().fill(Color.onBrown.opacity(0.25)).frame(height: 1).padding(.horizontal, 22)
            Text("今日暂存".l).font(.serif(15)).foregroundStyle(Color.onBrown).padding(.leading, 22).padding(.top, 14)
            Text("Pin 后长期保存".l).font(.serif(12)).foregroundStyle(Color.onBrownMuted).padding(.leading, 22).padding(.top, 4).padding(.bottom, 18)
        }
        .frame(width: 162, alignment: .leading)
        .background(Color.brownDeep.opacity(0.6))
        // A hand-ruled seam between the sidebar and the shelf.
        .overlay(alignment: .trailing) {
            TornPaper(right: true, seed: 5, amplitude: 0.8, step: 5).fill(Color.onBrown.opacity(0.28)).frame(width: 1.5)
        }
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
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                if active {
                    PaperPatch(top: true, right: true, bottom: true, left: true, seed: 11, amplitude: 2.2)
                        .padding(.leading, 6).padding(.trailing, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Header — paper tabs, search, close

    private var header: some View {
        HStack(spacing: 0) {
            // Tabs read like a ruled index: text separated by thin uprights, a baseline under the row;
            // the active one is a torn scrap of blue paper laid on top.
            let counts = model.counts
            ForEach(Array(ShelfFilter.allCases.enumerated()), id: \.element.id) { i, f in
                let on = model.filter == f
                Button { model.filter = f } label: {
                    HStack(spacing: 18) {
                        Text(f.rawValue.l("tab")).font(.serif(17))
                        Text("\(counts[f] ?? 0)").font(.serif(16))
                    }
                    .foregroundStyle(on ? Color.ink : Color.onBrown)
                    .padding(.horizontal, 20).frame(height: 40)
                    .background {
                        if on { PaperPatch(top: true, right: true, bottom: true, left: true, seed: 23 + UInt64(i), amplitude: 2).padding(.vertical, 1) }
                    }
                    .overlay {
                        // Hand-ruled: left, bottom, right — no top edge.
                        if !on { RuledBox(seed: 40 + UInt64(i)).stroke(Color.onBrown.opacity(0.5), lineWidth: 1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.onBrownMuted)
                ZStack(alignment: .leading) {
                    if model.query.isEmpty && !searchFocused {
                        Text("搜索剪贴板".l).font(.serif(15)).foregroundColor(Color.onBrownMuted).allowsHitTesting(false)
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
            .overlay(TornPaper(top: true, right: true, bottom: true, left: true, seed: 31, amplitude: 0.7, step: 6).stroke(Color.onBrown.opacity(0.45), lineWidth: 1))
            Button { ShelfPanelController.shared.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .regular)).foregroundStyle(Color.onBrown).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).help("关闭 ⎋".l)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Cards

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    if model.showWelcome { WelcomeCard(model: model) }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(item: item, selected: item.id == model.selectedID, onClipboard: item.id == ClipStore.shared.items.first?.id,
                                     index: index,
                                     renaming: Binding(get: { model.renamingID == item.id },
                                                       set: { if $0 { model.selectedID = item.id; model.renamingID = item.id } else if model.renamingID == item.id { model.renamingID = nil } }),
                                     onCopy: { model.copy(item) },
                                     onCopyAndClose: { model.copyAndClose(item) },
                                     onPreview: { model.selectedID = item.id; model.previewSelected() },
                                     onEdit: { model.selectedID = item.id; model.edit(item) },
                                     onDelete: { model.delete(item) })
                            .id(item.id)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.top, 16)              // just enough for the pushpin's head
                .padding(.bottom, 6)
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
                 ? String(format: "还没有内容。复制点什么，或者按 %@ 截个图。".l, Preferences.shared.shortcut(Preferences.Key.hotkeyCapture).display)
                 : "没有匹配的内容".l)
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
                    Capsule().fill(Color.onBrown.opacity(0.10)).frame(height: 3)
                    Capsule().fill(Color.onBrown.opacity(0.5)).frame(height: 3)
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
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制".l) { model.copy(item) }
        Button("复制并关闭".l) { model.copyAndClose(item, paste: false) }
        Button(item.title == nil ? "命名…".l : "重命名…".l) { model.selectedID = item.id; model.renamingID = item.id }
        if item.title != nil { Button("去掉标题".l) { ClipStore.shared.setTitle(nil, for: item.id) } }
        if item.kind == .text || item.kind == .url || item.kind == .image {
            Button("编辑".l) { model.selectedID = item.id; model.edit(item) }
        }
        Button("预览".l) { model.selectedID = item.id; model.previewSelected() }
        Button(item.pinned ? "取消 Pin".l : "Pin") { ClipStore.shared.togglePin(item.id) }
        Button("保存到本地…".l) { Exporter.export(item) }
        if item.kind == .files {
            Button("在 Finder 中显示".l) { NSWorkspace.shared.activateFileViewerSelecting(ClipStore.shared.fileURLs(of: item)) }
        }
        if item.kind == .video {
            Button("打开".l) { NSWorkspace.shared.open(ClipStore.shared.payloadURL(item)) }
        }
        if item.kind == .image, let t = item.ocrText, !t.isEmpty {
            Button("复制识别出的文字".l) {
                let it = ClipStore.shared.insertText(t, rtf: nil, source: CaptureCoordinator.source)
                PasteboardWriter.writeText(t, rtf: nil, itemID: it?.id ?? "")
                ShelfPanelController.shared.hide()
            }
        }
        Divider()
        Button("删除".l, role: .destructive) { model.delete(item) }
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
    var blue = true
    var top = false, right = false, bottom = false, left = false
    var seed: UInt64 = 7
    var amplitude: CGFloat = 3
    var body: some View {
        let shape = TornPaper(top: top, right: right, bottom: bottom, left: left, seed: seed, amplitude: amplitude)
        shape.fill(blue ? Paint.paperBlue : Paint.paper)
            .shadow(color: .black.opacity(0.4), radius: 5, x: 1, y: 3)
    }
}

/// Three sides of a box drawn by hand: down the left, along the bottom, up the right. No top.
struct RuledBox: Shape {
    var seed: UInt64 = 1
    var amplitude: CGFloat = 0.9
    func path(in r: CGRect) -> Path {
        var g = Seeded(seed)
        func j() -> CGFloat { CGFloat(Double(g.next() % 1000) / 1000.0 - 0.5) * 2 * amplitude }
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        var y = r.minY + 6
        while y < r.maxY { p.addLine(to: CGPoint(x: r.minX + j(), y: y)); y += 6 }
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        var x = r.minX + 6
        while x < r.maxX { p.addLine(to: CGPoint(x: x, y: r.maxY + j())); x += 6 }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        y = r.maxY - 6
        while y > r.minY { p.addLine(to: CGPoint(x: r.maxX + j(), y: y)); y -= 6 }
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
