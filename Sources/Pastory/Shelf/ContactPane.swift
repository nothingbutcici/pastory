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
                    Spacer(minLength: 0)
                    sheet("反馈 bug & 提功能".l, "Pastory 微信小小群，交个朋友".l, qr: Theme.wechatGroup)
                    sheet("GitHub 点个 Star 吧".l, "开源产品，喜欢就请助力一下".l, link: ("nothingbutcici/pastory", Self.repoURL))
                    sheet("关注我的 X".l, "新版本和碎碎念都在这。".l, link: ("@nothingbutcici", Self.xURL))
                    sheet("Buy me a coffee", "觉得好用，请我喝一杯。".l, qr: Theme.coffee)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 20)
            }
        }
    }

    /// Every sheet is the same size: title, one line, then the QR code or the link button centred in the same slot.
    private func sheet(_ title: String, _ line: String, qr: NSImage? = nil, link: (String, URL)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.serif(13, bold: true)).foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            Text(line).font(.serif(14)).foregroundStyle(Color.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .frame(height: 44, alignment: .top)
            ZStack {
                if let qr {
                    Image(nsImage: qr).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .padding(6).background(Color.white)
                }
                if let (label, url) = link {
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                            Text(label).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.ink.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .padding(.bottom, 8)
        }
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Paint.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 1, y: 4)
        )
    }
}
