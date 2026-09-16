<p align="center">
  <img src="Resources/Logo.png" width="96" alt="Pastory">
</p>

<h1 align="center">Pastory</h1>

<p align="center">
  截图、录屏和所有复制过的东西，都留在 Mac 底部的一张纸架上。<br>
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/images/shelf-zh.png" alt="Pastory 货架" width="900">
</p>

Pastory 是一个 macOS 菜单栏小工具，把两件事合在一起做：

- **截**：一个快捷键，框选区域（或选窗口、整屏），手绘风标注，识别文字，或者把这块区域录成 MP4 / GIF。结果直接进剪贴板。
- **记**：每一次复制，包括上面这些截图录屏，都会出现在一张可以随时唤出的货架上。点一下卡片就复制回来。重要的 Pin 住，其余按你定的规则自动清理。

所有内容只在你的电脑上。没有账号、不联网、不上报。

## 功能

**截图 / 录屏**
- 区域 / 窗口 / 整屏选取，选区可拖手柄改大小；截图时前台应用的菜单和弹层不会被收起。
- 不偏色：按显示器自己的色彩空间取图（P3 屏就是 P3，不转 sRGB）。
- Excalidraw 风标注：矩形、椭圆、箭头、直线、画笔、文字、马赛克，七种颜色三档粗细，可拖动、可改形。
- 本地文字识别（Vision），中英文都行，复制前可以先改。
- 同一块区域录成 MP4，或带体积上限的 GIF，先预览再决定复制。

**货架**
- 文本、链接、图片、文件、录屏各有自己的卡片，带来源应用和时间。搜索覆盖正文、标题和图片里识别出的文字。
- 单击 = 复制并停留，双击或 ⏎ = 复制、收起并直接粘贴进刚才的应用（可选，需要辅助功能权限），空格 = Quick Look。
- Pin、手写体标题、原地编辑文字、给图片再加标注、保存到本地。
- 微信、飞书、CleanShot 等其他工具的截图也按图片入库，有缩略图和文字识别。
- 再次复制以前复制过的内容，不会出现两张一样的卡，而是把原来那张提到最前。

**清理规则说得清**
- 没 Pin 的内容保留 *N* 天（1 / 3 / 7 / 30 / 365 / 永不），按自然日算，清理时刻自己定（默认 04:00）。Pin 住的永远不会被自动删除。手动删除的不会再出现。

**导入**
- 从其他剪贴板工具的 SQLite 库迁移历史（Paste 按其真实结构精确读取，其他 Core Data / SQLite 布局按启发式读），或从另一台 Mac 的 Pastory 文件夹导入。导入的历史排在你自己的记录后面。

**双语**：中文 / English，跟随系统或在设置里切换。

<p align="center">
  <img src="docs/images/capture-en.png" alt="截图与标注" width="900">
</p>

## 安装

需要 macOS 15 (Sequoia) 或更新，Intel 和 Apple 芯片都可以。

1. 在 [Releases](../../releases) 下载 `Pastory-<版本>.zip`，解压，把 `Pastory.app` 拖进「应用程序」。
2. 打开它。在公证完成之前，macOS 会说无法验证这个 app：点「完成」，再到 系统设置 › 隐私与安全性 › **仍要打开**（只需一次）。
3. Pastory 没有主窗口，看菜单栏右上角的手写 **P**。第一次启动会自动弹出货架。
4. 第一次截图会请求「屏幕录制」权限，打开后重新启动 Pastory。

默认快捷键：**⌥⌘S** 截图 / 录屏，**⇧⌘V** 货架，**⌥⌘F** 打开货架并聚焦搜索。都可以在 货架 › 设置 里改。

## 数据在哪

`~/Library/Application Support/Pastory/`

| | |
|---|---|
| `pastory.sqlite` | 索引（SQLite，WAL）：类型、时间、来源应用、预览、识别文字、Pin、标题、内容哈希 |
| `items/<id>.<ext>` | 正文本身：`.txt`、`.png`、`.mp4`、`.gif`，或文件路径列表的 JSON |
| `thumbs/<id>.heic` | 货架缩略图 |

故意用普通文件：Finder 里能直接看，能被备份，整个文件夹拷到另一台 Mac 就能导入。

## 从源码构建

```
git clone https://github.com/nothingbutcici/pastory.git
cd pastory
./build.sh          # → build/Pastory.app（本机架构）
./dist.sh           # → dist/Pastory-<版本>.zip（通用二进制 + 首次打开说明）
```

Swift Package Manager，macOS 15 SDK，只用 Apple 自带框架（ScreenCaptureKit、Vision、AVFoundation、SQLite）。有本地自签名证书时 `build.sh` 会用它签名（`tools/make-signing-cert.sh` 生成），这样重新编译不会丢屏幕录制权限。

离屏自测会渲染每个界面、跑保留期 / 剪贴板入库 / 导入的用例，且不会碰你的真实数据。细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)，那也是这个项目的规则本（存储规则、清理规则、视觉系统、约定）。

## 隐私

Pastory 每天向 GitHub 问一次有没有新版本（设置 › 系统 可关；这是它唯一的网络请求，不带任何标识）。Pastory 每半秒读一次系统剪贴板的变化计数（一个整数），只在变化时读内容；密码管理器标记为隐藏或临时的内容会被跳过。没有任何数据离开这台电脑。

## 致谢

字体：[Caveat](https://fonts.google.com/specimen/Caveat)、[Ysabeau Office](https://fonts.google.com/specimen/Ysabeau+Office)（SIL 开源字体许可，随包附带于 `Resources/Fonts`），以及 macOS 自带的宋体-简 和 翩翩体-简。
