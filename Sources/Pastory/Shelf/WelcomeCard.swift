import SwiftUI

/// First launch: a card built like every other card on the shelf — pushpin, source line, handwritten title —
/// whose body sets the two shortcuts and then asks you to try them. 「开始使用」 retires it for good.
struct WelcomeCard: View {
    @Bindable var model: ShelfModel
    @State private var tick = 0                      // re-read the shortcuts after the recorder changes them
    static let width: CGFloat = 440

    var body: some View {
        let _ = tick
        let shelfKey = Preferences.shared.shortcut(Preferences.Key.hotkeyShelf)
        let captureKey = Preferences.shared.shortcut(Preferences.Key.hotkeyCapture)
        VStack(alignment: .leading, spacing: 0) {
            // Header, as on a clip card: app icon · name, then a rule.
            HStack(spacing: 8) {
                if let logo = Theme.logo {
                    Image(nsImage: logo).resizable().interpolation(.high).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Text("Pastory").font(.serif(16)).foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 6)
            Rectangle().fill(Color.ink.opacity(0.7)).frame(height: 1).padding(.horizontal, 18)
            // Handwritten title between the two rules.
            Text("欢迎使用 Pastory".l).font(.script(28)).foregroundStyle(Color.ink).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.6)).frame(height: 1).padding(.horizontal, 18) }

            VStack(alignment: .leading, spacing: 0) {
                heading("设置常用快捷键".l)
                step(icon: "clipboard", title: "显示 / 隐藏剪贴板".l, key: Preferences.Key.hotkeyShelf, tag: "shelf")
                step(icon: "crop", title: "截图".l, key: Preferences.Key.hotkeyCapture, tag: "capture")

                heading("试一试".l).padding(.top, 10)
                todo(done: model.welcomeTried.contains("shelf"),
                     text: shelfKey.isSet ? String(format: "按 %@ 打开或收起剪贴板".l, shelfKey.display) : "先给剪贴板设一个快捷键".l)
                todo(done: model.welcomeTried.contains("capture"),
                     text: captureKey.isSet ? String(format: "按 %@ 截一张图".l, captureKey.display) : "先给截图设一个快捷键".l)
                todo(done: model.welcomeTried.contains("copy"), text: "复制一段文本".l)
                todo(done: model.welcomeTried.contains("pin"), text: "Pin 一段文本".l, pin: true)

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 18).padding(.top, 8)

            ticketRule.padding(.vertical, 4)

            HStack(spacing: 10) {
                if let p = Theme.menuIcon {
                    Image(nsImage: p).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 20, height: 20).foregroundStyle(Color.ink)
                }
                Text("稍后也能在设置中调整哦".l).font(.serif(12)).foregroundStyle(Color.inkMuted)
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("开始使用".l).font(.serif(15, bold: true)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(Color.paperBlue, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                .shadow(color: .black.opacity(0.4), radius: 9, x: 2, y: 6)
        )
        .overlay(alignment: .top) {
            if let img = Theme.pushpin {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(height: 44)
                    .shadow(color: .black.opacity(0.28), radius: 2, x: 1, y: 2)
                    .offset(x: 0, y: -6)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutsChanged)) { _ in tick += 1 }
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(.serif(13, bold: true)).foregroundStyle(Color.inkMuted).padding(.bottom, 2)
    }

    /// Icon · title · keycaps. A taken shortcut says so under the title.
    private func step(icon: String, title: String, key: String, tag: String) -> some View {
        let taken = HotKeyCenter.shared.failed.contains(tag)
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .light)).foregroundStyle(Color.ink).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(13)).foregroundStyle(Color.ink)
                if taken { Text("被其他应用占用，点击换一个".l).font(.serif(12)).foregroundStyle(Color.inkMuted) }
            }
            Spacer(minLength: 10)
            ShortcutRecorder(key: key, keycaps: true)
        }
        .padding(.vertical, 3)
    }

    /// Checklist line: an empty box that fills once the thing has really been done.
    private func todo(done: Bool, text: String, pin: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(done ? Color.paperBlueDeep : Color.ink.opacity(0.5))
                .frame(width: 20)
            Text(text).font(.serif(13)).foregroundStyle(done ? Color.inkMuted : Color.ink)
                .strikethrough(done, color: Color.inkMuted)
            if pin, let img = Theme.pushpin {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(height: 18).opacity(done ? 0.5 : 1)
            }
        }
        .padding(.vertical, 3)
    }

    /// Dashed tear-off line with the two notches on the card's edges.
    private var ticketRule: some View {
        ZStack {
            Line().stroke(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1).padding(.horizontal, 18)
            HStack {
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: -8)
                Spacer()
                Circle().fill(Paint.desk).frame(width: 16, height: 16).offset(x: 8)
            }
        }
        .frame(height: 16)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p }
    }
}
