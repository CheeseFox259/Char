import AppKit
import CharCore

@MainActor final class CompanionPanel: NSPanel {
    let surface: CompanionSurface
    init(runtime: CompanionRuntime) {
        surface = CompanionSurface(runtime: runtime)
        super.init(contentRect: NSRect(origin: .zero, size: CompanionGeometry.canvasSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; hidesOnDeactivate = false; isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if #available(macOS 14, *) { collectionBehavior.insert(.canJoinAllApplications) }
        contentView = surface
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func transition(to frame: NSRect, placement: PetPlacement, animated: Bool) {
        surface.transition(to: frame, placement: placement, animated: animated)
    }
}

@MainActor final class CompanionSurface: NSView {
    unowned let runtime: CompanionRuntime
    let pet: GraphicButton
    let buttons: [GraphicButton]
    private let overflow = NSView(frame: .zero)
    private var offset = 0
    private var clock: Timer?
    private let epoch = ProcessInfo.processInfo.systemUptime
    private var feedbackAt: TimeInterval?
    private struct Transition {
        let frame: NSRect
        let placement: PetPlacement
        let started: TimeInterval
        let reduced: Bool
        let initialAlpha: CGFloat
        let initialScale: CGFloat
        var arrived = false
    }
    private var movement: Transition?
    private var placement: PetPlacement = .desktop
    init(runtime: CompanionRuntime) {
        self.runtime = runtime
        pet = GraphicButton(kind: .pet, runtime: runtime)
        buttons = WorkEnd.allCases.map { GraphicButton(kind: .bubble($0), runtime: runtime) }
        super.init(frame: NSRect(origin: .zero, size: CompanionGeometry.canvasSize))
        addSubview(pet)
        addSubview(overflow)
        for button in buttons { addSubview(button) }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Agent orbit, scroll or use next and previous actions to cycle bubbles")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Next Agent bubbles", target: self, selector: #selector(nextBubbles)),
            NSAccessibilityCustomAction(name: "Previous Agent bubbles", target: self, selector: #selector(previousBubbles))])
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    func refresh() {
        placement = runtime.petPlacement
        layoutVisibleBubbles()
        pet.setAccessibilityLabel(runtime.snapshot.hold == nil ? "Char 桌宠，当前不可回城" : "回城，返回最初来源，Control+B\(runtime.snapshot.hold?.anchor.accuracy == .application ? "，应用级降级" : "")")
        for button in buttons {
            guard case let .bubble(end) = button.kind else { continue }
            let bubble = runtime.snapshot.bubbles.first { $0.workEnd == end }
            button.setAccessibilityLabel("\(end.title): \(bubble?.count ?? 0) unviewed, \(bubble?.runningCount ?? 0) running\(bubble?.head.map { ", \($0.reason.title)\($0.isPast ? ", past" : "")\($0.navigationOutcome == .fallback ? ", application fallback" : "")" } ?? "")")
            button.needsDisplay = true
        }
        pet.needsDisplay = true
        ensureClock()
    }
    private func layoutVisibleBubbles() {
        let visible = buttons.filter { button in
            guard case let .bubble(end) = button.kind else { return false }
            return runtime.snapshot.bubbles.contains { $0.workEnd == end }
        }
        buttons.forEach { $0.isHidden = true; $0.miniature = false }
        pet.placement = placement
        pet.frame = CompanionGeometry.petFrame(placement: placement)
        let slots = CompanionGeometry.layout(count: visible.count, offset: offset, placement: placement)
        overflow.isHidden = true
        for slot in slots {
            if let index = slot.primaryIndex {
                visible[index].frame = slot.frame; visible[index].isHidden = false
            } else {
                overflow.frame = slot.frame; overflow.isHidden = false
                for (index, frame) in zip(slot.overflowIndices, slot.miniFrames) {
                    visible[index].frame = frame; visible[index].miniature = true; visible[index].isHidden = false
                }
            }
        }
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for button in ([pet] + buttons).reversed() where !button.isHidden {
            let p = button.convert(local, from: self)
            if button.containsInteractivePoint(p) { return button }
        }
        if !overflow.isHidden && overflow.frame.contains(local) { return self }
        return nil
    }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0 {
            offset += event.scrollingDeltaY + event.scrollingDeltaX > 0 ? 1 : -1
            layoutVisibleBubbles()
        }
    }
    @objc private func nextBubbles() -> Bool { offset += 1; layoutVisibleBubbles(); return true }
    @objc private func previousBubbles() -> Bool { offset -= 1; layoutVisibleBubbles(); return true }
    func returnFeedback() { feedbackAt = ProcessInfo.processInfo.systemUptime; ensureClock() }
    func transition(to frame: NSRect, placement: PetPlacement, animated: Bool) {
        guard animated else {
            movement = nil; self.placement = placement; window?.alphaValue = 1
            window?.setFrame(frame, display: true); pet.motionScale = 1; layoutVisibleBubbles(); return
        }
        // Replacing this value interrupts both phases; there are no stale completion callbacks.
        movement = Transition(frame: frame, placement: placement, started: ProcessInfo.processInfo.systemUptime,
                              reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                              initialAlpha: window?.alphaValue ?? 1, initialScale: pet.motionScale)
        ensureClock()
    }
    private func ensureClock() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
    }
    private func animate() {
        let now = ProcessInfo.processInfo.systemUptime
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        pet.elapsed = reduce ? 0 : now - epoch
        pet.clip = "idle"
        pet.clipElapsed = pet.elapsed
        pet.feedbackElapsed = feedbackAt.map { now - $0 }
        if let feedbackAt, now - feedbackAt > 0.65 { self.feedbackAt = nil; pet.feedbackElapsed = nil }
        if var motion = movement {
            let duration = motion.reduced ? 0.16 : 0.5
            let t = min((now - motion.started) / duration, 1)
            pet.clip = t < 0.35 ? (placement == .desktop ? "depart" : "edgeHide") : (motion.placement == .desktop ? "arrive" : "edgePeek")
            pet.clipElapsed = now - motion.started
            if t < 0.35 {
                let phase = t / 0.35
                window?.alphaValue = motion.initialAlpha * (1 - phase * phase)
                pet.motionScale = motion.reduced ? 1 : motion.initialScale * (1 - 0.8 * phase * phase)
                pet.edgeRetraction = motion.reduced || placement == .desktop ? 0 : phase * 38
            } else {
                if !motion.arrived {
                    window?.setFrame(motion.frame, display: true)
                    placement = motion.placement; layoutVisibleBubbles(); motion.arrived = true
                }
                let phase = (t - 0.35) / 0.65
                window?.alphaValue = motion.reduced ? phase : min(1, phase * 3)
                pet.motionScale = motion.reduced ? 1 : CGFloat(0.2 + 0.8 * CompanionGeometry.arrivalProgress(phase))
                pet.edgeRetraction = motion.reduced || placement == .desktop ? 0 : CGFloat(38 * (1 - CompanionGeometry.arrivalProgress(phase)))
            }
            movement = t == 1 ? nil : motion
            if t == 1 { window?.alphaValue = 1; pet.motionScale = 1; pet.edgeRetraction = 0 }
        }
        // AppKit hitTest alone does not forward events through a transparent NSWindow.
        if let window {
            let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            window.ignoresMouseEvents = hitTest(local) == nil
        }
        pet.needsDisplay = true
        // Keep the single lightweight clock for pointer passthrough; Reduce Motion freezes drawing.
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !overflow.isHidden else { return }
        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: overflow.frame).fill()
        NSColor.white.withAlphaComponent(0.75).setStroke()
        NSBezierPath(ovalIn: overflow.frame.insetBy(dx: 1, dy: 1)).stroke()
        let count = max(0, runtime.snapshot.bubbles.count - 5)
        let style = NSMutableParagraphStyle(); style.alignment = .center
        "+\(count)".draw(in: NSRect(x: overflow.frame.midX - 11, y: overflow.frame.midY - 3, width: 22, height: 12),
                         withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold),
                                          .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
    }
}

@MainActor final class GraphicButton: NSButton {
    enum Kind { case pet, bubble(WorkEnd) }
    let kind: Kind
    unowned let runtime: CompanionRuntime
    var responding = false
    var miniature = false
    var elapsed: TimeInterval = 0
    var feedbackElapsed: TimeInterval?
    var motionScale: CGFloat = 1
    var edgeRetraction: CGFloat = 0
    var placement: PetPlacement = .desktop
    var clip = "idle"
    var clipElapsed: TimeInterval = 0
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        if case .pet = kind { return true }
        let x = (point.x - bounds.midX) / (bounds.width / 2)
        let y = (point.y - bounds.midY) / (bounds.height / 2)
        return x * x + y * y <= 1
    }
    override func scrollWheel(with event: NSEvent) { superview?.scrollWheel(with: event) }
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
                NSAccessibilityCustomAction(name: "结束回城", target: self, selector: #selector(accessibleEnd))])
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
        for (title, selector) in [("回城 (Ctrl+B)", #selector(homeAction)), ("Settings…", #selector(settingsAction)),
                                  (runtime.settings.soundEnabled ? "Mute" : "Unmute", #selector(muteAction)),
                                  ("结束回城", #selector(endAction)), ("Quit Char", #selector(quitAction))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self
            if selector == #selector(endAction) || selector == #selector(homeAction) { item.isEnabled = runtime.snapshot.hold != nil }
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
    @objc private func homeAction() { runtime.returnHome() }
    @objc private func settingsAction() { runtime.showSettings() }
    @objc private func muteAction() { runtime.toggleMute() }
    @objc private func endAction() { runtime.endHold() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    override func draw(_ dirtyRect: NSRect) {
        switch kind { case .pet: drawPet(); case let .bubble(end): drawBubble(end) }
    }
    private func drawPet() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pulse = reduce ? 0 : sin(elapsed * 1.7)
        let idlePhase = elapsed.truncatingRemainder(dividingBy: 7)
        let idleBounce = reduce || idlePhase > 1.2 ? 0 : sin(.pi * idlePhase / 1.2) * exp(-2 * idlePhase) * sin(12 * idlePhase)
        let feedback = reduce ? 0 : feedbackElapsed.map { exp(-8 * $0) * sin(22 * $0) } ?? 0
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 38, yBy: 38)
        switch placement {
        case .left: transform.translateX(by: -edgeRetraction, yBy: 0)
        case .right: transform.translateX(by: edgeRetraction, yBy: 0)
        case .top: transform.translateX(by: 0, yBy: edgeRetraction)
        case .bottom: transform.translateX(by: 0, yBy: -edgeRetraction)
        case .desktop: break
        }
        transform.rotate(byDegrees: CGFloat(reduce ? 0 : sin(elapsed * 0.8) * 2 + feedback * 7))
        transform.scaleX(by: motionScale * CGFloat(1 + pulse * 0.018 + idleBounce * 0.07 + feedback * 0.1),
                         yBy: motionScale * CGFloat(1 - pulse * 0.025 - idleBounce * 0.07 - feedback * 0.1))
        transform.translateX(by: -38, yBy: -38 + CGFloat(pulse * 1.8 + idleBounce * 6))
        transform.concat()
        if let image = runtime.customPetImage(clip: feedbackElapsed == nil ? clip : "return", elapsed: feedbackElapsed ?? clipElapsed) {
            image.draw(in: bounds)
        } else {
            let ink = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1)
            let cream = NSColor(calibratedRed: 1, green: 0.97, blue: 0.87, alpha: 1)
            let body = NSBezierPath(roundedRect: NSRect(x: 7, y: 13, width: 62, height: 58), xRadius: 20, yRadius: 20)
            cream.setFill(); body.fill(); ink.setStroke(); body.lineWidth = 3.5; body.stroke()
            for x in [21.0, 54.0] {
                let foot = NSBezierPath(ovalIn: NSRect(x: x - 7, y: 7, width: 17, height: 15))
                cream.setFill(); foot.fill(); ink.setStroke(); foot.lineWidth = 2.5; foot.stroke()
            }
            ink.setFill()
            let blink = !reduce && elapsed.truncatingRemainder(dividingBy: 5.2) > 5.04
            for x in [27.0, 46.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: blink || responding ? 35 : 31,
                                               width: 4, height: blink || responding ? 3 : 12), xRadius: 2, yRadius: 2).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
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
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let hue = CGFloat(WorkEnd.allCases.firstIndex(of: end) ?? 0) / CGFloat(WorkEnd.allCases.count)
        let tint = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.9, alpha: 1)
        let path = NSBezierPath(ovalIn: rect)
        NSGradient(starting: tint.withAlphaComponent(0.35), ending: tint.withAlphaComponent(0.88))?.draw(in: path, angle: -70)
        tint.setStroke(); path.lineWidth = 1.5; path.stroke()
        NSColor.white.withAlphaComponent(0.78).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width * 0.17, y: bounds.height * 0.69,
                                  width: bounds.width * 0.27, height: bounds.height * 0.12)).fill()
        let iconRect = bounds.insetBy(dx: miniature ? 5 : 12, dy: miniature ? 5 : 12)
        if let icon = runtime.agentIcon(for: end) { icon.draw(in: iconRect) }
        else { symbol(end.symbol, in: iconRect, color: .white) }
        guard !miniature else { return }
        if let head = bubble.head {
            symbol(head.reason.symbol, in: NSRect(x: 3, y: 2, width: 15, height: 15), color: .labelColor)
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 35, y: 34, width: 17, height: 17)).fill()
            number(bubble.count, rect: NSRect(x: 35, y: 35, width: 17, height: 15), color: .black, size: 11)
            if head.isPast { symbol("clock.arrow.circlepath", in: NSRect(x: 21, y: 1, width: 12, height: 12), color: .labelColor) }
            if head.navigationOutcome == .fallback { symbol("arrow.triangle.turn.up.right.diamond.fill", in: NSRect(x: 37, y: 1, width: 13, height: 13), color: .systemOrange) }
        }
        if bubble.runningCount > 0 { number(bubble.runningCount, rect: NSRect(x: 35, y: 17, width: 17, height: 12), color: .black, size: 9) }
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
    var title: String { switch self { case .claudeCode: return "Claude Code"; case .codexCLI: return "Codex CLI"; case .codexDesktop: return "Codex Desktop"; case .deepseekDesktop: return "DeepSeek Harness"; case .kimiCLI: return "Kimi Code CLI"; case .kimiDesktop: return "Kimi Code Desktop"; case .pi: return "pi" } }
    var symbol: String { switch self { case .claudeCode: return "terminal.fill"; case .codexCLI: return "chevron.left.forwardslash.chevron.right"; case .codexDesktop: return "macwindow"; case .deepseekDesktop: return "bolt.horizontal.circle.fill"; case .kimiCLI: return "keyboard.fill"; case .kimiDesktop: return "square.grid.2x2.fill"; case .pi: return "circle.grid.2x2.fill" } }
}
extension StopReason {
    var title: String { switch self { case .question: return "Question"; case .approval: return "Approval"; case .turnEnded: return "Turn ended"; case .failure: return "Failure"; case .rateLimit: return "Rate limit"; case .contextExhausted: return "Context exhausted"; case .unclassified: return "Unclassified stop" } }
    var symbol: String { switch self { case .question: return "questionmark.bubble.fill"; case .approval: return "hand.raised.fill"; case .turnEnded: return "checkmark.circle.fill"; case .failure: return "exclamationmark.triangle.fill"; case .rateLimit: return "hourglass"; case .contextExhausted: return "rectangle.stack.badge.minus"; case .unclassified: return "pause.circle.fill" } }
}
