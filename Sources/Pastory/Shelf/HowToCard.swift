import Foundation

/// 「Pastory 怎么用」: an ordinary pinned text card with the short manual, seeded once for every user (new or
/// upgrading). It behaves like any other card: searchable, editable, and gone for good once deleted.
enum HowToCard {
    @MainActor static func seedIfNeeded() {
        let p = Preferences.shared
        guard !p.didSeedHowTo else { return }
        p.didSeedHowTo = true
        let store = ClipStore.shared
        guard let item = store.insertText(L.isEnglish ? english : chinese, rtf: nil, source: CaptureCoordinator.source) else { return }
        store.setTitle(L.isEnglish ? "How to use Pastory" : "Pastory 怎么用", for: item.id)
        if !item.pinned { store.togglePin(item.id) }
    }

    static let chinese = """
1. 单击卡片：复制到剪贴板。
2. 双击卡片：直接粘贴进你刚才在用的应用（需要「辅助功能」权限）。
3. 把卡片向上拖出面板：固定到桌面任意位置，成为便签；便签上可以编辑、切换是否置顶、关闭。
4. Pin：Pin 住的内容永远不会被自动清理。
5. 自动清理：未 Pin 的内容默认永久保留；想定时清理，去 设置 › 清理 选保留天数和清理时刻。
6. 标题：选中卡片后点「加个标题」，方便辨认和搜索。
7. 搜索：面板打开时直接打字。正文、标题、来源应用、图片里识别出的文字都能搜到。
8. 截图 / 录屏：按截图快捷键，框选区域或点选窗口；顶部可切到录屏。截完直接标注、识别文字。
9. 这张卡片是普通卡片，看完可以删掉。
"""

    static let english = """
1. Click a card: copy it to the clipboard.
2. Double-click a card: paste it straight into the app you came from (needs Accessibility).
3. Drag a card up out of the shelf: stick it anywhere on the desktop as a note; a note can be edited, kept on top or on the desktop only, and closed.
4. Pin: pinned items are never cleaned up automatically.
5. Cleanup: unpinned items are kept forever by default; to clean on a schedule, choose the days and the hour in Settings › Cleanup.
6. Titles: select a card and click "add a title" to make it easy to spot and search.
7. Search: just type while the shelf is open. Text, titles, source apps and text recognized inside images are all searchable.
8. Screenshots and recording: press the screenshot shortcut, drag a region or click a window; switch to Record at the top. Annotate and recognize text right after.
9. This is an ordinary card. Delete it once you are done.
"""
}
