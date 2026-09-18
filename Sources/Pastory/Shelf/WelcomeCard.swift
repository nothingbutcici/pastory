import SwiftUI

/// First launch: a ticket-shaped paper card at the head of the shelf. Two shortcuts to confirm, each ticked off
/// once it has actually been used; 「开始使用」 retires the card for good.
struct WelcomeCard: View {
    @Bindable var model: ShelfModel
    static let width: CGFloat = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("欢迎使用".l).font(.serif(22, bold: true)).foregroundStyle(Color.ink)
                Text("Pastory").font(.script(30)).foregroundStyle(Color.ink)
            }
            Text("设置常用快捷键".l).font(.serif(13)).foregroundStyle(Color.inkMuted)

            step(icon: "clipboard", title: "显示 / 隐藏剪贴板".l, key: Preferences.Key.hotkeyShelf, tag: "shelf",
                 ready: "设置成功！按一下快捷键感受一下".l)
                .padding(.top, 6)
            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            step(icon: "crop", title: "截图".l, key: Preferences.Key.hotkeyCapture, tag: "capture",
                 ready: "快捷键设置成功，现在截图试试看".l)
            Text("点击修改，稍后也能在设置中调整".l).font(.serif(12)).foregroundStyle(Color.inkMuted).padding(.top, 2)

            Spacer(minLength: 4)
            ticketRule.padding(.vertical, 6)

            HStack(spacing: 10) {
                if let logo = Theme.logo {
                    Image(nsImage: logo).resizable().interpolation(.high).frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("也可从菜单栏打开".l).font(.serif(13)).foregroundStyle(Color.inkMuted)
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("开始使用".l).font(.serif(15, bold: true)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .background(Color.paperBlue, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 14)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)
        )
    }

    /// Icon · title with a status line · check · keycaps.
    private func step(icon: String, title: String, key: String, tag: String, ready: String) -> some View {
        let done = model.welcomeTried.contains(tag)
        let taken = HotKeyCenter.shared.failed.contains(tag)
        return HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(Color.ink).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.serif(15)).foregroundStyle(Color.ink)
                Text(taken ? "被其他应用占用，点击换一个".l : (done ? "完成".l : ready))
                    .font(.serif(12)).foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: 12)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(done ? Color.paperBlueDeep : Color.ink.opacity(0.35))
                .padding(.trailing, 4)
            ShortcutRecorder(key: key, keycaps: true)
        }
        .padding(.vertical, 7)
    }

    /// Dashed tear-off line with the two notches on the card's edges.
    private var ticketRule: some View {
        ZStack {
            Line().stroke(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
            HStack {
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: -32)
                Spacer()
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: 32)
            }
        }
        .frame(height: 16)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p }
    }
}
