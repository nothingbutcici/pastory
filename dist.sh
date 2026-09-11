#!/usr/bin/env bash
# Builds a shareable zip: dist/Pastory-<version>.zip
# Signed ad-hoc on purpose: the local dev certificate is not trusted on anyone else's Mac anyway.
# Without an Apple Developer ID + notarization, recipients must approve the app once (see dist/首次打开.txt).
set -euo pipefail
cd "$(dirname "$0")"
SIGN_ID="-" ./build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Pastory.app/Contents/Info.plist)"
mkdir -p dist
rm -f "dist/Pastory-$VERSION.zip"
xattr -cr build/Pastory.app
ditto -c -k --sequesterRsrc --keepParent build/Pastory.app "dist/Pastory-$VERSION.zip"
cat > dist/首次打开.txt <<'TXT'
Pastory 首次打开说明

1. 解压后把 Pastory.app 拖进「应用程序」文件夹。
2. 第一次打开：右键 Pastory.app →「打开」。
   如果系统说「无法打开，因为 Apple 无法检查其是否包含恶意软件」，
   去「系统设置 › 隐私与安全性」，页面底部会有「仍要打开」，点一下再确认一次即可。
   （这是因为 app 没有走 Apple 的开发者签名与公证，只需处理这一次。）
3. 打开后菜单栏会出现 Pastory 图标。第一次截图会请求「屏幕录制」权限：
   系统设置 › 隐私与安全性 › 屏幕录制，勾选 Pastory，然后退出 Pastory 重新打开。
4. 默认快捷键：⌥⌘S 截图 / 录屏，⇧⌘V 打开剪贴板。可以在剪贴板面板左侧「设置」里改。

所有内容只存在本机 ~/Library/Application Support/Pastory/，不联网、不上传。
TXT
echo "→ dist/Pastory-$VERSION.zip ($(du -h "dist/Pastory-$VERSION.zip" | cut -f1))"
