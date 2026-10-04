import AppKit
import CharCore

@MainActor final class StatusBarController: NSObject {
    private unowned let runtime: CompanionRuntime
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var previous: AttentionSnapshot?
    private var previousSound: Bool?
    init(runtime: CompanionRuntime) {
        self.runtime = runtime
        super.init()
        item.button?.image = Self.faceIcon()
        item.button?.setAccessibilityLabel("Char 状态栏")
        refresh()
    }
    func refresh() {
        guard previous != runtime.snapshot || previousSound != runtime.settings.soundEnabled else { return }
        previous = runtime.snapshot; previousSound = runtime.settings.soundEnabled
        let menu = NSMenu()
        add("显示桌宠", action: #selector(showPet), to: menu)
        add("设置…", action: #selector(settings), to: menu)
        let home = add("回城 · Ctrl+B", action: #selector(returnHome), to: menu)
        home.isEnabled = runtime.snapshot.hold != nil && !runtime.busy
        add(runtime.settings.soundEnabled ? "静音提醒" : "取消静音", action: #selector(mute), to: menu)
        menu.addItem(.separator())
        add("退出 Char", action: #selector(quit), to: menu)
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
    private static func faceIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 14), xRadius: 4, yRadius: 4)
            body.lineWidth = 1.6; body.stroke()
            NSColor.black.setFill()
            for x in [6.0, 11.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 7, width: 1.6, height: 4.5), xRadius: 0.8, yRadius: 0.8).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }
}
