import Foundation

/// Two languages, one table. Source strings are the Chinese literals in the code; `"…".l` returns the English
/// when the app runs in English. Keys with a context ("tab") disambiguate words that translate differently.
enum L {
    /// Resolved from Preferences ("system" / "zh" / "en"); PASTORY_LANG overrides for offscreen renders.
    /// Cached: a card body asks a dozen times per render. `Preferences.language` resets it.
    static var isEnglish: Bool {
        if let c = cached { return c }
        let v: Bool
        if let env = envOverride, !env.isEmpty { v = env == "en" }
        else {
            switch Preferences.shared.language {
            case "zh": v = false
            case "en": v = true
            default: v = !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
            }
        }
        cached = v
        return v
    }
    nonisolated(unsafe) private static var cached: Bool?
    private static let envOverride = Sandbox.language
    static func languageChanged() { cached = nil; NotificationCenter.default.post(name: .languageChanged, object: nil) }

    /// Source strings → English. A plain array of pairs: a duplicate here must never be a launch crash
    /// (a dictionary literal traps on duplicate keys); `--selftest l10n` reports duplicates and unused keys.
    static let pairs: [(String, String)] = [
        // Capture chrome
        ("复制", "Copy"), ("识别文字", "Recognize Text"), ("撤销 ⌘Z", "Undo ⌘Z"), ("取消 ⎋", "Cancel ⎋"),
        ("完成 ⏎ · 复制到剪贴板", "Done ⏎ · copy to clipboard"), ("小", "S"), ("中", "M"), ("大", "L"),
        ("输入文字", "Type here"), ("矩形  R", "Rectangle  R"), ("椭圆  O", "Ellipse  O"), ("箭头  A", "Arrow  A"),
        ("直线  L", "Line  L"), ("画笔  P", "Pen  P"), ("文字  T", "Text  T"), ("马赛克  M", "Mosaic  M"),
        ("识别中…", "Recognizing…"), ("没有识别到文字", "No text found"), ("%d 字 · 可直接编辑", "%d characters · editable"),
        ("正在下载 Pastory %@…", "Downloading Pastory %@…"), ("正在连接 GitHub…", "Connecting to GitHub…"), ("正在校验并安装…", "Verifying and installing…"),
        ("重试", "Retry"), ("下载的更新包没有通过签名校验，已放弃安装。", "The downloaded update failed signature verification and was not installed."),
        ("下载的更新包不完整。", "The downloaded update is incomplete."), ("连不上 GitHub（可能需要代理）", "Cannot reach GitHub (a proxy may help)"),
        ("连不上 GitHub，更新包没有下载下来。\n\n部分网络直连 GitHub 不稳定：可以打开代理后重试，或者从下载页手动下载。", "Could not reach GitHub, so the update was not downloaded.\n\nSome networks cannot reach GitHub reliably: turn on a proxy and try again, or download it manually from the release page."),
        ("欢迎使用", "Welcome to"), ("设置常用快捷键", "Set your two shortcuts"), ("开始使用", "Get Started"),
        ("点击修改，稍后也能在设置中调整", "Click to change; you can adjust these in Settings later."), ("也可从菜单栏打开", "Also opens from the menu bar"),
        ("设置成功！按一下快捷键感受一下", "All set! Press the shortcut to try it"), ("快捷键设置成功，现在截图试试看", "All set! Take a screenshot to try it"),
        ("被其他应用占用，点击换一个", "Taken by another app. Click to pick another"), ("完成", "Done"),
        ("全部保留", "Keeping everything"), ("可在设置里定时清理", "Schedule cleanup in Settings"), ("保留 %d 天", "Keeping %d days"),
        ("记录密码管理器复制的内容", "Record copies from password managers"),
        ("「密码」、1Password 等应用复制的内容也会进历史；带「请勿保存」标记的仍然跳过。", "Copies from Passwords, 1Password and similar apps go into history; anything marked do-not-save is still skipped."),
        ("「密码」、1Password 等应用复制的内容不进历史，带「请勿保存」标记的内容也不记。", "Copies from Passwords, 1Password and similar apps are never recorded, nor is anything marked do-not-save."),
        ("复制文字", "Copy Text"), ("关闭", "Close"), ("截屏", "Screenshot"), ("录屏", "Record"), ("取消", "Cancel"),
        // Menu bar / app
        ("截图", "Screenshot"), ("剪贴板", "Clipboard"), ("搜索剪贴板", "Search Clipboard"),
        ("快捷键被其他应用占用", "Shortcut taken by another app"),
        ("\n\n另一个应用（常见是微信、飞书）已经注册了同样的组合键，系统只认先注册的那个。换一个组合键，或者去那个应用里改掉它的。", "\n\nAnother app (often WeChat or Feishu) already registered the same combination; macOS honours whoever registered first. Pick another combination, or change it in that app."),
        ("打开设置", "Open Settings"), ("稍后", "Later"), ("隐藏剪贴板", "Hide Clipboard"), ("显示剪贴板", "Show Clipboard"),
        ("暂停记录剪贴板", "Pause Clipboard Capture"), ("打开存储文件夹", "Open Storage Folder"), ("设置…", "Settings…"),
        ("退出 Pastory", "Quit Pastory"), ("编辑", "Edit"), ("撤销", "Undo"), ("重做", "Redo"), ("剪切", "Cut"), ("拷贝", "Copy"),
        ("粘贴", "Paste"), ("全选", "Select All"),
        // Permissions
        ("Pastory 还没有屏幕录制权限", "Pastory has no Screen Recording permission yet"),
        ("在「系统设置 › 隐私与安全性 › 屏幕录制」里打开 Pastory。已经打开了的话，权限要重新启动后才生效。", "Turn Pastory on in System Settings › Privacy & Security › Screen Recording. If it is already on, the permission only takes effect after a relaunch."),
        ("我已打开，重新启动 Pastory", "It's on — relaunch Pastory"), ("打开系统设置", "Open System Settings"), ("未设置", "Not set"),
        // Shortcut recorder
        ("被其他应用占用", "Taken by another app"), ("按下组合键", "Press keys"), ("不设快捷键", "No shortcut"),
        ("至少两个键：⌘ ⌥ ⌃ ⇧ 中的一个加一个键", "At least two keys: one of ⌘ ⌥ ⌃ ⇧ plus a key"),
        ("没收到按键。如果对方应用弹出来了，说明这个组合已被它占用", "No key arrived. If another app reacted, that combination already belongs to it."),
        ("已被其他应用占用，换一个", "Taken by another app, pick another"), ("已被 %@ 占用，换一个", "Taken by %@, pick another"),
        ("已被 Pastory 的「%@」占用，换一个", "Already used by Pastory's “%@”, pick another"),
        ("已设置。注意：所有应用里的 %@ 都会变成这个功能", "Set. Note: %@ in every app now triggers this."),
        // Recording
        ("录屏预览", "Recording Preview"), ("丢弃", "Discard"), ("复制为 GIF", "Copy as GIF"),
        ("复制为 MP4", "Copy as MP4"), ("保存中…", "Saving…"), ("录屏失败", "Recording failed"), ("■ 停止", "■ Stop"),
        ("正在转 GIF…", "Converting to GIF…"), ("正在转 GIF… %d%%", "Converting to GIF… %d%%"), ("GIF 转换失败：%@，可以改选 MP4", "GIF conversion failed: %@ — MP4 is still available"),
        // Items
        ("文本", "Text"), ("链接", "Link"), ("图片", "Image"), ("文件", "Files"), ("已导入", "Imported"),
        ("tab|全部", "All"), ("tab|图片", "Images"), ("tab|录屏", "Recordings"), ("tab|文本", "Text"),
        ("Pastory 读写不了存储目录", "Pastory cannot read or write its storage folder"),
        ("在修好之前不会写入任何改动，也不会清理。检查磁盘空间后重新打开 Pastory。", "Nothing will be written or cleaned up until this is fixed. Check disk space and reopen Pastory."),
        ("… 共 %d 项", "… %d items"), ("%@ · %d 秒%@", "%@ · %d s%@"),
        ("这不是 SQLite 数据库文件", "Not a SQLite database"), ("请选择某个剪贴板工具自己的数据文件夹，而不是整个资源库", "Pick the clipboard app's own data folder, not the whole Library"), ("没有找到能导入的文本或图片", "No importable text or images found"),
        // Cards
        ("输入标题", "Title"), ("保存 ⏎", "Save ⏎"), ("点击重命名", "Click to rename"), ("已复制", "Copied"), ("编辑标注", "Annotate"),
        ("编辑文字", "Edit Text"), ("预览", "Preview"), ("保存到本地…", "Save to Disk…"), ("删除", "Delete"), ("取消 Pin", "Unpin"),
        ("Pin 住，不会被自动清理", "Pin: never auto-deleted"), ("%d 字", "%d chars"), ("%d 项", "%d items"),
        ("保存", "Save"), ("保存到这里", "Save Here"), ("选择一个文件夹，把这些文件复制过去", "Choose a folder to copy these files into"),
        ("编辑图片", "Edit Image"), ("+ 加个标题", "+ add a title"), ("保存并复制", "Save and Copy"),
        // Shelf
        ("设置", "Settings"), ("今日暂存", "Today's clips"), ("Pin 后长期保存", "Pin to keep"), ("关闭 ⎋", "Close ⎋"),
        ("还没有内容。复制点什么，或者按 %@ 截个图。", "Nothing yet. Copy something, or press %@ to take a screenshot."),
        ("没有匹配的内容", "No matches"), ("复制并关闭", "Copy and Close"), ("命名…", "Name…"), ("重命名…", "Rename…"),
        ("去掉标题", "Remove Title"), ("在 Finder 中显示", "Show in Finder"), ("打开", "Open"), ("复制识别出的文字", "Copy Recognized Text"),
        // Settings
        ("返回剪贴板", "Back to Clipboard"), ("快捷键", "Shortcuts"), ("显示 / 隐藏剪贴板", "Show / Hide Clipboard"),
        ("未 Pin 内容保留时间", "Keep unpinned items for"), ("1 天", "1 day"), ("3 天", "3 days"), ("7 天", "7 days"), ("30 天", "30 days"),
        ("一年", "1 year"), ("永不删除", "Forever"), ("当日清理时间", "Cleanup time"),
        ("本地数据库截图存储方式", "How screenshots are stored locally"), ("高质量有损压缩，体积约为 PNG 的三分之一", "High-quality lossy; about a third the size of PNG"), ("无损，体积最大", "Lossless; largest files"),
        ("双击直接粘贴到刚才的应用", "Double-click pastes into the app you came from"), ("清理", "Cleanup"), ("截图与录屏", "Screenshots & Recording"), ("需要辅助功能权限", "Needs Accessibility"), ("辅助功能已授权", "Accessibility granted"), ("去授权", "Grant…"),
        ("这条是 Pin 住的，确定删除？", "This one is pinned. Delete it?"), ("Pin 住的内容不会被自动清理，只有这样手动删除才会消失，而且不能恢复。", "Pinned items are never cleaned up automatically; deleting by hand is the only way they go, and it cannot be undone."),
        ("版本更新", "Updates"), ("当前版本 %@", "Current version %@"), ("检查中…", "Checking…"), ("已是最新版本", "Up to date"), ("有新版本 %@", "New version %@"), ("检查失败：%@", "Check failed: %@"),
        ("每天自动检查一次（app 唯一的联网请求，不带任何标识）", "Check once a day (the app's only network request; carries no identifier)"), ("手动检查更新", "Check Now"), ("检查更新…", "Check for Updates…"),
        ("已经是最新版本", "You're up to date"), ("Pastory %@", "Pastory %@"), ("检查更新失败", "Update check failed"), ("暂无发布版本", "No release published yet"),
        ("Pastory %@ 可以更新了（当前 %@）", "Pastory %@ is available (you have %@)"), ("下载并安装", "Download and Install"), ("打开下载页", "Open Download Page"),
        ("跳过这个版本", "Skip This Version"), ("自动更新没有成功", "The update could not be installed"), ("可以手动从下载页更新。", "You can update by hand from the download page."),
        ("录屏编码", "Recording codec"), ("所有设备都能播放", "Plays on every device"), ("体积小一半；老设备和部分 Windows 打不开", "Half the size; older devices and some Windows PCs cannot open it"),
        ("复制为 GIF（会糊，建议 MP4）", "Copy as GIF (blurry at this length; MP4 is better)"),
        ("语言", "Language"), ("跟随系统", "System"), ("中文", "中文"),
        ("从其他剪贴板工具导入（SQLite）", "Import from another clipboard app (SQLite)"), ("选择数据库…", "Choose Database…"), ("导入", "Import"),
        ("移除所有导入进来的条目（来源为「导入」）", "Remove everything that was imported"), ("移除", "Remove"),
        ("手动清空一次（不含已 Pin 内容）", "Clear now (pinned items stay)"), ("已清空", "Cleared"), ("现在清空", "Clear Now"),
        ("位置", "Locations"), ("「保存到本地」默认打开的文件夹", "Default folder for “Save to Disk”"), ("选择…", "Choose…"),
        ("剪贴板内容临时存放位置", "Where clipboard items are stored"), ("系统", "System"), ("登录时启动", "Launch at login"),
        ("屏幕录制权限（截图、录屏需要）", "Screen Recording permission (screenshots and recording)"), ("已授权", "Granted"), ("未授权", "Not granted"),
        ("把保留期改成 %d 天？", "Change retention to %d days?"),
        ("会立刻清掉 %d 条未 Pin 的记录。Pin 住的不受影响。", "%d unpinned items will be removed right away. Pinned items are not affected."),
        ("改并清理", "Change and Clean"), ("移除 %d 条导入的内容？", "Remove %d imported items?"),
        ("只删来源标为「导入」的条目，包括其中已 Pin 的；其他内容不动。", "Only items marked as imported are deleted, pinned ones included; nothing else is touched."),
        ("已移除 %d 条", "Removed %d"), ("扫描", "Scan"),
        ("选另一个剪贴板工具的数据库文件或它的数据文件夹，或另一台机器的 Pastory 文件夹", "Choose another clipboard app's database file or data folder, or a Pastory folder from another Mac"),
        ("扫描中…", "Scanning…"), ("导入中…", "Importing…"), ("找到 %d 条文本、%d 张图片", "Found %d texts and %d images"),
        ("来自 %@。已经在 Pastory 里的内容会自动跳过，Pin 会保留；导入的内容排在 Pastory 自己记录的后面。", "From %@. Items already in Pastory are skipped, pins are kept; imported history sorts after Pastory's own items."),
        ("\n\n当前保留期是 %d 天，而这些内容都比保留期老：导入会同时把保留期改为「永不删除」，否则它们马上就会被清掉。", "\n\nRetention is currently %d days and all of this is older than that: importing also sets retention to Forever, otherwise it would be cleaned up immediately."),
        ("导入并改为永不删除", "Import and Keep Forever"), ("没有新内容（都已存在）", "Nothing new (all present)"), ("已导入 %d 条", "Imported %d"),
        ("选择", "Choose"), ("上下滑动或点箭头调整", "Scroll or use the arrows"),
    ]
    static let en: [String: String] = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
}

extension String {
    /// The user-facing form of this Chinese source string.
    var l: String { L.isEnglish ? (L.en[self] ?? self) : self }
    /// Same, with a context prefix for words that need a different English in that spot.
    func l(_ context: String) -> String { L.isEnglish ? (L.en[context + "|" + self] ?? L.en[self] ?? self) : self }
}

extension Notification.Name { static let languageChanged = Notification.Name("pastory.languageChanged") }
