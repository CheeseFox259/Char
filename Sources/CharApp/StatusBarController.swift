import AppKit
import CharCore

@MainActor final class StatusBarController: NSObject {
    private unowned let runtime: CompanionRuntime
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var previous: AttentionSnapshot?
    private var previousSound: Bool?
    private var previousLanguage: AppLanguage?
    private var previousSkinID: String?
    var iconImage: NSImage? { item.button?.image }
    var representedSkinID: String? { previousSkinID }
    init(runtime: CompanionRuntime) {
        self.runtime = runtime
        super.init()
        item.button?.setAccessibilityLabel(runtime.localized("Char 状态栏", "Char menu bar"))
        refresh()
    }
    func refresh() {
        guard previous != runtime.snapshot || previousSound != runtime.settings.soundEnabled || previousLanguage != runtime.settings.language || previousSkinID != runtime.selectedSkinID else { return }
        if previousSkinID != runtime.selectedSkinID {
            let image = runtime.softwareIcon.copy() as! NSImage
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            item.button?.image = image
            previousSkinID = runtime.selectedSkinID
        }
        previous = runtime.snapshot; previousSound = runtime.settings.soundEnabled; previousLanguage = runtime.settings.language
        item.button?.setAccessibilityLabel(runtime.localized("Char 状态栏", "Char menu bar"))
        let menu = NSMenu()
        add(runtime.localized("显示桌宠", "Show pet"), action: #selector(showPet), to: menu)
        add(runtime.localized("设置…", "Settings…"), action: #selector(settings), to: menu)
        let home = add(runtime.localized("回城 · Ctrl+B", "Return · Ctrl+B"), action: #selector(returnHome), to: menu)
        home.isEnabled = runtime.snapshot.hold != nil && !runtime.busy
        add(runtime.settings.soundEnabled ? runtime.localized("静音提醒", "Mute notifications") : runtime.localized("取消静音", "Unmute notifications"), action: #selector(mute), to: menu)
        menu.addItem(.separator())
        add(runtime.localized("退出 Char", "Quit Char"), action: #selector(quit), to: menu)
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.toolTip = "Char"
    }
    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self; menu.addItem(row); return row
    }
    @objc private func showPet() { runtime.showPet() }
    @objc private func settings() { runtime.showSettings() }
    @objc private func returnHome() { runtime.returnHome() }
    @objc private func mute() { runtime.toggleMute() }
    @objc private func quit() { NSApp.terminate(nil) }
}
