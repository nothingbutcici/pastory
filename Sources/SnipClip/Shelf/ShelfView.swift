import SwiftUI

struct ShelfView: View {
    @Bindable var model: ShelfModel
    @FocusState private var searchFocused: Bool
    private static let accent = Color(nsColor: AnnotatePalette.accent)

    var body: some View {
        let items = model.items
        VStack(spacing: 0) {
            header(count: items.count)
            if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(.quaternary)
                    Text(model.query.isEmpty
                         ? "还没有内容。复制点什么，或者按 \(Preferences.shared.shortcut(Preferences.Key.hotkeyCapture).display) 截个图。"
                         : "没有匹配的内容")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(items) { item in
                                ClipCardView(item: item, selected: item.id == model.selectedID,
                                             onCopy: { model.selectedID = item.id; model.copy(item) })
                                    .id(item.id)
                                    .contextMenu { menu(for: item) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 18)
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .background(VisualEffect())
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "scissors").font(.system(size: 13, weight: .semibold)).foregroundStyle(Self.accent)
                Text("剪贴板").font(.system(size: 15, weight: .semibold))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(spacing: 5) {
                Image(systemName: "hand.tap").font(.system(size: 10))
                Text("点一下卡片即复制")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: Capsule())
            Spacer()
            Picker("", selection: $model.filter) {
                ForEach(ShelfFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("搜索内容、识别文字、来源", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 230)
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("设置")
            Button { ShelfPanelController.shared.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭 ⎋")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制") { model.copy(item) }
        Button(item.pinned ? "取消固定" : "固定") { ClipStore.shared.togglePin(item.id) }
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

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
