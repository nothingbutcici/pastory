<p align="center">
  <img src="Resources/Logo.png" width="104" alt="Pastory">
</p>

<h1 align="center">Pastory</h1>

<p align="center">Pastory = Paste + History</p>

<p align="center">
  简体中文 · <a href="README.en.md">English</a>
</p>

<p align="center">喜欢就请不要吝啬你的 Star，感谢各位！</p>

<br>

<p align="center">
  <img src="docs/images/hero-zh.png" alt="Pastory 剪贴板" width="920">
</p>

<br>

<p align="center">你电脑上什么都有历史记录。只有剪贴板除外，它只记得最后一次。</p>

<p align="center">你每天按几十次 ⌘C。其中一大半，是过去已经复制过的东西。</p>

<p align="center">于是那些高频使用的内容：好用的 prompt、发现的宝藏链接、截过的图、客户地址、发票抬头……<br>都在「下一次复制」的时候瞬间消失。</p>

<p align="center">Pastory 给剪贴板开了个长期记忆的外挂：<br>复制过的文字、链接、图片、截图、录屏，都在一个面板里集中管理和调用。</p>

<p align="center">
常用内容 Pin 起来，就算设了定时清理，也不会被删。<br>
重要内容起个标题，一眼就能认出。<br>
单击立即复制，双击直接贴进外部输入框。
</p>

<p align="center">所有东西都在你自己的电脑上。没有账号，除每天一次检查更新外不联网，隐私安全 100% 在你手里。</p>

<p align="center">
  <img src="docs/images/wechat-group.png" alt="微信群：Pastory 小小群" width="160"><br>
  <sub>扫码进微信群，聊用法、提想法</sub>
</p>

<br>

## 安装

macOS 15 或更新，Intel 和 Apple 芯片都可以。

1. 下载 [最新版 zip](../../releases/latest)，解压，把 `Pastory.app` 拖进「应用程序」。
2. 打开它。菜单栏右上角出现手写的 **P**，第一次会自动弹出剪贴板面板。（已过 Apple 公证，请放心“食用”）

   <img src="docs/images/menubar-zh.png" alt="菜单栏里的 P" width="313">

3. 第一次截图时，按提示打开「屏幕录制」权限，然后重新打开 Pastory。

快捷键、自动清理时间、截图存储格式等均可在「设置」中根据偏好自定义。

<br>

## 为什么做它

### 剪贴板，我最核心的需求

每天我都会复制文本、截图很多次，其中不少甚至是一个小时前刚做过的操作（ADHD），反复重复操作ing。

常用的内容有的时候会粘贴进「备忘录」，有的时候会放进 OB。总之信息也很分散。

于是，有了这个小产品！！！

所有复制行为（含截图），都收拢在同一个地方，等待回顾、二次使用，甚至是编辑。

**高阶用法**：如果你来回复制的内容信息密度很高，甚至可以让 Agent 定期读你的 Pastory 数据库，帮你整理成可以 review 的 md 知识库！

<img src="docs/images/clipboard-history.jpg" alt="剪贴板历史" width="600">

### 截图（额外私心加的小功能）

我的 Mac 上同时会用到两个截图工具。

微信截图有色差，但我很喜欢「识别文字」这个功能，所以需要认字的时候，我会唤起微信的截图。

飞书截图没有色差，还能录屏（MP4 / GIF），所以对应的需求我会唤起飞书的截图。

只不过按哪个快捷键，总需要我提前想一下。

另外，两个产品虽然都有基础的标注能力，只是样式都不太「雅」。我很在意标注时字体、文本框好不好看（时刻需要为自己提供情绪价值）。

所以 Pastory 把这些能力都合在一起了！

<img src="docs/images/capture-annotations.jpg" alt="截图之后，随时标注" width="600">

<br>

## 核心功能

### 剪贴板历史

可自由设置唤起快捷键，也可以点击顶部 menu button 唤起。复制过的任何内容都以卡片形式呈现，同时保留来源应用与复制时间。

- **复制内容：** 单击任意卡片，即为复制，可直接粘贴进目标输入框。
- **复制内容，自动带进输入框：** 双击任意卡片，选中内容会直接贴进所在应用输入框。习惯全键盘的话，可在设置里选「双击 + 回车」，用方向键选中卡片后按回车同样直接粘贴。
- **剪贴板搜索：** 支持根据关键词进行历史搜索，搜索范围包括文本、标题、图片中的文本内容。
- **Pin 一下，内容长期保留：** 重要内容随手 Pin 起来，方便随时回捞使用，长期保存。未 Pin 内容可在设置中自定义清理时间。
- **重要内容，添加标题：** 方便浏览，一眼认出。
- **支持二次编辑：** 剪贴板文本、图片均提供二次编辑能力；调整后，新内容会替换原 copy 内容，留在剪贴板中，方便下次使用。
- **其他软件截图：** 微信、飞书、系统截图，只要进了剪贴板，就有一张卡，一样能搜、能 Pin、能标注。

<p>
  <img src="docs/images/clipboard-history.jpg" alt="所有复制历史，都在这里" width="49%">
  <img src="docs/images/clipboard-settings.jpg" alt="设置" width="49%">
</p>
<p>
  <img src="docs/images/card-actions.jpg" alt="一张卡片，四个顺手操作" width="32.5%">
  <img src="docs/images/clipboard-title.jpg" alt="加个标题" width="32.5%">
  <img src="docs/images/clipboard-editing.jpg" alt="已复制内容，接着改改" width="32.5%">
</p>

### 截图 & 录屏

根据设置好的快捷键，进行截图、录屏等相关操作。

颜色按显示器自己的色彩空间取，不会在截图时改变画面原色。

**图片标注是 Obsidian 插件 Excalidraw 的画风**（用过的朋友看到这里应该会很开心）：编辑会很美观：支持矩形、圆、箭头、直线、画笔、文字、马赛克，同时配了七种低饱和的颜色。编辑后分享出去的图大家都会直呼好看！

**文字框：** 拖动四角或四边调整宽高，文字随宽度自动换行，字号保持不变。回车换行，⌘回车或点击框外结束编辑。

**识别文字：** 底层是 Apple 自带的本地 OCR，识别出来的文字也会跟着图一起存进剪贴板，方便后续使用。

**录屏：** 支持 MP4 / GIF，录制后选择对应格式即可。

<p>
  <img src="docs/images/capture-annotations.jpg" alt="截图之后，随时标注" width="32.5%">
  <img src="docs/images/text-recognition.jpg" alt="图片里的字，识别提取文本" width="32.5%">
  <img src="docs/images/recording-formats.jpg" alt="屏幕录制，按格式复制" width="32.5%">
</p>

<br>

## 你为什么需要

#### 寄件地址、开票信息、话术等对你而言常用的文本内容

相信大家都有过：需要某个信息时，每次都得来回翻聊天记录疯狂找的体验。

使用 Pastory：文本复制一次，加个标题如「客户 A 地址」「公司开票信息」。Pin 起来，下次使用，双击就能贴过去。

#### 好用的 Prompt、宝藏链接

复制的那一刻它就在剪贴板里了，终于不用专门逼自己培养随时存到笔记软件的习惯啦！！下次做类似的任务，也不用再思考我在哪个 session 中聊过，翻几十轮对话挨个找。

使用 Pastory：搜索关键词，想用随时都能找得到。

#### 当视觉素材库用

vibe coding 做产品，视觉也很重要。过去疯狂截图找参考，再一个个存在本地文件夹。单图耗时至少 10 秒。

使用 Pastory：简单截图，剪贴板排成一排，方便你比较、再确定最终选中方案。喜欢的 Pin 住，要标注的时候再点开编辑。喜欢就下载保存到桌面，导出的永远是全分辨率 PNG。

<br>

## 隐私

- 所有数据都在 `~/Library/Application Support/Pastory/`：普通文件加一个 SQLite 索引，随时能看、能备份、能拷到另一台 Mac 导入。
- 没有账号，没有统计。唯一的联网请求是每天一次检查更新，不带任何标识，设置里可以关。
- 密码管理器标记为隐藏的内容不会被记录。

<br>

## 从源码构建

```bash
git clone https://github.com/nothingbutcici/pastory.git
cd pastory
./build.sh          # → build/Pastory.app
```

Swift Package Manager，只用 Apple 自带框架。项目约定见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

<br>

## 致谢与许可

字体 [Caveat](https://fonts.google.com/specimen/Caveat)、[Ysabeau Office](https://fonts.google.com/specimen/Ysabeau+Office)（SIL 开源字体许可）。交互受 [Paste](https://pasteapp.io) 启发，标注风格来自 [Excalidraw](https://excalidraw.com)。

[MIT License](LICENSE) · © 2026 nothingbutcici
