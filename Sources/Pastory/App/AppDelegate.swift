import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    /// Launchpad / Dock icon clicked while already running: a menu-bar app has no window to bring up, so open the shelf.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ShelfPanelController.shared.show()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        if SelfTest.handleCommandLine() { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Theme.menuIcon ?? NSImage(systemSymbolName: "scissors", accessibilityDescription: "Pastory")
        statusItem.button?.image?.isTemplate = true
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Preferences.shared.migrateImplicitRetention()
        bindShortcuts()
        NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bindShortcuts() }
        }

        Retention.schedule()
        ClipboardMonitor.shared.start()
        ShelfPanelController.shared.prewarm()
        Updater.shared.schedule()
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.buildMainMenu() }
        }
        if !Preferences.shared.didWelcome {
            // The shelf opens by itself with the welcome card; the card sets the flag when the user is done.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ShelfPanelController.shared.show() }
        }
    }

    @objc private func statusClicked() {
        // Right click, or control-click as everywhere else on the Mac, opens the menu.
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || (e?.type == .leftMouseUp && e?.modifierFlags.contains(.control) == true) {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            ShelfPanelController.shared.toggle()
        }
    }

    private func bindShortcuts() {
        let p = Preferences.shared
        var taken: [String] = []
        if !HotKeyCenter.shared.bind(p.shortcut(Preferences.Key.hotkeyCapture), name: "capture", action: {
            MainActor.assumeIsolated { CaptureCoordinator.shared.start() }
        }) { taken.append("截图".l + " " + p.shortcut(Preferences.Key.hotkeyCapture).display) }
        if !HotKeyCenter.shared.bind(p.shortcut(Preferences.Key.hotkeyShelf), name: "shelf", action: {
            MainActor.assumeIsolated { ShelfPanelController.shared.model.noteWelcomeTried("shelf"); ShelfPanelController.shared.toggle() }
        }) { taken.append("剪贴板".l + " " + p.shortcut(Preferences.Key.hotkeyShelf).display) }
        if !HotKeyCenter.shared.bind(p.shortcut(Preferences.Key.hotkeySearch), name: "search", action: {
            MainActor.assumeIsolated { ShelfPanelController.shared.showSearch() }
        }) { taken.append("搜索剪贴板".l + " " + p.shortcut(Preferences.Key.hotkeySearch).display) }
        NotificationCenter.default.post(name: .shortcutBindingChanged, object: nil)
        // During onboarding the welcome card shows the conflict inline next to the recorder; no extra dialog.
        guard !taken.isEmpty, Preferences.shared.didWelcome else { return }
        let alert = NSAlert()
        alert.messageText = "快捷键被其他应用占用".l
        alert.informativeText = taken.joined(separator: "、") + "\n\n另一个应用（常见是微信、飞书）已经注册了同样的组合键，系统只认先注册的那个。换一个组合键，或者去那个应用里改掉它的。".l
        alert.addButton(withTitle: "打开设置".l)
        alert.addButton(withTitle: "稍后".l)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { SettingsWindowController.shared.show() }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = Preferences.shared
        add(menu, "截图".l, #selector(menuCapture), hint: p.shortcut(Preferences.Key.hotkeyCapture))
        add(menu, ShelfPanelController.shared.isVisible ? "隐藏剪贴板".l : "显示剪贴板".l, #selector(menuShelf),
            hint: p.shortcut(Preferences.Key.hotkeyShelf))
        add(menu, "搜索剪贴板".l, #selector(menuSearch), hint: p.shortcut(Preferences.Key.hotkeySearch))
        menu.addItem(.separator())
        let pause = add(menu, "暂停记录剪贴板".l, #selector(menuTogglePause))
        pause.state = p.monitoringPaused ? .on : .off
        add(menu, "打开存储文件夹".l, #selector(menuOpenStore))
        menu.addItem(.separator())
        add(menu, "检查更新…".l, #selector(menuCheckUpdates))
        add(menu, "设置…".l, #selector(menuSettings), keyEquivalent: ",")
        add(menu, "退出 Pastory".l, #selector(menuQuit), keyEquivalent: "q")
    }

    /// Menu-bar apps get no menu for free; without an Edit menu, ⌘V/⌘C are dead in every text field.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 Pastory".l, action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑".l)
        edit.addItem(withTitle: "撤销".l, action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做".l, action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切".l, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝".l, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴".l, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选".l, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     hint: Shortcut? = nil, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty { item.keyEquivalentModifierMask = [.command] }
        if let hint, hint.isSet {
            let attr = NSMutableAttributedString(string: title)
            attr.append(NSAttributedString(string: "   \(hint.display)", attributes: [
                .foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 0)
            ]))
            item.attributedTitle = attr
        }
        menu.addItem(item)
        return item
    }

    @objc private func menuCapture() { CaptureCoordinator.shared.start() }
    @objc private func menuShelf() { ShelfPanelController.shared.toggle() }
    @objc private func menuSearch() { ShelfPanelController.shared.showSearch() }
    @objc private func menuTogglePause() { Preferences.shared.monitoringPaused.toggle() }
    @objc private func menuOpenStore() { NSWorkspace.shared.open(ClipStore.shared.root) }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuCheckUpdates() { Task { @MainActor in await Updater.shared.check(interactive: true) } }
    @objc private func menuQuit() {
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }
}
