#!/usr/bin/env bash
# Builds a shareable zip: dist/Pastory-<version>.zip
# Signed ad-hoc on purpose: the local dev certificate is not trusted on anyone else's Mac anyway.
# Without an Apple Developer ID + notarization, recipients must approve the app once (see dist/首次打开.txt).
set -euo pipefail
cd "$(dirname "$0")"
# Signing: a "Developer ID Application" identity in the keychain is used automatically (hardened runtime,
# timestamp), then the zip is notarized with the keychain profile NOTARY_PROFILE (default "pastory-notary",
# created once with `xcrun notarytool store-credentials`) and the ticket is stapled. No identity → ad-hoc,
# recipients need "Open Anyway" once.
DEV_ID="$( (security find-identity -v -p codesigning 2>/dev/null || true) | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
NOTARY_PROFILE="${NOTARY_PROFILE:-pastory-notary}"
# Universal: Intel Macs get "你无法打开这个软件" from an arm64-only binary.
ARCHS="arm64 x86_64" SIGN_ID="${DEV_ID:--}" ./build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Pastory.app/Contents/Info.plist)"
mkdir -p dist
rm -f "dist/Pastory-$VERSION.zip"
xattr -cr build/Pastory.app
ditto -c -k --sequesterRsrc --keepParent build/Pastory.app "dist/Pastory-$VERSION.zip"
if [ -n "$DEV_ID" ]; then
    echo "→ notarizing as $DEV_ID (profile $NOTARY_PROFILE)…"
    xcrun notarytool submit "dist/Pastory-$VERSION.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/Pastory.app
    rm -f "dist/Pastory-$VERSION.zip"
    ditto -c -k --sequesterRsrc --keepParent build/Pastory.app "dist/Pastory-$VERSION.zip"   # re-zip with the ticket inside
    spctl --assess --type execute -vv build/Pastory.app 2>&1 | tail -2
    NOTARIZED=1
fi
cat > dist/首次打开.txt <<'TXT'
Pastory 首次打开说明

需要 macOS 15 (Sequoia) 或更新；Intel 和 Apple 芯片的 Mac 都可以。

1. 解压后把 Pastory.app 拖进「应用程序」文件夹。
2. 第一次打开：双击 Pastory.app。
   这个包已经过 Apple 公证，系统最多问一句「这是从互联网下载的应用，确定打开？」，点「打开」即可。
3. Pastory 没有主窗口：打开后只在屏幕右上角菜单栏出现一个手写的 P 图标，第一次会自动弹出底部的剪贴板面板。
   如果什么都没出现，先看菜单栏有没有 P。
4. 第一次截图会请求「屏幕录制」权限：系统设置 › 隐私与安全性 › 屏幕录制，打开 Pastory，然后退出 Pastory 重新打开。
5. 默认快捷键：⌥⌘S 截图 / 录屏，⇧⌘V 打开剪贴板。可以在剪贴板面板左侧「设置」里改。

还是打不开？在「终端」里粘贴这两行（去掉隔离标记后再打开）：
  xattr -dr com.apple.quarantine /Applications/Pastory.app
  open /Applications/Pastory.app

所有内容只存在本机 ~/Library/Application Support/Pastory/，不联网、不上传。
界面语言跟随系统（中文 / English），也可以在剪贴板面板 › 设置 › 语言 里改。

---------------------------------------------------------------- English

Pastory — first launch
Requires macOS 15 (Sequoia) or later; Intel and Apple silicon.

1. Unzip and drag Pastory.app into Applications.
2. Double-click it. The app is notarized by Apple; at most macOS asks once whether to open an app
   downloaded from the internet — click Open.
3. Pastory has no main window: look for the handwritten P in the menu bar. The clipboard shelf opens by itself on first launch.
4. The first screenshot asks for Screen Recording permission: turn Pastory on, then relaunch it.
5. Default shortcuts: ⌥⌘S screenshot / record, ⇧⌘V clipboard shelf. Change them in the shelf › Settings.
   Language follows the system (中文 / English) and can be switched in Settings › Language.

Everything stays in ~/Library/Application Support/Pastory/ on this Mac. No network, no upload.
Still won't open? In Terminal:  xattr -dr com.apple.quarantine /Applications/Pastory.app && open /Applications/Pastory.app
TXT
if [ -z "${NOTARIZED:-}" ]; then
    # Not notarized: swap the two "first open" lines for the Gatekeeper walk-through.
    sed -i '' \
      -e 's|^2. 第一次打开：双击 Pastory.app。$|2. 第一次打开：双击 Pastory.app。系统会说「无法打开，因为 Apple 无法检查其是否包含恶意软件」，点「完成」。|' \
      -e 's|^   这个包已经过 Apple 公证，系统最多问一句「这是从互联网下载的应用，确定打开？」，点「打开」即可。$|   再去「系统设置 › 隐私与安全性」，往下滚到底，点「仍要打开」，输入一次密码。（这个包未经公证，只需处理这一次。）|' \
      -e 's|^2. Double-click it. The app is notarized by Apple; at most macOS asks once whether to open an app$|2. Double-click it. macOS will say it cannot verify the app: click Done, then System Settings › Privacy \& Security,|' \
      -e 's|^   downloaded from the internet — click Open.$|   scroll to the bottom and click "Open Anyway" (password once). This build is not notarized; it happens only the first time.|' \
      dist/首次打开.txt
fi
echo "→ dist/Pastory-$VERSION.zip ($(du -h "dist/Pastory-$VERSION.zip" | cut -f1))${NOTARIZED:+ · notarized & stapled}"
