import SwiftUI

/// First launch: a paper card at the head of the shelf that gets the two shortcuts set before anything else.
/// Real cards appear to its right as soon as something is copied; 「开始使用」 retires it for good.
struct WelcomeCard: View {
    @Bindable var model: ShelfModel
    static let width: CGFloat = 540

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("你好，我是 Pastory".l).font(.script(30)).foregroundStyle(Color.ink)
                .padding(.bottom, 2)
            Text("先设两个快捷键，30 秒就好。".l).font(.serif(15)).foregroundStyle(Color.inkMuted)
                .padding(.bottom, 14)
            row("显示 / 隐藏剪贴板".l) { ShortcutRecorder(key: Preferences.Key.hotkeyShelf) }
            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            row("截图".l) { ShortcutRecorder(key: Preferences.Key.hotkeyCapture) }
            Text("被占用就换一个；以后随时在设置里改。".l).font(.serif(13)).foregroundStyle(Color.inkMuted)
                .padding(.top, 8)
            Spacer(minLength: 12)
            Text("菜单栏右上角的手写 P 也能打开我。现在随便复制点什么，它会出现在右边。".l)
                .font(.serif(14)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            HStack {
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("开始使用".l).font(.serif(15, bold: true)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Color.paperBlue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)
        )
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack {
            Text(label).font(.serif(15)).foregroundStyle(Color.ink)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 9)
    }
}
