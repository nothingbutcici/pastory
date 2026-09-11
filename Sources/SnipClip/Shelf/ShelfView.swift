import SwiftUI

struct ShelfView: View {
    @Bindable var model: ShelfModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.items
        VStack(spacing: 0) {
            header(count: items.count)
            Divider().opacity(0.4)
            if items.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text(model.query.isEmpty ? "还没有内容。复制点什么，或者 \(Preferences.shared.shortcut(Preferences.Key.hotkeyCapture).display) 截个图。" : "没有匹配的内容")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                ClipCardView(item: item, selected: item.id == model.selectedID,
                                             onCopy: { model.copy(item) })
                                    .id(item.id)
                                    .onTapGesture(count: 1) { model.selectedID = item.id; model.copy(item) }
                                    .contextMenu { menu(for: item) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .background(VisualEffect())
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.15)).frame(height: 0.5) }
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scissors").foregroundStyle(.secondary)
            Text("剪贴板").font(.headline)
            Text("\(count) 项").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $model.filter) {
                ForEach(ShelfFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("搜索文字、OCR 结果、来源", text: $model.query)
                    .textFieldStyle(.plain).focused($searchFocused)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .frame(width: 240)
            Button { SettingsWindowController.shared.show() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("设置")
            Button { ShelfPanelController.shared.hide() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭 ⎋")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("复制") { model.copy(item) }
        Button(item.pinned ? "取消固定" : "固定") { ClipStore.shared.togglePin(item.id) }
        Button("保存到本地…") { _ = ClipStore.shared.export(item) }
        if item.kind == .files {
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(ClipStore.shared.fileURLs(of: item)) }
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
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
