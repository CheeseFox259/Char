import AppKit
import CharCore

@MainActor final class CompanionPanel: NSPanel {
    let surface: CompanionSurface
    init(runtime: CompanionRuntime) {
        surface = CompanionSurface(runtime: runtime)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 290, height: 96),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; hidesOnDeactivate = false; isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = surface
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class CompanionSurface: NSView {
    unowned let runtime: CompanionRuntime
    let pet: GraphicButton
    let buttons: [GraphicButton]
    init(runtime: CompanionRuntime) {
        self.runtime = runtime
        pet = GraphicButton(kind: .pet, runtime: runtime)
        buttons = WorkEnd.allCases.map { GraphicButton(kind: .bubble($0), runtime: runtime) }
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 96))
        pet.frame = NSRect(x: 0, y: 10, width: 76, height: 76)
        addSubview(pet)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 82 + index * 68, y: 17, width: 62, height: 62)
            addSubview(button)
        }
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    func refresh() {
        pet.setAccessibilityLabel(runtime.snapshot.hold == nil ? "Char companion, no return saved" : "Return to saved source\(runtime.snapshot.hold?.anchor.accuracy == .application ? ", application fallback" : "")")
        pet.needsDisplay = true
        for button in buttons {
            guard case let .bubble(end) = button.kind else { continue }
            let bubble = runtime.snapshot.bubbles.first { $0.workEnd == end }
            button.isHidden = bubble == nil
            button.setAccessibilityLabel("\(end.title): \(bubble?.count ?? 0) unviewed, \(bubble?.runningCount ?? 0) running\(bubble?.head.map { ", \($0.reason.title)\($0.isPast ? ", past" : "")\($0.navigationOutcome == .fallback ? ", application fallback" : "")" } ?? "")")
            button.needsDisplay = true
        }
    }
}

@MainActor final class GraphicButton: NSButton {
    enum Kind { case pet, bubble(WorkEnd) }
    let kind: Kind
    unowned let runtime: CompanionRuntime
    var responding = false
    private var dragStart: NSPoint?
    private var initialOrigin: NSPoint?
    private var didDrag = false
    init(kind: Kind, runtime: CompanionRuntime) {
        self.kind = kind; self.runtime = runtime
        super.init(frame: .zero)
        isBordered = false; title = ""; target = self; action = #selector(performClickAction)
        setAccessibilityRole(.button)
        switch kind {
        case .pet:
            setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Open Settings", target: self, selector: #selector(accessibleSettings)),
                NSAccessibilityCustomAction(name: "Toggle Mute", target: self, selector: #selector(accessibleMute)),
                NSAccessibilityCustomAction(name: "End Hold", target: self, selector: #selector(accessibleEnd))])
        case .bubble:
            setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Ignore first attention item", target: self, selector: #selector(accessibleIgnore))])
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func performClickAction() {
        switch kind { case .pet: runtime.petClicked(); case let .bubble(end): runtime.visit(end) }
    }
    override func mouseDown(with event: NSEvent) {
        if case .pet = kind {
            dragStart = NSEvent.mouseLocation; initialOrigin = window?.frame.origin; didDrag = false
        } else { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard case .pet = kind, let start = dragStart, let origin = initialOrigin else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        if abs(dx) + abs(dy) > 3 { didDrag = true }
        if didDrag { window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        guard case .pet = kind else { super.mouseUp(with: event); return }
        if didDrag { runtime.saveDraggedPosition() } else { performClickAction() }
        dragStart = nil; initialOrigin = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        if case let .bubble(end) = kind { runtime.ignore(end); return }
        let menu = NSMenu()
        for (title, selector) in [("Settings…", #selector(settingsAction)),
                                  (runtime.settings.soundEnabled ? "Mute" : "Unmute", #selector(muteAction)),
                                  ("End Hold", #selector(endAction)), ("Quit Char", #selector(quitAction))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self
            if selector == #selector(endAction) { item.isEnabled = runtime.snapshot.hold != nil }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func accessibleSettings() -> Bool { runtime.showSettings(); return true }
    @objc private func accessibleMute() -> Bool { runtime.toggleMute(); return true }
    @objc private func accessibleEnd() -> Bool { runtime.endHold(); return true }
    @objc private func accessibleIgnore() -> Bool {
        if case let .bubble(end) = kind { runtime.ignore(end); return true }
        return false
    }
    @objc private func settingsAction() { runtime.showSettings() }
    @objc private func muteAction() { runtime.toggleMute() }
    @objc private func endAction() { runtime.endHold() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    override func draw(_ dirtyRect: NSRect) {
        switch kind { case .pet: drawPet(); case let .bubble(end): drawBubble(end) }
    }
    private func drawPet() {
        let shift: CGFloat = responding && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 3 : 0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 13, y: 23 + shift))
        path.curve(to: NSPoint(x: 8, y: 44 + shift), controlPoint1: NSPoint(x: 6, y: 26 + shift), controlPoint2: NSPoint(x: 4, y: 37 + shift))
        path.curve(to: NSPoint(x: 27, y: 64 + shift), controlPoint1: NSPoint(x: 12, y: 52 + shift), controlPoint2: NSPoint(x: 19, y: 48 + shift))
        path.curve(to: NSPoint(x: 37, y: 57 + shift), controlPoint1: NSPoint(x: 30, y: 72 + shift), controlPoint2: NSPoint(x: 34, y: 65 + shift))
        path.curve(to: NSPoint(x: 57, y: 51 + shift), controlPoint1: NSPoint(x: 43, y: 69 + shift), controlPoint2: NSPoint(x: 60, y: 63 + shift))
        path.curve(to: NSPoint(x: 64, y: 24 + shift), controlPoint1: NSPoint(x: 70, y: 43 + shift), controlPoint2: NSPoint(x: 72, y: 31 + shift))
        path.curve(to: NSPoint(x: 13, y: 23 + shift), controlPoint1: NSPoint(x: 53, y: 8 + shift), controlPoint2: NSPoint(x: 25, y: 8 + shift))
        path.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
        NSColor(calibratedRed: 0.12, green: 0.78, blue: 0.72, alpha: 1).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.02, green: 0.20, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 19, y: 26 + shift, width: 37, height: 23), xRadius: 11, yRadius: 11).fill()
        NSColor(calibratedRed: 0.87, green: 1, blue: 0.98, alpha: 1).setFill()
        for x in [29.0, 44.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 33 + shift, width: 4, height: responding ? 3 : 7), xRadius: 2, yRadius: 2).fill() }
        if let anchor = runtime.sourceBadgeAnchor {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(runtime.sourceBadgeOpacity)
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 51, y: 8, width: 23, height: 23)).fill()
            let icon = runtime.demo ? NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: anchor.bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
            icon?.draw(in: NSRect(x: 54, y: 11, width: 17, height: 17))
            if anchor.accuracy == .application { symbol("arrow.triangle.turn.up.right.diamond.fill", in: NSRect(x: 5, y: 8, width: 16, height: 16), color: .systemOrange) }
            NSGraphicsContext.restoreGraphicsState()
        }
        if runtime.snapshot.navigationFeedback == .fallback {
            symbol("arrow.triangle.turn.up.right.diamond.fill", in: NSRect(x: 55, y: 53, width: 18, height: 18), color: .systemOrange)
        } else if runtime.snapshot.navigationFeedback == .unavailable {
            symbol("exclamationmark.circle.fill", in: NSRect(x: 55, y: 53, width: 18, height: 18), color: .systemRed)
        }
    }
    private func drawBubble(_ end: WorkEnd) {
        guard let bubble = runtime.snapshot.bubbles.first(where: { $0.workEnd == end }) else { return }
        let rect = NSRect(x: 2, y: 5, width: 58, height: 52)
        let active = bubble.count > 0
        NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.17, alpha: active ? 0.96 : 0.74).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16); outline.lineWidth = 1; outline.stroke()
        symbol(end.symbol, in: NSRect(x: 10, y: 31, width: 16, height: 16), color: .white.withAlphaComponent(0.8))
        if let head = bubble.head {
            symbol(head.reason.symbol, in: NSRect(x: 12, y: 12, width: 16, height: 16), color: .systemMint)
            number(bubble.count, rect: NSRect(x: 32, y: 24, width: 24, height: 25), color: .white, size: 21)
            if head.isPast { symbol("clock.arrow.circlepath", in: NSRect(x: 35, y: 10, width: 11, height: 11), color: .white.withAlphaComponent(0.8)) }
            if head.navigationOutcome == .fallback { symbol("arrow.triangle.turn.up.right.diamond.fill", in: NSRect(x: 48, y: 10, width: 11, height: 11), color: .systemOrange) }
        } else { number(bubble.runningCount, rect: NSRect(x: 31, y: 20, width: 24, height: 25), color: .white.withAlphaComponent(0.65), size: 17) }
        if active && bubble.runningCount > 0 { number(bubble.runningCount, rect: NSRect(x: 44, y: 47, width: 16, height: 12), color: .systemMint, size: 9) }
    }
    private func symbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: rect.height, weight: .semibold)) else { return }
        let tinted = NSImage(size: image.size)
        tinted.lockFocus(); image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); tinted.unlockFocus()
        tinted.draw(in: rect)
    }
    private func number(_ value: Int, rect: NSRect, color: NSColor, size: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        String(value).draw(in: rect, withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold), .foregroundColor: color, .paragraphStyle: style])
    }
}

extension WorkEnd {
    var title: String { switch self { case .claudeCode: return "Claude Code"; case .codexCLI: return "Codex CLI"; case .codexDesktop: return "Codex Desktop" } }
    var symbol: String { switch self { case .claudeCode: return "terminal.fill"; case .codexCLI: return "chevron.left.forwardslash.chevron.right"; case .codexDesktop: return "macwindow" } }
}
extension StopReason {
    var title: String { switch self { case .question: return "Question"; case .approval: return "Approval"; case .turnEnded: return "Turn ended"; case .failure: return "Failure"; case .rateLimit: return "Rate limit"; case .contextExhausted: return "Context exhausted"; case .unclassified: return "Unclassified stop" } }
    var symbol: String { switch self { case .question: return "questionmark.bubble.fill"; case .approval: return "hand.raised.fill"; case .turnEnded: return "checkmark.circle.fill"; case .failure: return "exclamationmark.triangle.fill"; case .rateLimit: return "hourglass"; case .contextExhausted: return "rectangle.stack.badge.minus"; case .unclassified: return "pause.circle.fill" } }
}
