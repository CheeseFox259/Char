import AppKit
import CharCore

@MainActor private enum BubbleDrawing {
    static func raster(size: NSSize, draw: () -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                  pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size); image.addRepresentation(rep); return image
    }
    static func pose(in rect: NSRect, elapsed: TimeInterval) {
        let wobble = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : sin(elapsed * 1.2) * sin(elapsed * 0.37)
        let pose = NSAffineTransform()
        pose.translateX(by: rect.midX, yBy: rect.midY)
        pose.rotate(byDegrees: CGFloat(wobble * 2.5))
        pose.scaleX(by: CGFloat(1 + wobble * 0.035), yBy: CGFloat(1 - wobble * 0.035))
        pose.translateX(by: -rect.midX, yBy: -rect.midY)
        pose.concat()
    }
    static func shell(in bounds: NSRect, tint: NSColor) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: rect)
        NSGradient(starting: tint.withAlphaComponent(0.35), ending: tint.withAlphaComponent(0.88))?.draw(in: path, angle: -70)
        tint.setStroke(); path.lineWidth = 1.5; path.stroke()
        NSColor.white.withAlphaComponent(0.78).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.69,
                                  width: rect.width * 0.27, height: rect.height * 0.12)).fill()
    }
}

@MainActor final class CompanionPanel: NSPanel {
    let surface: CompanionSurface
    init(runtime: CompanionRuntime) {
        surface = CompanionSurface(runtime: runtime)
        super.init(contentRect: NSRect(origin: .zero, size: CompanionGeometry.canvasSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; hidesOnDeactivate = false; isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if #available(macOS 14, *) {
            collectionBehavior.remove(.fullScreenAuxiliary)
            collectionBehavior.insert(.canJoinAllApplications)
        }
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
    private var overflowArtwork: NSImage?
    private var overflowCount = -1
    private var lastReduced: Bool?
    private var clock: Timer?
    private let epoch = ProcessInfo.processInfo.systemUptime
    private var feedbackAt: TimeInterval?
    private struct Transition {
        let frame: NSRect
        let placement: PetPlacement
        let started: TimeInterval
        let reduced: Bool
        let playback: CompanionPlayback
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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Agent orbit, scroll or use next and previous actions to cycle bubbles")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Next Agent bubbles", target: self, selector: #selector(nextBubbles)),
            NSAccessibilityCustomAction(name: "Previous Agent bubbles", target: self, selector: #selector(previousBubbles))])
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    func refresh() {
        if movement == nil { placement = runtime.petPlacement }
        layoutVisibleBubbles()
        pet.setAccessibilityLabel(runtime.snapshot.hold == nil ? "Char 桌宠，当前不可回城" : "回城，返回最初来源，Control+B\(runtime.snapshot.hold?.anchor.accuracy == .application ? "，应用级降级" : "")")
        for button in buttons {
            guard case let .bubble(end) = button.kind else { continue }
            let bubble = runtime.snapshot.bubbles.first { $0.workEnd == end }
            button.setAccessibilityLabel("\(end.title): \(bubble?.count ?? 0) unviewed, \(bubble?.runningCount ?? 0) running\(bubble?.head.map { ", \($0.reason.title)\($0.isPast ? ", past" : "")\($0.navigationOutcome == .fallback ? ", application fallback" : "")" } ?? "")")
            button.refreshArtwork()
            button.needsDisplay = true
        }
        let count = max(0, runtime.snapshot.bubbles.count - 5)
        if overflowCount != count { overflowCount = count; overflowArtwork = nil }
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
        for button in buttons where !button.isHidden { button.refreshArtwork() }
        setAccessibilityChildren([pet] + buttons.filter { !$0.isHidden })
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
    @objc fileprivate func nextBubbles() -> Bool { offset += 1; layoutVisibleBubbles(); return true }
    @objc fileprivate func previousBubbles() -> Bool { offset -= 1; layoutVisibleBubbles(); return true }
    func returnFeedback() { pet.feedbackClip = "return"; feedbackAt = ProcessInfo.processInfo.systemUptime; ensureClock() }
    func pressFeedback() { pet.feedbackClip = "press"; feedbackAt = ProcessInfo.processInfo.systemUptime; ensureClock() }
    func transition(to frame: NSRect, placement: PetPlacement, animated: Bool) {
        guard animated else {
            movement = nil; self.placement = placement; window?.alphaValue = 1
            window?.setFrame(frame, display: true); pet.motionScale = 1; layoutVisibleBubbles(); return
        }
        // Replacing this value interrupts both phases; there are no stale completion callbacks.
        movement = Transition(frame: frame, placement: placement, started: ProcessInfo.processInfo.systemUptime,
                              reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                              playback: CompanionPlayback(departure: runtime.customPetClipDuration(clip: self.placement == .desktop ? "depart" : "edgeHide"),
                                                          arrival: runtime.customPetClipDuration(clip: placement == .desktop ? "arrive" : "edgePeek")),
                              initialAlpha: window?.alphaValue ?? 1, initialScale: pet.motionScale)
        ensureClock()
    }
    private func ensureClock() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        if let clock { RunLoop.main.add(clock, forMode: .common) }
    }
    private func animate() {
        let now = ProcessInfo.processInfo.systemUptime
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasAnimating = movement != nil || feedbackAt != nil
        pet.elapsed = reduce ? 0 : now - epoch
        pet.clip = "idle"
        pet.clipElapsed = pet.elapsed
        pet.feedbackElapsed = feedbackAt.map { reduce ? 0 : now - $0 }
        if let feedbackAt, now - feedbackAt > (runtime.customPetClipDuration(clip: pet.feedbackClip) ?? 0.65) { self.feedbackAt = nil; pet.feedbackElapsed = nil }
        if var motion = movement {
            // A placement transition interrupts feedback; its authored departure/arrival wins.
            feedbackAt = nil; pet.feedbackElapsed = nil
            let elapsed = now - motion.started
            let playback = motion.reduced ? CompanionPlayback(departure: 0.056, arrival: 0.104) : motion.playback
            let arriving = playback.isArriving(at: elapsed)
            let phase = playback.progress(at: elapsed)
            let t = min(elapsed / playback.duration, 1)
            pet.clip = arriving ? (motion.placement == .desktop ? "arrive" : "edgePeek") : (placement == .desktop ? "depart" : "edgeHide")
            pet.clipElapsed = reduce ? 0 : playback.clipElapsed(at: elapsed)
            if !arriving {
                window?.alphaValue = motion.initialAlpha * (1 - phase * phase)
                pet.motionScale = motion.reduced || placement != .desktop ? 1 : motion.initialScale * (1 - 0.8 * phase * phase)
                pet.edgeRetraction = motion.reduced || placement == .desktop ? 0 : phase * 38
            } else {
                if !motion.arrived {
                    window?.setFrame(motion.frame, display: true)
                    placement = motion.placement; layoutVisibleBubbles(); motion.arrived = true
                }
                window?.alphaValue = motion.reduced ? phase : min(1, phase * 3)
                pet.motionScale = motion.reduced || placement != .desktop ? 1 : CGFloat(0.2 + 0.8 * CompanionGeometry.arrivalProgress(phase))
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
        let redraw = !reduce || lastReduced != reduce || wasAnimating
        if redraw {
            pet.needsDisplay = true
            for button in buttons where !button.isHidden {
                button.elapsed = reduce ? 0 : now - epoch
                button.needsDisplay = true
            }
            if !overflow.isHidden { needsDisplay = true }
        }
        lastReduced = reduce
        // Keep the single lightweight clock for pointer passthrough; Reduce Motion freezes drawing.
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !overflow.isHidden else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        BubbleDrawing.pose(in: overflow.frame, elapsed: ProcessInfo.processInfo.systemUptime - epoch)
        if overflowArtwork == nil {
            overflowArtwork = BubbleDrawing.raster(size: overflow.frame.size) {
                let rect = NSRect(origin: .zero, size: overflow.frame.size)
                BubbleDrawing.shell(in: rect, tint: .systemBlue)
                let style = NSMutableParagraphStyle(); style.alignment = .center
                "+\(overflowCount)".draw(in: NSRect(x: rect.midX - 11, y: rect.midY - 3, width: 22, height: 12),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold),
                                                         .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
            }
        }
        overflowArtwork?.draw(in: overflow.frame)
    }
}

@MainActor final class GraphicButton: NSButton {
    // All vector and manifest-anchor geometry uses AppKit's bottom-left coordinates.
    override var isFlipped: Bool { false }
    enum Kind { case pet, bubble(WorkEnd) }
    let kind: Kind
    unowned let runtime: CompanionRuntime
    private struct ArtworkKey: Equatable {
        let bubble: AttentionBubble?
        let icon: ObjectIdentifier?
        let miniature: Bool
        let size: NSSize
    }
    private var artworkKey: ArtworkKey?
    private var artwork: NSImage?
    private var sourceIconBundle: String?
    private var sourceIcon: NSImage?
    private var symbolImages: [String: NSImage] = [:]
    func refreshArtwork() {
        guard case let .bubble(end) = kind else { return }
        let next = ArtworkKey(bubble: runtime.snapshot.bubbles.first { $0.workEnd == end },
                              icon: runtime.agentIcon(for: end).map(ObjectIdentifier.init), miniature: miniature, size: bounds.size)
        if next != artworkKey { artworkKey = next; artwork = nil }
    }
    var responding = false
    var miniature = false
    var elapsed: TimeInterval = 0
    var feedbackElapsed: TimeInterval?
    var feedbackClip = "return"
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
        switch kind {
        case .pet:
            if runtime.snapshot.hold == nil { (superview as? CompanionSurface)?.pressFeedback() }
            runtime.petClicked()
        case let .bubble(end): runtime.visit(end)
        }
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
        if let surface = superview as? CompanionSurface {
            menu.addItem(.separator())
            for (title, selector) in [("下一组气泡", #selector(CompanionSurface.nextBubbles)),
                                      ("上一组气泡", #selector(CompanionSurface.previousBubbles))] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = surface; menu.addItem(item)
            }
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
        let imageClip = feedbackElapsed == nil ? clip : feedbackClip
        let custom = runtime.customPetImage(clip: imageClip, elapsed: feedbackElapsed ?? clipElapsed)
        // The manifest anchor lands at the stable pet center and is the deformation pivot.
        let anchor = NSPoint(x: bounds.midX, y: bounds.midY)
        transform.translateX(by: anchor.x, yBy: anchor.y)
        switch placement {
        case .left: transform.translateX(by: -edgeRetraction, yBy: 0)
        case .right: transform.translateX(by: edgeRetraction, yBy: 0)
        case .top: transform.translateX(by: 0, yBy: edgeRetraction)
        case .bottom: transform.translateX(by: 0, yBy: -edgeRetraction)
        case .desktop: break
        }
        transform.rotate(byDegrees: CGFloat(reduce ? 0 : sin(elapsed * 0.8) * 3.5 + idleBounce * 8 + feedback * 7))
        transform.scaleX(by: motionScale * CGFloat(1 + pulse * 0.018 + idleBounce * 0.28 + feedback * 0.1),
                         yBy: motionScale * CGFloat(1 - pulse * 0.025 - idleBounce * 0.28 - feedback * 0.1))
        transform.translateX(by: -anchor.x, yBy: -anchor.y + CGFloat(pulse * 1.8 + idleBounce * 12))
        transform.concat()
        if let image = custom {
            let size = runtime.customPetSize
            NSGraphicsContext.saveGraphicsState()
            if imageClip == "edgeHide" || imageClip == "edgePeek" {
                let orientation = NSAffineTransform()
                orientation.translateX(by: anchor.x, yBy: anchor.y)
                orientation.rotate(byDegrees: CGFloat(CompanionPlayback.edgeRotation(placement: placement)))
                orientation.translateX(by: -anchor.x, yBy: -anchor.y)
                orientation.concat()
            }
            image.draw(in: NSRect(x: anchor.x - runtime.customPetAnchor.x * size.width,
                                  y: anchor.y - runtime.customPetAnchor.y * size.height,
                                  width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
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
            if sourceIconBundle != anchor.bundleIdentifier {
                sourceIconBundle = anchor.bundleIdentifier
                sourceIcon = runtime.demo ? NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)
                    : NSWorkspace.shared.urlForApplication(withBundleIdentifier: anchor.bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
            sourceIcon?.draw(in: NSRect(x: 54, y: 11, width: 17, height: 17))
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
        if artwork == nil {
            artwork = BubbleDrawing.raster(size: bounds.size) { drawBubbleContent(end) }
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let phase = elapsed + Double(WorkEnd.allCases.firstIndex(of: end) ?? 0) * 0.7
        BubbleDrawing.pose(in: bounds, elapsed: phase)
        artwork?.draw(in: bounds)
    }
    private func drawBubbleContent(_ end: WorkEnd) {
        guard let bubble = runtime.snapshot.bubbles.first(where: { $0.workEnd == end }) else { return }
        let hue = CGFloat(WorkEnd.allCases.firstIndex(of: end) ?? 0) / CGFloat(WorkEnd.allCases.count)
        let tint = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.9, alpha: 1)
        BubbleDrawing.shell(in: bounds, tint: tint)
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
        let key = "\(name)/\(rect.height)/\(color.description)"
        if symbolImages[key] == nil {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: rect.height, weight: .semibold)) else { return }
            let tinted = NSImage(size: image.size)
            tinted.lockFocus(); image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            color.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); tinted.unlockFocus()
            symbolImages[key] = tinted
        }
        symbolImages[key]?.draw(in: rect)
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
