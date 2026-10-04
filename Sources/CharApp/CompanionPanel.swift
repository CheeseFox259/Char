import AppKit
import QuartzCore
import CharCore

@MainActor private enum BubbleDrawing {
    static func raster(size: NSSize, draw: () -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                  pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.current = previousContext
        }
        // rep.size establishes the logical-to-pixel CTM (2×); do not scale twice.
        NSGraphicsContext.current?.cgContext.clear(CGRect(origin: .zero, size: size))
        draw()
        let image = NSImage(size: size); image.addRepresentation(rep); return image
    }
    static func shell(in bounds: NSRect, tint: NSColor) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: rect)
        NSGradient(starting: NSColor.white.withAlphaComponent(0.08), ending: NSColor(calibratedWhite: 0.88, alpha: 0.26))?.draw(in: path, angle: -70)
        NSColor(calibratedRed: 0.60, green: 0.70, blue: 0.78, alpha: 0.65).setStroke(); path.lineWidth = 1.2; path.stroke()
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
        level = .statusBar; hidesOnDeactivate = false; isMovableByWindowBackground = false
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
    private let overflow = CALayer()
    private struct LayoutKey: Equatable {
        let ends: [WorkEnd]
        let offset: Int
        let placement: PetPlacement
        let petSize: Double
        let distance: Double
    }
    private var lastLayout: LayoutKey?
    private var offset = 0
    private var orbitUntil: TimeInterval = 0
    private var lastOrbitActive = false
    var orbitOffset: Int { offset }
    var isClockRunning: Bool { clock != nil }
    private var scrollPolicy = CompanionScrollPolicy()
    private var spaceAt: TimeInterval?
    private var pendingSpaceFeedback = false
    private var spaceLifecycle = CompanionSpaceLifecycle()
    private var occlusionObserver: NSObjectProtocol?
    private var lastPointer: NSPoint?
    var capacity: Int { CompanionGeometry.capacity(placement: placement, petSize: runtime.petSize, bubbleDistance: runtime.bubbleDistance) }
    var canCycle: Bool { runtime.snapshot.bubbles.count > capacity }
    var reducesMotionForDiagnostics: Bool { reducedMotion }
    var isSpaceFeedbackActive: Bool { spaceAt != nil || pendingSpaceFeedback }
    private(set) var visualOpacity: CGFloat = 1
    private var overflowArtwork: NSImage?
    private var overflowCount = -1
    private var lastReduced: Bool?
    private var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    private var displayOptionsObserver: NSObjectProtocol?
    private var clock: Timer?
    private let epoch = ProcessInfo.processInfo.systemUptime
    private var feedbackAt: TimeInterval?
    private struct Transition {
        let frame: NSRect
        let placement: PetPlacement
        let started: TimeInterval
        let reduced: Bool
        let playback: CompanionPlayback
        let initialOpacity: CGFloat
        let initialScale: CGFloat
        var arrived = false
    }
    private var movement: Transition?
    private var placement: PetPlacement = .desktop
    // [DEBUG-char-wheel-deep] Temporary display-ownership A/B. Host contains only layers.
    let usesHostedScene = ProcessInfo.processInfo.environment["CHAR_HOSTED_SCENE"] == "1"
    private(set) var sceneHost: NSView?
    var sceneLayer: CALayer? { sceneHost?.layer ?? layer }
    var hostedSceneInvariant: Bool {
        guard usesHostedScene else { return true }
        guard let sceneHost, let sceneLayer, sceneHost.superview === self,
              sceneHost.subviews.isEmpty, !wantsLayer else { return false }
        return ([pet] + buttons).allSatisfy { $0.superview === self && !$0.wantsLayer && $0.graphicLayer.superlayer === sceneLayer }
            && overflow.superlayer === sceneLayer
    }
    init(runtime: CompanionRuntime) {
        self.runtime = runtime
        pet = GraphicButton(kind: .pet, runtime: runtime)
        buttons = WorkEnd.allCases.map { GraphicButton(kind: .bubble($0), runtime: runtime) }
        super.init(frame: NSRect(origin: .zero, size: CompanionGeometry.canvasSize))
        if usesHostedScene {
            let host = NSView(frame: bounds)
            let owned = CALayer(); owned.anchorPoint = .zero; owned.frame = bounds
            // AppKit's documented layer-hosting order is significant.
            host.layer = owned; host.wantsLayer = true
            host.setAccessibilityElement(false)
            sceneHost = host; addSubview(host)
        } else { wantsLayer = true }
        overflow.contentsScale = 2
        overflow.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
        sceneLayer?.addSublayer(overflow)
        addSubview(pet); pet.attachArtwork(to: sceneLayer!, eventOnly: usesHostedScene)
        for button in buttons { addSubview(button); button.attachArtwork(to: sceneLayer!, eventOnly: usesHostedScene) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Agent orbit, scroll or use next and previous actions to cycle bubbles")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Next Agent bubbles", target: self, selector: #selector(nextBubbles)),
            NSAccessibilityCustomAction(name: "Previous Agent bubbles", target: self, selector: #selector(previousBubbles))])
        displayOptionsObserver = workspaceNotifications.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.pet.reducedMotion = self.reducedMotion
            }
        }
        pet.reducedMotion = reducedMotion
        refresh()
    }
    deinit {
        if let displayOptionsObserver { workspaceNotifications.removeObserver(displayOptionsObserver) }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
    func dispose() {
        clock?.invalidate(); clock = nil
        wheelDiagnostics.stopMonitoring()
        if let displayOptionsObserver { workspaceNotifications.removeObserver(displayOptionsObserver) }
        displayOptionsObserver = nil
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wheelDiagnostics.monitor(self)
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }
    private func occlusionChanged() {
        guard let window, movement == nil else { return }
        if window.occlusionState.contains(.visible) { beginSpaceArrival() }
        else { prepareSpaceAppearance() }
    }
    /// Called by an actual occlusion loss; exposed internally for the fixture lifecycle check.
    func prepareSpaceAppearance() {
        guard spaceLifecycle.prepareHiddenAppearance() else { return }
        spaceAt = nil; pendingSpaceFeedback = false; visualOpacity = 1
        pet.spaceTuck = reducedMotion ? 0 : 1
        if placement != .desktop { pet.edgeRetraction = reducedMotion ? 0 : min(24, pet.frame.width * 0.5) }
        applySharedTransform()
        pet.needsDisplay = true
    }
    private func beginSpaceArrival() {
        guard window?.occlusionState.contains(.visible) == true,
              spaceLifecycle.beginPreparedArrival() else { return }
        pendingSpaceFeedback = false
        spaceAt = ProcessInfo.processInfo.systemUptime
        pet.spaceTuck = reducedMotion ? 0 : 1
        visualOpacity = reducedMotion ? 0.75 : 0.45
        applySharedTransform()
        pet.refreshPetArtwork()
        configureIdle()
        ensureClock()
    }
    required init?(coder: NSCoder) { nil }
    func refresh() {
        if movement == nil { placement = runtime.petPlacement }
        layoutVisibleBubbles()
        pet.setAccessibilityLabel(runtime.snapshot.hold == nil ? "Char 桌宠，当前不可回城" : "回城，返回最初来源，Control+B\(runtime.snapshot.hold?.anchor.accuracy == .application ? "，应用级降级" : "")")
        for button in buttons { button.refreshArtwork() }
        pet.refreshPetArtwork()
        configureIdle()
        ensureClock()
    }
    private func layoutVisibleBubbles(animated: Bool = false) {
        let ends = WorkEnd.allCases.filter { end in runtime.snapshot.bubbles.contains { $0.workEnd == end } }
        offset = ends.count <= capacity ? 0 : CompanionGeometry.normalizedOffset(offset, count: ends.count)
        let key = LayoutKey(ends: ends, offset: offset, placement: placement, petSize: runtime.petSize, distance: runtime.bubbleDistance)
        guard key != lastLayout else { return }
        lastLayout = key; lastPointer = nil
        pet.placement = placement
        let petFrame = CompanionGeometry.petFrame(placement: placement, petSize: runtime.petSize)
        if pet.frame != petFrame { pet.frame = petFrame }
        pet.presentPetFrame(petFrame)
        let center = NSPoint(x: petFrame.midX, y: petFrame.midY)
        let slots = CompanionGeometry.layout(count: ends.count, offset: offset, placement: placement, petSize: runtime.petSize, bubbleDistance: runtime.bubbleDistance)
        var targets: [WorkEnd: (NSRect, Bool)] = [:]
        var foldingCenter = center
        overflow.isHidden = !slots.contains { $0.primaryIndex == nil }
        for slot in slots {
            if let index = slot.primaryIndex { targets[ends[index]] = (slot.frame, false) }
            else {
                overflow.frame = slot.frame; foldingCenter = NSPoint(x: slot.frame.midX, y: slot.frame.midY)
                for (index, frame) in zip(slot.overflowIndices, slot.miniFrames) { targets[ends[index]] = (frame, true) }
            }
        }
        for button in buttons {
            guard case let .bubble(end) = button.kind else { continue }
            if let target = targets[end] {
                button.presentBubble(frame: target.0, miniature: target.1, visible: true,
                                     animated: animated && !reducedMotion, orbitCenter: center)
            } else {
                button.presentBubble(frame: NSRect(x: foldingCenter.x - 9, y: foldingCenter.y - 9, width: 18, height: 18),
                                     miniature: true, visible: false, animated: animated && !reducedMotion, orbitCenter: center)
            }
        }
        updateOverflowArtwork()
        setAccessibilityChildren([pet] + buttons.filter { !$0.isHidden })
        applySharedTransform()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for button in ([pet] + buttons).reversed() where !button.isHidden {
            if button.containsSurfacePoint(local) { return button }
        }
        if !overflow.isHidden && overflow.frame.contains(local) { return self }
        if ProcessInfo.processInfo.systemUptime < orbitUntil {
            let radius = CompanionGeometry.radius(petSize: runtime.petSize, bubbleDistance: runtime.bubbleDistance)
            if abs(hypot(local.x - pet.frame.midX, local.y - pet.frame.midY) - radius) < 30 { return self }
        }
        return nil
    }
    private let wheelDiagnostics = WheelDiagnostics()
    override func scrollWheel(with event: NSEvent) {
        let sequence = wheelDiagnostics.input(event, offset: offset)
        let tracked = buttons.first { !$0.isHidden && !$0.miniature }
        wheelDiagnostics.handler(sequence, layer: tracked?.graphicLayer)
        let before = tracked.map { ($0.graphicLayer.presentation() ?? $0.graphicLayer).position }
        let step = scrollPolicy.step(delta: Double(event.scrollingDeltaY + event.scrollingDeltaX),
                                     precise: event.hasPreciseScrollingDeltas, hasGesturePhase: event.phase != [], momentum: event.momentumPhase != [],
                                     count: runtime.snapshot.bubbles.count, capacity: capacity, now: event.timestamp)
        if step != 0 {
            _ = cycleBubbles(by: step)
            wheelDiagnostics.accepted(sequence, step: step, offset: offset, layer: tracked?.graphicLayer,
                center: NSPoint(x: pet.frame.midX, y: pet.frame.midY), before: before)
        }
    }
    @discardableResult func cycleBubbles(by step: Int) -> Bool {
        guard canCycle, step != 0 else { return false }
        orbitUntil = reducedMotion ? 0 : ProcessInfo.processInfo.systemUptime + 0.18
        offset += step; layoutVisibleBubbles(animated: true)
        return true
    }
    // [DEBUG-char-wheel-deep] Real surface/layout/layer animation chain, opt-in fixture only.
    func debugOrbitPathFindings(step: Int) -> [String] {
        guard !reducedMotion else { return ["NOT RUN: Reduce Motion disables animated paths"] }
        var required = Set(buttons.filter { !$0.isHidden }.map(ObjectIdentifier.init))
        guard cycleBubbles(by: step) else { return ["orbit was not folded"] }
        required.formUnion(buttons.filter { !$0.isHidden }.map(ObjectIdentifier.init))
        let center = NSPoint(x: pet.frame.midX, y: pet.frame.midY)
        var findings: [String] = []
        var inspected = 0
        for button in buttons {
            let samples: OrbitPathInspection.Samples
            do {
                guard let actual = try OrbitPathInspection.read(button.graphicLayer, required: required.contains(ObjectIdentifier(button))) else {
                    FileHandle.standardError.write(Data("[DEBUG-char-wheel-deep] path-check deliberately-hidden no animation\n".utf8))
                    continue
                }
                samples = actual; inspected += 1
            } catch { findings.append("\(String(describing: button.renderedWorkEnd)): \(error)"); continue }
            let values = samples.positions, scales = samples.scales
            let first = values[0].pointValue, last = values[values.count-1].pointValue
            let fromScale = scales.first?.doubleValue ?? 0
            let toScale = scales.last?.doubleValue ?? 0
            var delta = atan2(last.y-center.y, last.x-center.x)-atan2(first.y-center.y, first.x-center.x)
            while delta > .pi { delta -= 2 * .pi }; while delta < -.pi { delta += 2 * .pi }
            let opposite = (1..<values.count).contains { index in
                let previous = values[index-1].pointValue, point = values[index].pointValue
                var travel = atan2(point.y-center.y, point.x-center.x)-atan2(previous.y-center.y, previous.x-center.x)
                while travel > .pi { travel -= 2 * .pi }; while travel < -.pi { travel += 2 * .pi }
                // Only movement while large matters: growth at a stationary entry
                // is valid, and compressed/transparent fold transport is valid.
                let size = max(scales[index-1].doubleValue, scales[index].doubleValue)
                return travel * Double(step) > 0.002 && size > 18.0/44.0 + 0.05
            }
            let row = "placement=\(placement) step=\(step) end=\(String(describing: button.renderedWorkEnd)) fromScale=\(fromScale) toScale=\(toScale) angle=\(delta) opposite=\(opposite)"
            FileHandle.standardError.write(Data("[DEBUG-char-wheel-deep] path-check \(row)\n".utf8))
            if opposite { findings.append(row) }
        }
        if required.isEmpty || inspected < required.count { findings.append("incomplete animated coverage: inspected=\(inspected) required=\(required.count)") }
        return findings
    }
    @objc fileprivate func nextBubbles() -> Bool { cycleBubbles(by: 1) }
    @objc fileprivate func previousBubbles() -> Bool { cycleBubbles(by: -1) }
    func spaceFeedback() {
        // Notifications may arrive after the pet already became visible. A
        // preserved window needs no replay; an observed hidden cycle arrives once.
        guard spaceLifecycle.state == .prepared else { return }
        if movement != nil { pendingSpaceFeedback = true }
        else { beginSpaceArrival() }
        ensureClock()
    }
    func returnFeedback() { pet.feedbackClip = "return"; feedbackAt = ProcessInfo.processInfo.systemUptime; ensureClock() }
    func pressFeedback() { pet.feedbackClip = "press"; feedbackAt = ProcessInfo.processInfo.systemUptime; ensureClock() }
    func transition(to frame: NSRect, placement: PetPlacement, animated: Bool) {
        guard animated else {
            movement = nil; self.placement = placement; visualOpacity = 1
            window?.setFrame(frame, display: true); pet.motionScale = 1; pet.edgeRetraction = 0; layoutVisibleBubbles(); applySharedTransform(); return
        }
        // Replacing this value interrupts both phases; there are no stale completion callbacks.
        movement = Transition(frame: frame, placement: placement, started: ProcessInfo.processInfo.systemUptime,
                              reduced: reducedMotion,
                              playback: CompanionPlayback(departure: runtime.customPetClipDuration(clip: self.placement == .desktop ? "depart" : "edgeHide"),
                                                          arrival: runtime.customPetClipDuration(clip: placement == .desktop ? "arrive" : "edgePeek")),
                              initialOpacity: visualOpacity, initialScale: pet.motionScale)
        ensureClock()
    }
    private func ensureClock() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        if let clock { RunLoop.main.add(clock, forMode: .common); RunLoop.main.add(clock, forMode: .eventTracking) }
    }
    private func animate() {
        wheelDiagnostics.tick()
        guard window?.isVisible == true else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let reduce = reducedMotion
        let wasAnimating = movement != nil || feedbackAt != nil || spaceAt != nil
        pet.elapsed = reduce ? 0 : now - epoch
        pet.clip = "idle"
        pet.clipElapsed = pet.elapsed
        pet.feedbackElapsed = feedbackAt.map { reduce ? 0 : now - $0 }
        if let feedbackAt, now - feedbackAt > (runtime.customPetClipDuration(clip: pet.feedbackClip) ?? 0.65) { self.feedbackAt = nil; pet.feedbackElapsed = nil }
        if var motion = movement {
            if spaceAt != nil { spaceAt = nil; spaceLifecycle.finishArrival(); pet.spaceTuck = 0 }
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
                visualOpacity = motion.initialOpacity * (1 - phase * phase)
                pet.motionScale = motion.reduced || placement != .desktop ? 1 : motion.initialScale * (1 - 0.8 * phase * phase)
                pet.edgeRetraction = motion.reduced || placement == .desktop ? 0 : phase * 38
            } else {
                if !motion.arrived {
                    window?.setFrame(motion.frame, display: true)
                    placement = motion.placement; layoutVisibleBubbles(); motion.arrived = true
                }
                visualOpacity = motion.reduced ? phase : min(1, phase * 3)
                pet.motionScale = motion.reduced || placement != .desktop ? 1 : CGFloat(0.2 + 0.8 * CompanionGeometry.arrivalProgress(phase))
                pet.edgeRetraction = motion.reduced || placement == .desktop ? 0 : CGFloat(38 * (1 - CompanionGeometry.arrivalProgress(phase)))
            }
            movement = t == 1 ? nil : motion
            if t == 1 { visualOpacity = 1; pet.motionScale = 1; pet.edgeRetraction = 0 }
        }
        if movement == nil, pendingSpaceFeedback {
            pendingSpaceFeedback = false
            beginSpaceArrival()
        }
        if let start = spaceAt, movement == nil {
            let t = now - start
            let duration = reduce ? 0.16 : 0.70
            if t >= duration {
                spaceAt = nil; spaceLifecycle.finishArrival(); pet.spaceTuck = 0; pet.edgeRetraction = 0; visualOpacity = 1
            } else {
                if reduce {
                    pet.spaceTuck = 0
                    visualOpacity = 0.75 + CGFloat(t / duration) * 0.25
                } else {
                    // Arrival-only feedback avoids a full-size appearance followed by withdrawal.
                    let tuck = 1 - CompanionGeometry.spaceArrivalProgress(t / duration)
                    pet.spaceTuck = CGFloat(max(-0.12, tuck))
                    visualOpacity = min(1, 0.45 + CGFloat(t / duration) * 0.90)
                    if placement != .desktop { pet.edgeRetraction = pet.spaceTuck * min(24, pet.frame.width * 0.5) }
                }
            }
        }
        // AppKit hitTest alone does not forward events through a transparent NSWindow.
        if let window {
            let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            wheelDiagnostics.route(self, point: local, accepts: !window.ignoresMouseEvents)
            let orbitActive = now < orbitUntil
            if local != lastPointer || orbitActive || orbitActive != lastOrbitActive {
                let desired = hitTest(local) == nil
                if window.ignoresMouseEvents != desired {
                    window.ignoresMouseEvents = desired
                }
                lastPointer = local
                lastOrbitActive = orbitActive
            }
            var nearest: GraphicButton?
            var distance: CGFloat = 90
            for button in buttons where !button.isHidden {
                let d = hypot(local.x - button.presentationFrame.midX, local.y - button.presentationFrame.midY)
                if d < distance { nearest = button; distance = d }
                let target: CGFloat = button.containsSurfacePoint(local) ? 1 : 0
                let oldHover = button.hover
                button.hover += (target - button.hover) * 0.18
                if abs(button.hover - oldHover) > 0.002 { button.updateHoverRim() }
            }
            let target = nearest == nil ? NSPoint.zero : NSPoint(x: (local.x - pet.frame.midX) / 80, y: (local.y - pet.frame.midY) / 80)
            pet.gaze.x += (max(-1, min(1, target.x)) - pet.gaze.x) * 0.12
            pet.gaze.y += (max(-1, min(1, target.y)) - pet.gaze.y) * 0.12
        }
        pet.refreshPetArtwork()
        if lastReduced != reduce { configureIdle() }
        if wasAnimating || lastReduced != reduce { applySharedTransform() }
        lastReduced = reduce
        // Keep the single lightweight clock for pointer passthrough; Reduce Motion freezes drawing.
    }
    private func configureIdle() {
        for button in [pet] + buttons { button.configureIdle(reduced: reducedMotion) }
        if reducedMotion { sceneLayer?.removeAnimation(forKey: "scene-idle"); return }
        guard sceneLayer?.animation(forKey: "scene-idle") == nil else { return }
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, 2, 0, -1, 0]; bob.isAdditive = true
        let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
        breathe.values = [0, 0.006, 0, -0.004, 0]; breathe.isAdditive = true
        for animation in [bob,breathe] { animation.duration = 4.8; animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4) }
        let group = CAAnimationGroup(); group.animations = [bob,breathe]; group.duration = 4.8
        group.repeatCount = .infinity; group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sceneLayer?.add(group, forKey: "scene-idle")
    }
    /// One scene pose links the pet, primary bubbles and overflow miniatures.
    /// Layer opacity leaves the native window's occlusion state unchanged.
    private func applySharedTransform() {
        let feedback = reducedMotion ? 0 : pet.feedbackElapsed.map { exp(-8 * $0) * sin(22 * $0) } ?? 0
        let baseScale = pet.motionScale * (1 - pet.spaceTuck * 0.45)
        let sx = baseScale * CGFloat(1 + feedback * 0.06)
        let sy = baseScale * CGFloat(1 - feedback * 0.08)
        // AppKit backing layers commonly use (0,0), unlike ordinary CALayer defaults.
        let layerAnchor = sceneLayer?.anchorPoint ?? .zero
        let pivot = NSPoint(x: pet.frame.midX - bounds.width * layerAnchor.x,
                            y: pet.frame.midY - bounds.height * layerAnchor.y)
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch placement {
        case .left: dx = -pet.edgeRetraction
        case .right: dx = pet.edgeRetraction
        case .top: dy += pet.edgeRetraction
        case .bottom: dy -= pet.edgeRetraction
        case .desktop: break
        }
        let transform = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                          tx: pivot.x * (1 - sx) + dx, ty: pivot.y * (1 - sy) + dy)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sceneLayer?.setAffineTransform(transform)
        sceneLayer?.opacity = Float(visualOpacity)
        CATransaction.commit()
    }
    private func updateOverflowArtwork() {
        guard !overflow.isHidden else { return }
        let count = max(0, runtime.snapshot.bubbles.count - (capacity - 1))
        if overflowCount == count, overflowArtwork != nil { return }
        overflowCount = count
        overflowArtwork = BubbleDrawing.raster(size: overflow.frame.size) {
            let rect = NSRect(origin: .zero, size: overflow.frame.size)
            BubbleDrawing.shell(in: rect, tint: .systemBlue)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            "+\(count)".draw(in: NSRect(x: rect.midX - 11, y: rect.midY - 3, width: 22, height: 12),
                            withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold),
                                             .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        }
        overflow.contents = overflowArtwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

@MainActor final class GraphicButton: NSView {
    // All vector and manifest-anchor geometry uses AppKit's bottom-left coordinates.
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    enum Kind { case pet, bubble(WorkEnd) }
    let kind: Kind
    var isEnabled = true
    let graphicLayer = CALayer()
    private let textureLayer = CALayer()
    private let hoverLayer = CALayer()
    private var externalArtwork = false
    private var petArtworkKey = ""
    private var customImageIdentity: ObjectIdentifier?
    private var presentationGeneration = 0
    var renderedWorkEnd: WorkEnd? { if case let .bubble(end) = kind { return end }; return nil }
    var hasOwnedImage: Bool { textureLayer.contents != nil }
    private var renderedImage: CGImage?
    var artworkPixelData: Data? { renderedImage?.dataProvider?.data as Data? }
    var presentationFrame: NSRect { graphicLayer.presentation()?.frame ?? graphicLayer.frame }
    unowned let runtime: CompanionRuntime
    private struct ArtworkKey: Equatable {
        let workEnd: WorkEnd
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
        let next = ArtworkKey(workEnd: end, bubble: runtime.snapshot.bubbles.first { $0.workEnd == end },
                              icon: runtime.agentIcon(for: end).map(ObjectIdentifier.init), miniature: miniature, size: bounds.size)
        if next != artworkKey {
            artworkKey = next
            artwork = BubbleDrawing.raster(size: NSSize(width: 44, height: 44)) { drawBubbleContent(end) }
            renderedImage = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            textureLayer.contents = renderedImage
        }
        let bubble = next.bubble
        setAccessibilityLabel("\(end.title): \(bubble?.count ?? 0) unviewed, \(bubble?.runningCount ?? 0) running\(bubble?.head.map { ", \($0.reason.title)\($0.isPast ? ", past" : "")\($0.navigationOutcome == .fallback ? ", application fallback" : "")" } ?? "")")
    }
    var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private static let defaultBody = BubbleDrawing.raster(size: NSSize(width: 76, height: 76)) {
        let ink = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1)
        let cream = NSColor(calibratedRed: 1, green: 0.97, blue: 0.87, alpha: 1)
        let body = NSBezierPath(roundedRect: NSRect(x: 7, y: 8, width: 62, height: 60), xRadius: 21, yRadius: 21)
        cream.setFill(); body.fill(); ink.setStroke(); body.lineWidth = 3.5; body.stroke()
    }
    var responding = false
    var gaze = NSPoint.zero
    var hover: CGFloat = 0
    private let hoverRim = CAShapeLayer()
    private var rimBounds = NSRect.zero
    func updateHoverRim() {
        if rimBounds != textureLayer.bounds { rimBounds = textureLayer.bounds; hoverRim.path = CGPath(ellipseIn: textureLayer.bounds.insetBy(dx: 2, dy: 2), transform: nil) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverRim.opacity = Float(hover)
        hoverLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: hover * 3).scaledBy(x: 1 + hover * 0.09, y: 1 + hover * 0.09))
        CATransaction.commit()
    }
    var spaceTuck: CGFloat = 0
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
        wantsLayer = true
        graphicLayer.bounds = NSRect(x: 0, y: 0, width: 44, height: 44)
        hoverLayer.frame = graphicLayer.bounds
        textureLayer.frame = graphicLayer.bounds
        textureLayer.contentsScale = 2
        graphicLayer.addSublayer(hoverLayer); hoverLayer.addSublayer(textureLayer); layer?.addSublayer(graphicLayer)
        let actions: [String: CAAction] = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull(), "opacity": NSNull()]
        graphicLayer.actions = actions; textureLayer.actions = actions; hoverLayer.actions = actions
        setAccessibilityRole(.button)
        switch kind {
        case .pet:
            setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Open Settings", target: self, selector: #selector(accessibleSettings)),
                NSAccessibilityCustomAction(name: "Toggle Mute", target: self, selector: #selector(accessibleMute)),
                NSAccessibilityCustomAction(name: "结束回城", target: self, selector: #selector(accessibleEnd))])
        case .bubble:
            hoverRim.fillColor = NSColor.clear.cgColor
            hoverRim.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
            hoverRim.lineWidth = 2; hoverRim.opacity = 0
            textureLayer.addSublayer(hoverRim)
            setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Ignore first attention item", target: self, selector: #selector(accessibleIgnore))])
        }
    }
    required init?(coder: NSCoder) { nil }
    func performClick(_ sender: Any?) { performClickAction() }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; performClickAction(); return true }
    @objc private func performClickAction() {
        guard isEnabled else { return }
        switch kind {
        case .pet:
            if runtime.snapshot.hold == nil { (superview as? CompanionSurface)?.pressFeedback() }
            runtime.petClicked()
        case let .bubble(end): runtime.visit(end)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { isEnabled ? super.hitTest(point) : nil }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if case .pet = kind {
            dragStart = NSEvent.mouseLocation; initialOrigin = window?.frame.origin; didDrag = false
        } else { beginBubblePress() }
    }
    func beginBubblePress() {
        guard isEnabled, case .bubble = kind else { return }
        responding = true
    }
    @discardableResult func finishBubblePress(atSurfacePoint point: NSPoint) -> Bool {
        let accepted = responding && isEnabled && containsSurfacePoint(point)
        responding = false
        if accepted { performClickAction() }
        return accepted
    }
    override func mouseDragged(with event: NSEvent) {
        guard case .pet = kind, let start = dragStart, let origin = initialOrigin else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        if abs(dx) + abs(dy) > 3 { didDrag = true }
        if didDrag { window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        guard case .pet = kind else {
            let point = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            _ = finishBubblePress(atSurfacePoint: point)
            return
        }
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
                item.target = surface; item.isEnabled = surface.canCycle; menu.addItem(item)
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

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { if case .pet = kind { refreshPetArtwork() } else { refreshArtwork() } }
    override func layout() {
        super.layout()
        if !externalArtwork {
            graphicLayer.bounds = bounds; graphicLayer.position = NSPoint(x: bounds.midX, y: bounds.midY)
            hoverLayer.frame = graphicLayer.bounds
            textureLayer.frame = graphicLayer.bounds
            refreshPetArtwork()
        }
    }
    func attachArtwork(to host: CALayer, eventOnly: Bool = false) {
        externalArtwork = true
        graphicLayer.removeFromSuperlayer(); host.addSublayer(graphicLayer)
        if eventOnly { wantsLayer = false }
    }
    func containsSurfacePoint(_ point: NSPoint) -> Bool {
        guard !isHidden else { return false }
        let frame = presentationFrame
        guard frame.contains(point) else { return false }
        if case .pet = kind { return true }
        let x = (point.x-frame.midX)/(frame.width/2), y = (point.y-frame.midY)/(frame.height/2)
        return x*x+y*y <= 1
    }
    func presentPetFrame(_ frame: NSRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        graphicLayer.bounds = NSRect(origin: .zero, size: frame.size)
        graphicLayer.position = NSPoint(x: frame.midX, y: frame.midY)
        hoverLayer.frame = graphicLayer.bounds
        textureLayer.frame = graphicLayer.bounds
        CATransaction.commit()
        refreshPetArtwork()
    }
    func presentBubble(frame: NSRect, miniature: Bool, visible: Bool, animated: Bool, orbitCenter: NSPoint) {
        let start = graphicLayer.presentation() ?? graphicLayer
        let position = start.position
        let scale = LayerGeometry.planarScale(of: start)
        let opacity = start.opacity
        let wasMiniature = self.miniature, wasVisible = !isHidden
        self.miniature = miniature; self.frame = frame
        isHidden = !visible
        presentationGeneration += 1; let generation = presentationGeneration
        graphicLayer.isHidden = !visible && (!animated || opacity <= 0)
        let target = NSPoint(x: frame.midX, y: frame.midY)
        let targetScale: CGFloat = visible ? frame.width/44 : 0.01
        CATransaction.begin(); CATransaction.setDisableActions(true)
        graphicLayer.bounds = NSRect(x: 0, y: 0, width: 44, height: 44)
        hoverLayer.frame = graphicLayer.bounds
        textureLayer.frame = graphicLayer.bounds
        graphicLayer.position = target
        graphicLayer.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))
        graphicLayer.opacity = visible ? 1 : 0
        graphicLayer.removeAnimation(forKey: "orbit")
        refreshArtwork()
        if animated && (opacity > 0 || visible) {
            let initial = position
            let path = CAKeyframeAnimation(keyPath: "position")
            let a = atan2(initial.y-orbitCenter.y, initial.x-orbitCenter.x)
            let b = atan2(target.y-orbitCenter.y, target.x-orbitCenter.x)
            var delta = b-a
            while delta > .pi { delta -= 2 * .pi }; while delta < -.pi { delta += 2 * .pi }
            let r0 = hypot(initial.x-orbitCenter.x, initial.y-orbitCenter.y), r1 = hypot(target.x-orbitCenter.x, target.y-orbitCenter.y)
            // An open edge arc has no visible wrap route. Compress at the old
            // position, transport while tiny and transparent, then expand at the
            // fold/entry. Neighboring primary slots keep their linear 180ms orbit.
            let boundary = abs(delta) > 1.3 && (wasMiniature != miniature || !visible || !wasVisible)
            let transport: (CGFloat) -> CGFloat = { t in boundary ? min(1, max(0, (t - 0.3) / 0.4)) : t }
            path.values = (0...24).map { index in
                let t = transport(CGFloat(index)/24), radius = r0+(r1-r0)*t, angle = a+delta*t
                return NSValue(point: NSPoint(x: orbitCenter.x+cos(angle)*radius, y: orbitCenter.y+sin(angle)*radius))
            }
            path.calculationMode = .linear
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            grow.values = (0...24).map { index -> CGFloat in
                let t = CGFloat(index)/24
                if !boundary { return scale + (targetScale-scale)*t }
                if t < 0.3 { return scale + (0.08-scale)*t/0.3 }
                if t < 0.7 { return 0.08 }
                return 0.08 + (targetScale-0.08)*(t-0.7)/0.3
            }
            fade.values = (0...24).map { index -> Float in
                let t = Float(index)/24, target: Float = visible ? 1 : 0
                if !boundary { return opacity + (target-opacity)*t }
                if t < 0.3 { return opacity*(1-t/0.3) }
                if t < 0.7 { return 0 }
                return target*(t-0.7)/0.3
            }
            grow.calculationMode = .linear; fade.calculationMode = .linear
            for animation in [path, grow, fade] { animation.duration = 0.18; animation.timingFunction = CAMediaTimingFunction(name: .linear) }
            let group = CAAnimationGroup(); group.animations = [path, grow, fade]; group.duration = 0.18
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            graphicLayer.add(group, forKey: "orbit")
            if !visible {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.18) { [weak self] in
                    guard let self, self.presentationGeneration == generation else { return }
                    self.graphicLayer.isHidden = true
                }
            }
        }
        CATransaction.commit()
    }
    func refreshPetArtwork() {
        guard case .pet = kind, bounds.width > 0 else { return }
        let imageClip = feedbackElapsed == nil ? clip : feedbackClip
        let badge = runtime.sourceBadgeAnchor
        let overlayKey = "\(badge?.id ?? "")/\(badge?.bundleIdentifier ?? "")/\(String(describing: badge?.accuracy))/\(Int(runtime.sourceBadgeOpacity*30))/\(String(describing: runtime.snapshot.navigationFeedback))"
        if let custom = runtime.customPetImage(clip: imageClip, elapsed: feedbackElapsed ?? clipElapsed) {
            let identity = ObjectIdentifier(custom)
            guard identity != customImageIdentity || petArtworkKey != "custom/\(bounds.size)/\(placement)/\(overlayKey)" else { return }
            customImageIdentity = identity; petArtworkKey = "custom/\(bounds.size)/\(placement)/\(overlayKey)"
        } else {
            let blink = !reducedMotion && elapsed.truncatingRemainder(dividingBy: 5.2) > 5.04
            let key = "\(bounds.size)/\(placement)/\(Int(gaze.x*30))/\(Int(gaze.y*30))/\(blink)/\(responding)/\(overlayKey)"
            guard petArtworkKey != key else { return }
            customImageIdentity = nil; petArtworkKey = key
        }
        let image = BubbleDrawing.raster(size: bounds.size) { drawPet() }
        renderedImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        textureLayer.contents = renderedImage
    }
    func configureIdle(reduced: Bool) {
        if reduced { textureLayer.removeAnimation(forKey: "idle"); return }
        guard textureLayer.animation(forKey: "idle") == nil else { return }
        let rotate = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotate.values = [0, 0.035, 0, -0.025, 0]
        let x = CAKeyframeAnimation(keyPath: "transform.scale.x"); x.values = [1, 1.025, 1, 0.975, 1]
        let y = CAKeyframeAnimation(keyPath: "transform.scale.y"); y.values = [1, 0.975, 1, 1.025, 1]
        for animation in [rotate,x,y] { animation.duration = 4.8; animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4) }
        let group = CAAnimationGroup(); group.animations = [rotate,x,y]; group.duration = 4.8
        group.repeatCount = .infinity; group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        textureLayer.add(group, forKey: "idle")
    }
    private func drawPet() {
        let reduce = reducedMotion
        let pulse = 0.0
        let idleBounce = 0.0
        let feedback = 0.0
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        let imageClip = feedbackElapsed == nil ? clip : feedbackClip
        let custom = runtime.customPetImage(clip: imageClip, elapsed: feedbackElapsed ?? clipElapsed)
        // The manifest anchor lands at the stable pet center and is the deformation pivot.
        let anchor = NSPoint(x: bounds.midX, y: bounds.midY)
        transform.translateX(by: anchor.x, yBy: anchor.y)
        let edgeTilt: CGFloat = placement == .left ? -8 : placement == .right ? 8 : 0
        transform.rotate(byDegrees: edgeTilt + CGFloat(reduce ? 0 : 0 + idleBounce * 6 + feedback * 7))
        let widthPose = CGFloat(1 + pulse * 0.018 + idleBounce * 0.28 + feedback * 0.1)
        let heightPose = CGFloat(1 - pulse * 0.025 - idleBounce * 0.28 - feedback * 0.1)
        transform.scaleX(by: widthPose,
                         yBy: heightPose)
        transform.translateX(by: -anchor.x, yBy: -anchor.y)
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
            // A face inset toward the desktop keeps both eyes visible in the peek pose.
            let scale = bounds.width / 76
            let local = NSAffineTransform(); local.scaleX(by: scale, yBy: scale); local.concat()
            let ink = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1)
            Self.defaultBody.draw(in: NSRect(x: 0, y: 0, width: 76, height: 76))
            ink.setFill()
            let blink = !reduce && elapsed.truncatingRemainder(dividingBy: 5.2) > 5.04
            let faceX: CGFloat = placement == .left ? 16 : placement == .right ? -17 : 0
            let faceY: CGFloat = placement == .bottom ? 15 : placement == .top ? -20 : 0
            for x in [27.0, 46.0] {
                NSBezierPath(roundedRect: NSRect(x: x + faceX + gaze.x * 3, y: (blink || responding ? 38 : 33) + faceY + gaze.y * 3,
                                               width: 4, height: blink || responding ? 3 : 12), xRadius: 2, yRadius: 2).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let badgeScale = bounds.width / 76
        NSGraphicsContext.saveGraphicsState()
        let badgeTransform = NSAffineTransform(); badgeTransform.scaleX(by: badgeScale, yBy: badgeScale); badgeTransform.concat()
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
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawBubbleContent(_ end: WorkEnd) {
        let bounds = NSRect(x: 0, y: 0, width: 44, height: 44)
        guard let bubble = runtime.snapshot.bubbles.first(where: { $0.workEnd == end }) else { return }
        BubbleDrawing.shell(in: bounds, tint: .clear)
        let iconRect = bounds.insetBy(dx: miniature ? 3 : 7, dy: miniature ? 3 : 7)
        if let icon = runtime.agentIcon(for: end) { icon.draw(in: iconRect) }
        else { symbol(end.symbol, in: iconRect, color: .labelColor) }
        if [.claudeCode, .codexCLI, .kimiCLI, .pi].contains(end) {
            let size: CGFloat = miniature ? 8 : 14
            let rect = NSRect(x: 0, y: bounds.height - size, width: size, height: size)
            NSColor(calibratedWhite: 0.09, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            symbol("terminal", in: rect.insetBy(dx: 2, dy: 2), color: .white)
        }
        guard !miniature else { return }
        let group = bubble.head.map { AttentionPresentationGroup.forReason($0.reason) }
        let color: NSColor = group == nil ? .systemMint : group == .issue ? .systemOrange : group == .interaction ? .systemBlue : .systemGreen
        let badge = NSRect(x: bounds.maxX - 26, y: 0, width: 26, height: 15)
        color.withAlphaComponent(bubble.head?.isPast == true ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 7.5, yRadius: 7.5).fill()
        symbol(group?.symbol ?? "circle.fill", in: NSRect(x: badge.minX + 3, y: 3, width: 9, height: 9), color: .white)
        number(bubble.head == nil ? bubble.runningCount : bubble.count, rect: NSRect(x: badge.minX + 12, y: 1, width: 12, height: 13), color: .white, size: 10)
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
