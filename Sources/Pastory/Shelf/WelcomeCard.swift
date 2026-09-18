import SwiftUI

/// First launch: a ticket-shaped paper card at the head of the shelf. Two shortcuts to set, then two things
/// to try; each try is ticked off once it has really happened. 「开始使用」 retires the card for good.
struct WelcomeCard: View {
    @Bindable var model: ShelfModel
    @State private var tick = 0                      // re-read the shortcuts after the recorder changes them
    static let width: CGFloat = 520

    var body: some View {
        let _ = tick
        let shelfKey = Preferences.shared.shortcut(Preferences.Key.hotkeyShelf)
        let captureKey = Preferences.shared.shortcut(Preferences.Key.hotkeyCapture)
        let allDone = model.welcomeTried.isSuperset(of: ["shelf", "capture"])
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("欢迎使用".l).font(.serif(20, bold: true)).foregroundStyle(Color.ink)
                Text("Pastory").font(.script(27)).foregroundStyle(Color.ink)
            }

            heading("设置常用快捷键".l).padding(.top, 10)
            step(icon: "clipboard", title: "显示 / 隐藏剪贴板".l, key: Preferences.Key.hotkeyShelf, tag: "shelf")
            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            step(icon: "crop", title: "截图".l, key: Preferences.Key.hotkeyCapture, tag: "capture")

            heading("试一试".l).padding(.top, 6)
            todo(done: model.welcomeTried.contains("shelf"),
                 text: shelfKey.isSet ? String(format: "按 %@ 打开或收起剪贴板".l, shelfKey.display) : "先给剪贴板设一个快捷键".l)
            todo(done: model.welcomeTried.contains("capture"),
                 text: captureKey.isSet ? String(format: "按 %@ 截一张图".l, captureKey.display) : "先给截图设一个快捷键".l)

            Spacer(minLength: 2)
            ticketRule.padding(.vertical, 3)

            HStack(spacing: 10) {
                Text("稍后也能在设置中调整 · 也可从菜单栏点 P 打开".l).font(.serif(12)).foregroundStyle(Color.inkMuted)
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("开始使用".l).font(.serif(15, bold: true)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(allDone ? Color.paperBlue : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink.opacity(allDone ? 0 : 0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 10)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)
        )
        .onReceive(NotificationCenter.default.publisher(for: .shortcutsChanged)) { _ in tick += 1 }
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(.serif(13, bold: true)).foregroundStyle(Color.ink).padding(.bottom, 1)
    }

    /// Icon · title · keycaps. A taken shortcut says so under the title.
    private func step(icon: String, title: String, key: String, tag: String) -> some View {
        let taken = HotKeyCenter.shared.failed.contains(tag)
        return HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(Color.ink).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.serif(14)).foregroundStyle(Color.ink)
                if taken { Text("被其他应用占用，点击换一个".l).font(.serif(12)).foregroundStyle(Color.inkMuted) }
            }
            Spacer(minLength: 12)
            ShortcutRecorder(key: key, keycaps: true)
        }
        .padding(.vertical, 3)
    }

    /// Checklist line: an empty box that fills once the thing has really been done.
    private func todo(done: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(done ? Color.paperBlueDeep : Color.ink.opacity(0.5))
            Text(text).font(.serif(13)).foregroundStyle(done ? Color.inkMuted : Color.ink)
                .strikethrough(done, color: Color.inkMuted)
        }
        .padding(.vertical, 2)
    }

    /// Dashed tear-off line with the two notches on the card's edges.
    private var ticketRule: some View {
        ZStack {
            Line().stroke(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
            HStack {
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: -30)
                Spacer()
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: 30)
            }
        }
        .frame(height: 16)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p }
    }
}
