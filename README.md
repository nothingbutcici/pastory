# Pastory（代号 Snip Clip）

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
  Clipboard/         NSPasteboard 监听、条目模型、SQLite 索引 + 文件存储、保留期清理
  Shelf/             底部半屏货架：横向卡片、固定、保存到本地（Exporter 弹对话框）、搜索
tools/               make-signing-cert.sh 等一次性脚本
build/               构建产物，不进 git
```

- 新文件放进对应子目录，一个类型一个文件。
- 临时产物（测试截图、抽样图片）走会话 scratchpad，不进项目目录。
- 可复用的取屏 / 快捷键 / 权限代码从 `../cc record` 复制过来改，不做跨项目引用。

## 存储

一切在 `~/Library/Application Support/Pastory/`：

| 路径 | 内容 |
| --- | --- |
| `pastory.sqlite` | 索引（SQLite，WAL）：id、kind(text/url/image/files/video)、创建时间、来源 app、预览片段、OCR 文本、是否 Pin、标题、内容哈希。旧版 `index.json` 首次启动导入后改名 `index.migrated.json` |
| `items/<id>.txt` | 文本 / 链接正文；富文本另存 `<id>.rtf` |
| `items/<id>.png` | 图片原图，带显示器色彩描述文件，不重编码 |
| `items/<id>.json` | 文件条目：路径列表 |
| `items/<id>.mp4` / `.gif` | 录屏本体 |
| `thumbs/<id>.png` | 货架缩略图（长边 640 px） |

索引用 SQLite（`Clipboard/ClipDB.swift`，系统自带 libsqlite3），正文仍是文件；整表在一个事务里写，几千条也快。
自测可用环境变量 `SNIPCLIP_STORE=<dir>` 指到别的目录，不污染真实数据。

- 「保存到本地」每次弹系统保存对话框让用户选位置（默认打开上次用过的文件夹），存储里的原条目不动。
- 清理规则（`Clipboard/Retention.swift`）按自然日：设清理时刻 X（默认 04:00，设置里 0–23 可调）和保留天数 N（默认 1；0 = 永不，此时时刻选择器禁用、不设定时器）。
  任何时候运行检查：过了今天的 X 就清「昨天及更早」（N=1），今天 0:00 之后的一律不动；没到 X 只清「前天及更早」。
  无状态、可重复执行，不需要记"删过没有"；Pin 住的永远不清。触发点只有两个：启动时一次，以及一个定在"最早到期那条的到期时刻"
  （它的日期 + N 天，当天 X 点）的定时器，到点清理后再定下一个；休眠错过会在唤醒时补发。没有周期巡检。
  用户手动删除即落盘并删文件，重开不会回来（自测 `--selftest retention` 覆盖以上场景）。
  索引读写失败会弹一次提示，且清理暂停直到写回成功。缩短保留天数会先告知将清掉多少条再执行。
- 带 `org.nspasteboard.ConcealedType` / `TransientType` 标记的内容（密码管理器等）不记录。
- 存放位置固定在上面这个目录，设置里只显示路径和「打开」，不提供更改。不上云。

## 构建

```bash
./build.sh                      # 产出 build/Pastory.app（bundle id 仍是 com.cici.snipclip，权限不丢）
open "build/Pastory.app"
```

签名顺序：钥匙串里有「Snip Clip Dev」用它；没有就复用 cc record 的「CC Record Dev」（同一台机器、同一用途，
不必再生成一张）；都没有才 ad-hoc（每次重编译都要重新勾屏幕录制权限）。要单独一张证书就跑
`./tools/make-signing-cert.sh`。只需要 Command Line Tools，不需要完整 Xcode。

## 分享给别人

```bash
./dist.sh        # 产出 dist/Pastory-<版本>.zip 和 dist/首次打开.txt，一起发给对方
```

分发包用 ad-hoc 签名（本机自签证书在别人机器上不被信任）。没有 Apple 开发者账号和公证，
对方第一次打开要在「隐私与安全性」里点「仍要打开」一次，说明写在 `首次打开.txt` 里。
版本号改 `Resources/Info.plist` 的 CFBundleShortVersionString。app 图标 `Resources/AppIcon.icns` 由 Logo.png 生成。

## 自测

```bash
BIN="./build/Pastory.app/Contents/MacOS/Pastory"
"$BIN" --selftest capture <out.png>    # 截主屏全图，打印色彩空间；再用系统 screencapture 抽样比像素
"$BIN" --selftest ocr [in.png]         # 不给路径则自绘一张中英文图，识别后核对关键词
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest clipboard 10   # 监听 10 秒，打印期间记录到的条目
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest retention      # 造今天 / 昨天 / 昨天固定 / 三天前，清理后核对存活
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest shelf <out.png>     # 离屏渲染货架面板（含 5 条样例）
"$BIN" --selftest annotate <out.png>   # 离屏渲染标注画布 + 工具条，另存 <out>.flat.png 为合成结果
"$BIN" --selftest gif                  # 合成 2 秒 mp4 → GIF，核对帧数与首帧
"$BIN" --selftest preview <out.png>    # 离屏渲染录屏预览窗（视频区离屏是黑的，看布局用）
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest settings <out.png>   # 离屏渲染货架的设置页
SNIPCLIP_STORE=/tmp/x "$BIN" --selftest editors <out.png>   # 离屏渲染文本编辑窗 <out>.text.png 与图片编辑窗 <out>.image.png
```

后三个不需要屏幕录制权限，改 UI 后先看这两张图。

**会写存储的自测（clipboard / retention / relocate / shelf / settings / editors）必须带 `SNIPCLIP_STORE=<临时目录>`，
不带会直接拒绝运行。** `ClipStore.defaultRoot` 在该环境变量存在时也指向它，所以「搬回默认位置」之类的路径在测试里
永远落在沙箱内。2026-09-12 曾因为这一点没做到，一次自测把用户真实存储清空过，不要再犯。

## 用法

- **⌥⌘S 截图**（⌃⌘A 被微信占用，系统只认先注册的）：拖拽选区；␣ 切窗口模式；F 整屏；单击空白 / 右键 / ⎋ 取消。
  框选时只显示尺寸角标，没有十字线和提示文字。选完立刻整屏取图（重新枚举窗口把遮罩排除掉），之后出现的工具条不会进图。
  ⏎ 或双击 = 复制到剪贴板并进货架；⌘Z 撤销一笔。
- 视觉：货架是纸感（2026-09-12 改）：深棕纹理底，米色纸片卡带票根缺口和虚线，当前剪贴板那张是浅蓝纸；
  正文宋体（Songti SC），标题和「Pastory」手写体（Caveat，CJK 回退翩翩体），设置页同样是纸片分区。
  截图 / 录屏那套（顶栏、标注工具条、子条、尺寸角标、录屏控制条）、录屏预览窗、文本 / 图片编辑窗、
  识别文字面板也全部是纸感（2026-09-12 晚统一）：米色纸条 `Theme.drawPaper` + 深棕桌面 `Theme.drawGround`，
  选中态是浅蓝纸，选区框 / 手柄 / 元素选中框用浅蓝和米纸；按钮统一 `Theme.paperButton`。`Theme.drawIsland` 只剩旧代码。
  logo 在 `Resources/Logo.png`（P 字紫版，透明底），面包人在 `Resources/Mascot.png`（黄色，夹子染成品牌紫；
  原图棋盘格是画进去的，用局部纹理 + 边缘泛洪抠的），菜单栏图标 `Resources/MenuIcon(@2x).png` 来自设计稿
  `Project/codex相关/cc tools visual identity/.../pastory-menubar*.png`，作为 template 使用。
  品牌字体 Ysabeau Office（OFL，`Resources/Fonts/`，启动时按进程注册）只用在「Pastory」字样。
  截图 / 录屏只排除取景遮罩自己的窗口，货架开着时也能被截进去。
- 框选完成后屏幕顶部出品牌条：logo · Snip Clip · [截屏 │ 录屏] · ✕，默认截屏；点录屏进录制流程。
  选区是荧光绿框 + 8 个手柄，拖手柄可以改选区（截图是整屏取一次再按选区裁，拖手柄只是重新裁，标注位置不动），
  右上角深色角标显示像素尺寸。
- 工具条两层，结构对标飞书：主条 = 矩形 R / 椭圆 O / 箭头 A / 直线 L / 画笔 P / 文字 T / 马赛克 M │ 识别文字 │
  撤销 · ✕ 取消 · ✓ 完成（三个纯紫图标一组）。子条只在点了某个工具、或选中了某个元素时从主条下方弹出（带指向小三角），
  内容是三档粗细的小圆点（文字工具显示 小 / 中 / 大；马赛克档位 = 格子大小）和 7 个方形色块（选中打勾，马赛克不显示颜色）；
  改动作用于选中元素，没选中时作为新元素的默认值。再点一次当前工具 = 收起。没有虚线、没有「保存到文件」（剪贴板已经联动）。
  没有选择工具、没有撤销按钮：点到已画的元素就选中它（矩形 / 椭圆只认边框，所以在框里仍能继续画），
  拖动移动，拉手柄改形（直线 / 箭头两端点，方框四角），右上角 ✕ 或 ⌫ 删除，⌘Z 仍可撤销；
  已选中的文字再点一下进入编辑。画笔画完不选中，方便连画。
  线条是手绘感：路径打平后加低频噪声画两遍，每个形状带固定 seed，预览和导出一模一样。
  文字用翩翩体（HanziPen SC，系统自带），没有就退回系统字体。
  「识别文字」弹出可编辑结果，「复制文字」把文字复制走（图片条目也保留）。
- **⌥⌘F 搜索剪贴板**：打开面板并直接聚焦搜索框。三个全局快捷键都在设置里改；录制时当场试注册，
  被其他应用占用、和自己的另一个快捷键重复、或只有 ⌘/⇧ 加单键（会抢走所有应用的同名快捷键）都会拒绝并提示。
- **⇧⌘V 剪贴板**：底部滑出（屏高 55%）深色货架，淡紫强调：左侧侧栏（logo、今日暂存、清理规则、Pin 说明；吉祥物位待素材），
  侧栏底部「Pin 后一直保留」和「设置」两行，设置在面板右半区内展开（`Shelf/SettingsPane`），不弹窗；
  顶部胶囊筛选 全部 / Pin / 图片 / 录屏 / 文本 + 搜索 + ✕，深色卡片配米色内容纸面（app 图标、时间、内容、
  「已复制」标记 = 此刻剪贴板里的那条、说明行、编辑或预览 / Pin / 保存（仅图片、录屏）/ 删除），底部滚动条带左右箭头。左 = 最新。
  单击卡片 = 复制并停留（绿标签跳过去就是反馈）；⏎ 或双击 = 复制并收起。
  每条记录可以起标题（右键「命名…」在卡片头部下方就地输入，点已有标题可改，文本编辑窗顶部也有标题栏）；
  标题加粗显示在来源行下面，来源 app 名不变，搜索也匹配标题。
  铅笔键：文本 / 链接进自己的编辑窗（`Shelf/TextEditorWindow`，⌘⏎ 保存并复制），图片进标注编辑器
  （`Shelf/ImageEditorWindow`，复用截图的画布和工具条，✓ 保存）；保存都是回写同一条记录并复制，Pin 状态不变。
  录屏和文件卡片是眼睛键，走 Quick Look。
  ← → 选，⏎ 复制并收起，空格 Quick Look 预览，P 固定，S 保存到本地（弹对话框选位置），⌫ 删除，⌘F 搜索，⎋ 关闭。
  过滤：全部 / 固定 / 图片 / 录屏 / 文本。
  卡片底栏常驻固定 / 保存 / 删除三个按钮，右键有完整菜单。
- **录屏**：选区上方的「录屏」。点了之后遮罩撤掉、选区外围留一圈紫框、下方一个小条（计时 / 停止 / 丢弃），
  再按一次截图快捷键也是停止。30 帧 H.264、带光标、不录声音、上限 10 分钟。停止后弹预览窗循环播放，
  看好了再选「复制为 MP4」（⏎）/「复制为 GIF」/「丢弃」，复制完窗口自动关。GIF 有体积预算（约 8 MB）：从长边 1280、10 帧/秒起步，
  按时长估算超预算就降帧率、再缩尺寸（长边不低于 640）；编码后若仍超出四分之一，缩一次重编。
  预览窗保存后显示实际大小。GIF 以图片数据进剪贴板（微信 / 飞书 ⌘V 贴出来是动图），MP4 以文件进剪贴板，
  文件名是可读的 `Rec 2026-09-11 16.10.23.mp4`（存储里 `share/` 下的硬链接）。
  文件上剪贴板用 Finder 同款写法（NSURL 对象 + NSFilenamesPboardType），只写 public.file-url 微信会当纯文本贴出路径。
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
