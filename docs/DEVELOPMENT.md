> 这是项目的规则本（约定、存储 / 清理规则、视觉系统、自测）。面向用户的介绍在仓库根目录的 [README.md](../README.md) / [README.zh.md](../README.zh.md)。

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
| `pastory.sqlite` | 索引（SQLite，WAL）：id、kind(text/url/image/files/video)、创建时间、来源 app、预览片段、OCR 文本、是否 Pin、标题、内容哈希。旧版 `index.json` 首次启动导入后改名 `index.migrated.<yyyyMMdd-HHmmss>.json` |
| `items/<id>.txt` | 文本 / 链接正文；富文本另存 `<id>.rtf` |
| `items/<id>.png` | 图片原图，带显示器色彩描述文件，不重编码 |
| `items/<id>.json` | 文件条目：路径列表 |
| `items/<id>.mp4` / `.gif` | 录屏本体 |
| `thumbs/<id>.heic`（旧库里是 .png） | 货架缩略图（长边 640 px） |

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
  选中态是浅蓝纸，选区框 / 手柄 / 元素选中框用浅蓝和米纸；按钮统一 `Theme.paperButton`。深色浮岛那套代码已全部删除。
  截图浮层的条（顶栏 / 工具条 / 子条 / 尺寸角标 / 录屏控制条）2026-09-12 晚再改成和货架一样的深棕磨砂 `Theme.drawDesk`，
  米字 + 浅蓝选中；标注调色盘 = 紫 + #E9631A / #C56F8C / #A9C2E0 / #59382C / #1E151C / #EBEBDF（用户 2026-09-12 晚定）。
  logo 用品牌稿 `Project/codex相关/pastory clipboard concepts/brand/signature-assets/Pastory Logo/`：
  `Resources/Logo.png` 与 `AppIcon.icns` 由 `pastory-app-icon-hd.png` 圆角化生成（1024 画布放 824 圆角方，半径 22.37%），
  `Resources/MenuIcon(@2x).png` 直接取自 `PastoryMenuBar.imageset`（template，build.sh 会拷进包）。面包人 `Resources/Mascot.png` 留在仓库但不进包、代码不引用。
  品牌字体 Ysabeau Office（OFL，`Resources/Fonts/`，启动时按进程注册）只用在「Pastory」字样。
  截图 / 录屏只排除取景遮罩自己的窗口，货架开着时也能被截进去。
- 框选完成后屏幕顶部出品牌条：logo · Snip Clip · [截屏 │ 录屏] · ✕，默认截屏；点录屏进录制流程。
  选区是浅蓝框 + 8 个米纸手柄，拖手柄可以改选区（截图是整屏取一次再按选区裁，拖手柄只是重新裁，标注位置不动），
  右上角深色角标显示像素尺寸。
- 工具条两层，结构对标飞书：主条 = 矩形 R / 椭圆 O / 箭头 A / 直线 L / 画笔 P / 文字 T / 马赛克 M │ 识别文字 │
  撤销 · ✕ 取消 · ✓ 完成（米色图标，✓ 浅蓝）。子条只在点了某个工具、或选中了某个元素时从主条下方弹出（带指向小三角），
  内容是三档粗细的小圆点（文字工具显示 小 / 中 / 大；马赛克档位 = 格子大小）和 7 个方形色块（选中打勾，马赛克不显示颜色）；
  改动作用于选中元素，没选中时作为新元素的默认值。再点一次当前工具 = 收起。没有虚线、没有「保存到文件」（剪贴板已经联动）。
  没有选择工具：点到已画的元素就选中它（矩形 / 椭圆只认边框，所以在框里仍能继续画），
  拖动移动，拉手柄改形（直线 / 箭头两端点，方框四角），右上角 ✕ 或 ⌫ 删除，⌘Z 仍可撤销；
  已选中的文字再点一下进入编辑。画笔画完不选中，方便连画。
  线条是手绘感：路径打平后加低频噪声画两遍，每个形状带固定 seed，预览和导出一模一样。
  文字用翩翩体（HanziPen SC，系统自带），没有就退回系统字体。
  「识别文字」弹出可编辑结果，「复制文字」把文字复制走（图片条目也保留）。
- **⌥⌘F 搜索剪贴板**：打开面板并直接聚焦搜索框。三个全局快捷键都在设置里改；录制时当场试注册，
  被其他应用占用、和自己的另一个快捷键重复会拒绝并提示；单个键（没有 ⌘⌥⌃⇧）提示「至少两个键」；
  只有 ⌘/⇧ 加单键（如 ⌘A）允许设置，但保存后提示「所有应用里的 ⌘A 都会变成这个功能」（2026-09-12 改，之前是直接拒绝）。
- **外部截图工具的图**（微信 / 飞书 / CleanShot 把位图和一个图片文件 URL 一起放上剪贴板——Finder 复制文件不带位图，所以这一组合只会是截图工具；
  或只放一个临时目录里的图片文件）按图片入库（缩略图 + OCR），不是「文件」；Finder 里复制文件（没有位图）仍是文件条目。规则在 `ClipboardMonitor.ingest`，
  `--selftest ingest` 用私有剪贴板验证五种组合。卡片缩略图长边 1200px。
- **取图像素比**以 `NSScreen.backingScaleFactor` 为准（`Screenshotter.pixelScale`，和 `pointPixelScale` 取大），
  截图和录屏都用它；`pointPixelScale` 在部分显示器上返回过 1，导致存下来的图只有一半分辨率。
- **「移除所有导入进来的条目」是唯一会连 Pin 一起删的操作**：手动、有确认框、只针对来源为「导入」的条目；自动清理仍然永远不碰 Pin。
- **导入时保留期不是永不删除**：弹窗只给「导入并改为永不删除」/「取消」，因为导入项都比保留期老，「只导入」等于导入后立刻被清。
- **双语**（2026-09-14）：`App/Localization.swift` 一张表，键就是代码里的中文字面量，`"…".l` 在英文环境返回英文，
  `"图片".l("tab")` 这类带上下文的键写成 `tab|图片`。带数字的句子用 `String(format: "%d 字".l, n)`。
  语言 = 设置 › 语言（跟随系统 / 中文 / English，`Preferences.language`），切换时 `ShelfModel.langTick` 让货架整体重建，
  菜单栏菜单每次打开时重建；`SNIPCLIP_LANG=en` 可强制离屏渲染英文。新增文案：写中文字面量 + `.l`，再往表里加一行英文；
  `ClipStore.importSourceName`（"导入"）是存库的标记，永远不翻译，显示时走「已导入」。
- **更新**（2026-09-16，`App/Updater.swift`）：启动 30 秒后、之后每 24 小时，向 `api.github.com/repos/nothingbutcici/pastory/releases/latest`
  取最新 release（这是 app 唯一的网络请求，不带任何标识；设置 › 系统 可关，菜单和设置里都有「检查更新」）。tag 必须是 `v<版本>`，
  资产是 `.zip`。比当前 `CFBundleShortVersionString` 新就弹窗：下载并安装 / 稍后 / 跳过这个版本。
  **只有 Developer ID 签名的包才自动安装**：下载、`ditto` 解压、`codesign --verify`、比对 TeamIdentifier 和运行中的自己一致，
  再 `replaceItemAt` 原地替换并重新启动；ad-hoc 包或被 App Translocation 挪走的包只打开下载页。
  发版流程：改 Info.plist 版本 → commit → `./release.sh notes.md`（打 tag、传 zip、建 release）。`--selftest updater` 测解析和版本比较。
- **货架键盘（2026-09-16 第五轮审查后）**：设置页打开时只认 ⎋（返回）和 ⌘F，不会对看不见的卡片执行删除 / Pin / 复制；
  搜索框里 ⏎ 直接复制高亮结果并收起、↑↓ 在结果间移动（IME 候选框打开时这些键交还给输入法）；导航 / 功能键（U+F700 私用区）不会打进搜索框；
  首个字母先存进 `pendingQuery`，等搜索框拿到焦点后再追加，避免被全选覆盖。单击复制后货架"漂浮"期间切到第三个应用会自动收起
  （`NSWorkspace.didActivateApplicationNotification`）。
- **缓存**：`L.isEnglish`、`Theme.serif/script` 字体、货架排序后的列表（按 `ClipStore.version` + 快照号失效）、权限徽标（设置页 1 秒轮询一次，不在 body 里查）；
  缩略图缓存超 100 张时只淘汰最老的三分之一；没有缩略图文件的条目记入 `thumbMissing`，显示占位图标，不再反复解码；辅助功能的系统提示每次启动只弹一次。
- **货架细节**（2026-09-16）：面板打开、没有输入框聚焦时直接敲字母 = 开始搜索；删 Pin 住的卡（⌫、垃圾桶、右键）先弹确认，
  没 Pin 的直接删；五个筛选标签的计数一次遍历算完；搜索用每条缓存好的小写文本（按 id + modifiedAt 失效），不再每次按键全量 lowercased。
- **双击 / ⏎ 直接粘贴**（2026-09-16，设置里可关，默认开）：`copyAndClose` 收起货架后重新激活之前的前台应用，确认它在前台后
  用 CGEvent 发一次 ⌘V（`Permissions.sendPaste`）。这一步需要「辅助功能」权限：没有时第一次双击会弹系统提示，并退化为只复制并收起。
  单击仍然只复制。分发包每次重签，权限要重新授（和屏幕录制一样）。这是唯一用到辅助功能的地方。
- **缩略图是 HEIC**（2026-09-16）：长边 900px、质量 0.8，只用于货架显示，约为 PNG 的 1/4；旧的 .png 缩略图继续可读，`thumbURL` 两种都找。
- **截图存储格式**（2026-09-16，设置 › 剪贴板 › 本地数据库截图存储方式）：默认 HEIC 质量 0.9（2026-09-16 起；ImageIO 编码，保留原色彩空间，约为 PNG 的 1/3），可选无损 PNG。只影响新截图；`contentHash` 永远是原 PNG 的 hash，去重不受格式影响；
  `ClipStore.png(of:)` 对 HEIC 项解码后再包成 PNG 交给剪贴板 / 编辑器 / 导出（像素、色彩空间不变），Quick Look 直接看 HEIC 文件。
- **货架焦点**：单击卡片复制后 `handBackFocus()` 把前台应用重新激活，货架留在屏幕上但不再是 key window，⌘V 落到用户的应用里
  （之前货架一直持有键盘，⌘V 无处可去，「粘不进 Claude Code」就是这个）；此时点货架外任意位置仍会关闭，靠全局鼠标监听
  （鼠标事件的全局监听不需要辅助功能权限）。面板在启动时 `prewarm()` 预建，缩略图后台解码并在 `show()` 时预热前 10 张。
- **为将来同步预留的两样东西**（2026-09-15）：每条有 `modifiedAt`（任何字段改动都更新；老行 = created_at，`ALTER TABLE` 自动补列），
  删除（手动或清理）在 `tombstones` 表留 `id + content_hash + deleted_at`，正文照删；`importEntries` 跳过墓碑里的 hash
  （在这台机器删过的东西不会被另一份 Pastory 库导回来），墓碑 30 天后在清理时顺带清掉。新复制同样内容仍是新条目，不受墓碑影响。
  `--selftest tombstone` 验证。
- **去重**（2026-09-12 夜改）：再次复制历史里已有的内容（同 kind 家族、内容 hash 相同）不会生成新卡，而是把那张卡提到最前，
  标题和 Pin 跟着；之前只和最新一条比。
- **货架出场**：窗口固定在所在屏幕底部不越界，动画是窗口内内容上滑 28pt + 淡入，系统窗口阴影关掉
  （之前从屏幕下方滑入 + 阴影，会在排列在下方的第二块屏顶部露出来）。
- **SQLite 写法**（2026-09-12 晚改）：单条改动（复制置顶、Pin、标题、OCR 回写、编辑、新增、删除）走单行 upsert / delete，
  只有清空、导入、迁移走整表重写；写失败的语义不变（`lastSaveFailed`，UI 回滚）。
- **录屏预览 / 转 GIF 期间按截图键**只响一声，不会丢弃录像；标注阶段 ⎋ 交回画布（先取消选中 / 退出文字框，再取消整次），
  系统级的 ⎋ 热键只在框选阶段挂着。三个快捷键录制框共用一个 suspend 计数，先后打开不会把全局键弄丢。
- **屏幕录制权限**：系统自己的授权框每次启动最多弹一次；之后截图再被拒时弹我们的提示，第一个按钮是
  「我已打开，重新启动 Pastory」（授权只对新进程生效，重启是唯一办法），第二个才是「打开系统设置」。
  从终端直接启动的 Pastory，权限会记在终端名下，正式使用要从 Finder / 启动台打开。
- **自测护栏**：会写库的子命令（clipboard / retention / shelf / settings / editors / import）必须带 `SNIPCLIP_STORE`，
  且路径不能在 `~/Library/Application Support` 下面（不管叫什么名字），否则直接拒绝。
- **截图中再按截图键 = 重新框选**，不是退出；打开着的「识别文字」面板会留在原地（这样才能截它），
  完成时只带上属于这次截图的识别文本（OCR 面板带 token）。⎋ 仍是取消。
- **卡片标题**：输入框无论怎么离开（⏎、✓、点别处、切到别的卡、⎋）都算保存，删空即去掉标题；草稿没变就不写盘。
- **取屏浮层不激活自己、框选期间也不做 key window**（2026-09-16）：遮罩是 `.nonactivatingPanel`，`canBecomeMain = false`，
  而且在拍下图片之前不 `makeKey`（抢走 key 会让前台应用的下拉菜单 / popover 立刻收起，之前 Codex 的设置弹窗、会议软件的麦克风下拉就是这样丢的）。
  框选阶段的键盘全靠系统级钩子：⎋ 取消、空格切窗口模式、F / ⏎ 整屏；十字光标靠 mouseMoved 手动设置（cursor rect 只对 key window 生效）。
  截到图、标注器出现后才 `makeKey`，钩子同时解绑。第一下按压就开始框选（`acceptsFirstMouse`）。
- **导入**：设置 → 剪贴板 → 「从其他剪贴板工具导入（SQLite）」：选数据库文件（任意扩展名）或一个文件夹（Pastory 库，或任何目录：按文件头找出里面的 SQLite 文件，最多向下三层，全部读），
  `Clipboard/Importer.swift` 先复制一份再读（连同 -wal/-shm），Pastory 库按 schema 精确导，其他库按启发式：
  文本列 / UTF-8 blob 当文本、PNG/JPEG/TIFF blob 当图片、名字像 date/time/copied 的列当时间（识别 1970 秒、2001 秒、毫秒、ISO），
  像 pin/favorite 的列当 Pin；Core Data 子表通过整数列关联到有日期的父表，同一条的多种表示（plain+rtf、png+tiff）只留一份。
  **Paste（wiheads，Setapp 版目录 `~/Library/Application Support/com.wiheads.paste-setapp/db.sqlite`）** 有专门读法：
  `ZITEMENTITY`（时间 ZTIMESTAMP/ZCREATEDAT，ZLIST 指向列表，条目最多的列表当历史、其余当 Pinboard=Pin）→
  `ZITEMDATAENTITY.ZRAWPASTEBOARDITEMS`（剪贴板项归档；大块走 Core Data 外置存储 `.db_SUPPORT/_EXTERNAL_DATA/<UUID>`，
  实测引用 = 0x02 + UUID 文本）。blob 实测 = 0x01 + 压缩过的 plist（小的走 LZFSE 帧 `bvx…`，大的像 raw deflate，
  `PasteboardArchive.unwrap` 按顺序试 lzfse / zlib / lz4 / lzma），plist 是 `[{types: [UTI…], data…: [bytes…]}]`，
  `PasteboardArchive.payload` 取一张图或一段文本。用 `compression_tool` 仿造的库全部通过；真机导入结果待朋友反馈。
  弹窗先报数量再导入，已存在的内容按 hash 跳过，Pin 保留；导入的一批保持内部先后，整体后移到比 Pastory 自己最早的一条还早
  （导入的历史永远排在自己记录的后面）。保留期不是「永不删除」时弹窗会提醒这些旧内容下次清理就会被清，可一键改为永不删除。`--selftest import <db>` 可用假库验证。
- **⇧⌘V 剪贴板**：底部滑出（屏高 48%，最少 420pt）纸感货架：左侧侧栏（手写 Pastory、剪贴板 / 设置两行、今日暂存 + Pin 说明），
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
- 设置：三个快捷键、保留期（默认到次日凌晨 4 点）、图片自动 OCR、保存位置、登录时启动。

## 权限

屏幕录制（截图必需）。辅助功能：可选，只用于「双击 / ⏎ 后直接粘贴」那一次 ⌘V；不授权则退化为只复制并收起。
丢权限时 `tccutil reset ScreenCapture com.cici.snipclip` 后重新启动。

## 已知边界

- 选区不跨显示器。
- 货架不做条目合并 / 拼接，只做固定与导出。
- 文件类型条目只存路径引用，不复制文件本体；源文件删了卡片就失效。
- 单条文本超过 20 MB 不入库。
- 不上云；要跨设备自行把存储目录放进 iCloud Drive。
