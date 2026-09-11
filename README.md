# Snip Clip

macOS 菜单栏工具，截图 + 剪贴板货架合一。截图直接进剪贴板即可 ⌘V 发出去；
所有复制过的内容（含截图）留在底部滑出的半屏货架里，可回看、固定、存到本地，
未固定的按保留期自动清。交互对标 Paste，截图对标飞书（不偏色）+ 微信（OCR）。

## 目录约定

```
README.md            本文件：约定、构建、自测、存储格式
Package.swift        SwiftPM，macOS 15+，只用 Apple 框架，无第三方依赖
build.sh             swift build → build/Snip Clip.app → codesign（自签名证书「Snip Clip Dev」）
Resources/           Info.plist、entitlements、AppIcon.icns
Sources/SnipClip/
  App/               入口、菜单栏、全局快捷键、权限、偏好、设置窗口
  Capture/           ScreenCaptureKit 取图、框选覆盖层、坐标换算、区域录屏（SCRecordingOutput → mp4，可转 GIF）
  Annotate/          截图标注：Excalidraw 风手绘渲染（选择/矩形/椭圆/箭头/直线/画笔/文字/马赛克），OCR 面板
  Clipboard/         NSPasteboard 监听、条目模型、JSON 索引 + 文件存储、保留期清理
  Shelf/             底部半屏货架：横向卡片、固定、保存到本地（Exporter 弹对话框）、搜索
tools/               make-signing-cert.sh 等一次性脚本
build/               构建产物，不进 git
```

- 新文件放进对应子目录，一个类型一个文件。
- 临时产物（测试截图、抽样图片）走会话 scratchpad，不进项目目录。
- 可复用的取屏 / 快捷键 / 权限代码从 `../cc record` 复制过来改，不做跨项目引用。

## 存储

一切在 `~/Library/Application Support/Snip Clip/`：

| 路径 | 内容 |
| --- | --- |
| `index.json` | 条目元数据数组，新的在前：id、kind(text/url/image/files)、创建时间、来源 app、预览片段、OCR 文本、是否固定、内容哈希 |
| `items/<id>.txt` | 文本 / 链接正文；富文本另存 `<id>.rtf` |
| `items/<id>.png` | 图片原图，带显示器色彩描述文件，不重编码 |
| `items/<id>.json` | 文件条目：路径列表 |
| `items/<id>.mp4` / `.gif` | 录屏本体 |
| `thumbs/<id>.png` | 货架缩略图（长边 640 px） |

不用 SQLite：条目量级是几百，Codable 读写整个索引就够。
自测可用环境变量 `SNIPCLIP_STORE=<dir>` 指到别的目录，不污染真实数据。

- 「保存到本地」每次弹系统保存对话框让用户选位置（默认打开上次用过的文件夹），存储里的原条目不动。
- 保留期默认「次日凌晨 4 点清理未固定条目」，可改为 N 天；固定的永不自动清。
- 带 `org.nspasteboard.ConcealedType` / `TransientType` 标记的内容（密码管理器等）不记录。
- 不上云。要跨设备时由用户把存储目录换到 iCloud Drive，本项目不碰服务器。

## 构建

```bash
./build.sh                      # 产出 build/Snip Clip.app
open "build/Snip Clip.app"
```

签名顺序：钥匙串里有「Snip Clip Dev」用它；没有就复用 cc record 的「CC Record Dev」（同一台机器、同一用途，
不必再生成一张）；都没有才 ad-hoc（每次重编译都要重新勾屏幕录制权限）。要单独一张证书就跑
`./tools/make-signing-cert.sh`。只需要 Command Line Tools，不需要完整 Xcode。

## 自测

```bash
BIN="./build/Snip Clip.app/Contents/MacOS/Snip Clip"
"$BIN" --selftest capture <out.png>    # 截主屏全图，打印色彩空间；再用系统 screencapture 抽样比像素
"$BIN" --selftest ocr [in.png]         # 不给路径则自绘一张中英文图，识别后核对关键词
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest clipboard 10   # 监听 10 秒，打印期间记录到的条目
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest retention      # 造今天 / 昨天 / 昨天固定 / 三天前，清理后核对存活
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest shelf <out.png>     # 离屏渲染货架面板（含 5 条样例）
"$BIN" --selftest annotate <out.png>   # 离屏渲染标注画布 + 工具条，另存 <out>.flat.png 为合成结果
"$BIN" --selftest gif                  # 合成 2 秒 mp4 → GIF，核对帧数与首帧
```

后三个不需要屏幕录制权限，改 UI 后先看这两张图。

## 用法

- **⌥⌘S 截图**（⌃⌘A 被微信占用，系统只认先注册的）：拖拽选区；␣ 切窗口模式；F 整屏；单击空白 / 右键 / ⎋ 取消。
  框选时只显示尺寸角标，没有十字线和提示文字。选完立刻取图，之后出现的工具条不会进图。
  ⏎ 或双击 = 复制到剪贴板并进货架；⌘Z 撤销一笔。
- 框选完成后选区上方有「截屏 │ 录屏」切换，默认截屏；点录屏进录制流程。
- 工具条两层，结构对标飞书：主条 = 矩形 R / 椭圆 O / 箭头 A / 直线 L / 画笔 P / 文字 T / 马赛克 M │ 识别文字 │
  撤销 · 红 ✕ 取消 · 绿 ✓ 完成。子条只在点了某个工具、或选中了某个元素时从主条下方弹出（带指向小三角），
  内容是三档粗细的小圆点（文字工具显示 小 / 中 / 大；马赛克档位 = 格子大小）和 7 个方形色块（选中打勾，马赛克不显示颜色）；
  改动作用于选中元素，没选中时作为新元素的默认值。再点一次当前工具 = 收起。没有虚线、没有「保存到文件」（剪贴板已经联动）。
  没有选择工具、没有撤销按钮：点到已画的元素就选中它（矩形 / 椭圆只认边框，所以在框里仍能继续画），
  拖动移动，拉手柄改形（直线 / 箭头两端点，方框四角），右上角 ✕ 或 ⌫ 删除，⌘Z 仍可撤销；
  已选中的文字再点一下进入编辑。画笔画完不选中，方便连画。
  线条是手绘感：路径打平后加低频噪声画两遍，每个形状带固定 seed，预览和导出一模一样。
  文字用翩翩体（HanziPen SC，系统自带），没有就退回系统字体。
  「识别文字」弹出可编辑结果，「复制文字」把文字复制走（图片条目也保留）。
- **⇧⌘V 剪贴板**：底部滑出半屏货架，左 = 最新。单击卡片 = 复制回剪贴板并收起。
  ← → 选，⏎ 复制，P 固定，S 保存到本地（弹对话框选位置），⌫ 删除，⌘F 搜索，⎋ 关闭。
  卡片底栏常驻固定 / 保存 / 删除三个按钮，右键有完整菜单。
- **录屏**：选区上方的「录屏」。点了之后遮罩撤掉、选区外围留一圈紫框、下方一个小条（计时 / 停止 / 丢弃），
  再按一次截图快捷键也是停止。30 帧 H.264、带光标、不录声音、上限 10 分钟。停止后弹预览窗循环播放，
  看好了再选「复制 MP4」（⏎）/「保存为 GIF」/「丢弃」。GIF 有体积预算（约 8 MB）：从长边 1280、10 帧/秒起步，
  按时长估算超预算就降帧率、再缩尺寸（长边不低于 640）；编码后若仍超出四分之一，缩一次重编。
  预览窗保存后显示实际大小。GIF 以图片数据进剪贴板（微信 / 飞书 ⌘V 贴出来是动图），MP4 以文件进剪贴板，
  文件名是可读的 `Rec 2026-09-11 16.10.23.mp4`（存储里 `share/` 下的硬链接）。
  不做鼠标高亮、缩放、剪辑，那是 cc record 的事。
- 菜单栏图标：左键开关货架，右键菜单（截图 / 暂停记录 / 打开存储文件夹 / 设置 / 退出）。
- 设置：两个快捷键、保留期（默认到次日凌晨 4 点）、图片自动 OCR、保存位置、登录时启动。

## 权限

屏幕录制（截图必需）。不需要辅助功能：货架选中只是「复制回剪贴板」，不模拟粘贴。
丢权限时 `tccutil reset ScreenCapture com.cici.snipclip` 后重新启动。

## 已知边界

- 选区不跨显示器。
- 货架不做条目合并 / 拼接，只做固定与导出。
- 文件类型条目只存路径引用，不复制文件本体；源文件删了卡片就失效。
- 单条文本超过 20 MB 不入库。
- 不上云；要跨设备自行把存储目录放进 iCloud Drive。
