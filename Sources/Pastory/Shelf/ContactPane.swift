import SwiftUI

/// 联系我: four paper sheets — feedback group, GitHub star, X, buy me a coffee.
struct ContactPane: View {
    @Bindable var model: ShelfModel
    static let repoURL = URL(string: "https://github.com/nothingbutcici/pastory")!
    static let xURL = URL(string: "https://x.com/nothingbutcici")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("联系我".l).font(.serif(22, bold: true)).foregroundStyle(Color.onBrown)
                Spacer()
                Button { model.showContact = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("返回剪贴板".l).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.onBrown)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Color.onBrown.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { ShelfPanelController.shared.hide() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .regular)).foregroundStyle(Color.onBrown).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18).padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    sheet("反馈 bug & 提功能".l, "进微信群聊，直接说。".l, qr: Theme.wechatGroup)
                    sheet("GitHub 点个 Star 吧".l, "源码都在这里，喜欢就点一下。".l, link: ("nothingbutcici/pastory", Self.repoURL))
                    sheet("关注我的 X".l, "新版本和碎碎念都在这。".l, link: ("@nothingbutcici", Self.xURL))
                    sheet("Buy me a coffee", "觉得好用，请我喝一杯。".l, qr: Theme.coffee)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func sheet(_ title: String, _ line: String, qr: NSImage? = nil, link: (String, URL)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.serif(13, bold: true)).foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            Text(line).font(.serif(14)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.bottom, 12)
            if let qr {
                Image(nsImage: qr).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(8).background(Color.white)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
            if let (label, url) = link {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        Text(label).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().stroke(Color.ink.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)
        )
    }
}
