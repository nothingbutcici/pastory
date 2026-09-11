import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        if SelfTest.handleCommandLine() { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snip Clip")
        statusItem.button?.image?.isTemplate = true
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        bindShortcuts()
        NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bindShortcuts() }
        }

        Retention.schedule()
        ClipboardMonitor.shared.start()
        if !Permissions.hasScreenRecording { _ = Permissions.requestScreenRecording() }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            ShelfPanelController.shared.toggle()
        }
    }

    private func bindShortcuts() {
        let p = Preferences.shared
        HotKeyCenter.shared.bind(p.shortcut(Preferences.Key.hotkeyCapture), name: "capture") {
            MainActor.assumeIsolated { CaptureCoordinator.shared.start() }
        }
        HotKeyCenter.shared.bind(p.shortcut(Preferences.Key.hotkeyShelf), name: "shelf") {
            MainActor.assumeIsolated { ShelfPanelController.shared.toggle() }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = Preferences.shared
        add(menu, "截图", #selector(menuCapture), hint: p.shortcut(Preferences.Key.hotkeyCapture))
        add(menu, ShelfPanelController.shared.isVisible ? "隐藏剪贴板" : "显示剪贴板", #selector(menuShelf),
            hint: p.shortcut(Preferences.Key.hotkeyShelf))
        menu.addItem(.separator())
        let pause = add(menu, "暂停记录剪贴板", #selector(menuTogglePause))
        pause.state = p.monitoringPaused ? .on : .off
        add(menu, "打开存储文件夹", #selector(menuOpenStore))
        menu.addItem(.separator())
        add(menu, "设置…", #selector(menuSettings), keyEquivalent: ",")
        add(menu, "退出 Snip Clip", #selector(menuQuit), keyEquivalent: "q")
    }

    /// Menu-bar apps get no menu for free; without an Edit menu, ⌘V/⌘C are dead in every text field.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 Snip Clip", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
    @objc private func menuTogglePause() { Preferences.shared.monitoringPaused.toggle() }
    @objc private func menuOpenStore() { NSWorkspace.shared.open(ClipStore.shared.root) }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuQuit() {
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
    }
}
