import AppKit
import QuartzCore
import ApplicationServices
import UniformTypeIdentifiers
import SwiftUI
import CharCore
import CharObservations
import CharPlatform
import CharPluginHost

actor ObservationWorker {
    private let poller: LocalObservationPoller
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        let kimiHome = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".kimi-code")
        let hookEvents = ProcessInfo.processInfo.environment["CHAR_HOOK_EVENTS"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Application Support/Char/harness-hooks.jsonl")
        poller = LocalObservationPoller(claudeProjectsRoot: home.appendingPathComponent(".claude/projects"),
            codexSessionsRoot: codexHome.appendingPathComponent("sessions"),
            hookEventsFile: hookEvents,
            kimiSessionsRoot: kimiHome.appendingPathComponent("sessions"))
    }
    func start() { poller.start() }
    private var configuration = ObservationGeneration()
    struct Batch { let events: [ObservationEvent]; let configuration: ObservationGeneration }
    func poll() -> Batch { Batch(events: poller.poll(), configuration: configuration) }
    func configure(_ next: ObservationGeneration) {
        guard next.isNewer(than: configuration) else { return }
        let restarted = next.enabled.filter { next.generations[$0, default: 0] != configuration.generations[$0, default: 0] }
        // An off/on Task may overtake the off Task. Apply a new EOF baseline anyway.
        var enabled = next.enabled.subtracting(restarted)
        poller.setEnabledWorkEnds(enabled, at: next.changedAt)
        for end in restarted.sorted() {
            enabled.insert(end)
            poller.setEnabledWorkEnds(enabled, at: next.activatedAt[end] ?? next.changedAt)
        }
        configuration = next
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: CompanionRuntime?
    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = CompanionRuntime()
        runtime?.start()
    }
    func applicationWillTerminate(_ notification: Notification) { runtime?.capabilityHost?.stopAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor final class CompanionRuntime: NSObject, ObservableObject, NSWindowDelegate {
    let demo: Bool
    let smoke: Bool
    let store: CharSettingsStore
    let router: AttentionRouter
    let platform: MacOSPlatform?
    private let login: LoginItemController?
    let worker: ObservationWorker?
    let pluginStore: IntegrationPluginStore?
    let skinStore: PetSkinStore?
    var agentIconCache: [WorkEnd: NSImage] = [:]
    var pluginRegistryRevision: Date?
    var observationGeneration = ObservationGeneration()
    var capabilityHost: CapabilityHost?
    var nativeRuntimeURL: URL?
    var capabilityOrigins: [String: CapabilityOrigin] = [:]
    var capabilityRevision = 0
    @Published var pluginHealth: [String: PluginHealth] = [:]
    @Published var pluginEntries: [IntegrationPluginEntry] = []
    @Published var skins: [PetSkinManifest] = []
    @Published var selectedSkinID = "char.default"
    @Published var useAppearanceBehavior = true
    @Published var selectedThemeID = ""
    @Published var installedIconStatus = ""
    var loadedAppearanceID: String?
    var appearanceScript: AppearanceScriptHost?
    var appearanceGeneration = 0
    var appearancePoseCache: [String:PetSkinPose] = [:]
    var appearanceApplyingActions = false
    var appearanceSoundCache: [String:NSSound] = [:]
    var appearanceSoundTimes: [String:TimeInterval] = [:]
    var appearanceIconTask: Task<Void,Never>?

    @Published var petPlacement: PetPlacement = .desktop
    @Published var petSize: Double = 48
    @Published var bubbleDistance: Double = 20
    var bubbleCapacity: Int {
        appearanceCapacity(for: petPlacement)
    }
    private var companionPreferences = CompanionPreferences()
    private let companionPreferencesURL: URL
    @Published var settings: CharSettings
    @Published var snapshot: AttentionSnapshot
    @Published var setupMessage = ""
    @Published var loginStatus = ""
    @Published var loginFailure: LoginItemError?
    @Published var accessibilityStatus = ""
    @Published var automationStatus = ""
    @Published var busy = false
    @Published var homeShortcutStatus = ""
    private var homeShortcut: HomeShortcutController!
    private var fixtureHotKey: FixtureHomeHotKeyService?
    private var timer: Timer?
    private var polling = false
    private var displayTimer: Timer?
    private var statusBar: StatusBarController?
    func refreshAppearanceStatusBar() { statusBar?.refresh() }
    private var retainedAnchor: ReturnAnchor?
    private(set) var sourceBadgeAnchor: ReturnAnchor?
    private(set) var sourceBadgeOpacity: CGFloat = 0
    private var badgeFadeTimer: Timer?
    private var badgeFadeGeneration = 0
    var panel: CompanionPanel!
    var settingsWindow: NSWindow?
    private var currentDisplay: String?
    private var feedbackGeneration = 0
    private var responseGeneration = 0
    private var demoSoundCount = 0

    override init() {
        smoke = CommandLine.arguments.contains("--smoke") || CommandLine.arguments.contains("--capability-smoke")
        demo = smoke || CommandLine.arguments.contains("--demo")
        let directory = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("Char-fixture-\(UUID().uuidString)")
            : CharSettingsStore.defaultFileURL.deletingLastPathComponent()
        store = CharSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        companionPreferencesURL = directory.appendingPathComponent("companion.json")
        pluginStore = try? IntegrationPluginStore(directory: directory.appendingPathComponent("integrations"))
        skinStore = try? PetSkinStore(directory: directory.appendingPathComponent("skins"))
        let loaded: CharSettings
        let loadMessage: String
        do { loaded = try store.load(); loadMessage = "" }
        catch { loaded = CharSettings(); loadMessage = (loaded.language == .chinese ? "无法读取设置：" : "Could not load preferences: ") + error.localizedDescription }
        let initialSettings = demo ? CharSettings(filterSeconds: 0, launchAtLogin: false) : loaded
        settings = initialSettings
        let engine = AttentionRouter(settings: initialSettings)
        router = engine
        snapshot = engine.snapshot
        platform = demo ? nil : MacOSPlatform()
        login = demo ? nil : LoginItemController()
        worker = demo ? nil : ObservationWorker()
        super.init()
        if smoke {
            let service = FixtureHomeHotKeyService()
            fixtureHotKey = service
            homeShortcut = HomeShortcutController(service: service) { [weak self] in self?.returnHome() }
        } else {
            homeShortcut = HomeShortcutController { [weak self] in self?.returnHome() }
        }
        setupMessage = loadMessage
        if let pluginStore { pluginEntries = pluginStore.entries }
        else { setupMessage = localized("插件目录无法加载；请检查本地配置。", "Could not load plugin directory.") }
        platform?.configure(plugins: pluginEntries.filter(\.enabled).map(\.plugin))
        refreshSkins()
        if let data = try? Data(contentsOf: companionPreferencesURL),
           let saved = try? JSONDecoder().decode(CompanionPreferences.self, from: data) {
            companionPreferences = saved; petPlacement = saved.placement; petSize = saved.petSize; bubbleDistance = saved.bubbleDistance
        }

    }

    func start() {
        initializeCapabilityHost()
        panel = CompanionPanel(runtime: self)
        refreshSkins()
        place(on: NSScreen.main ?? NSScreen.screens.first, animated: false)
        panel.orderFrontRegardless()
        statusBar = StatusBarController(runtime: self)
        installDesktopTracking()
        if demo { injectFixtures() }
        else {
            refreshStatus()
            if settings.launchAtLogin {
                do {
                    _ = try login?.setEnabled(true)
                    loginFailure = nil
                } catch {
                    loginFailure = (error as? LoginItemError) ?? .failed(error.localizedDescription)
                }
                refreshStatus()
            }
        }
        observationGeneration.configure(enabled: enabledWorkEnds, at: Date())
        let initialConfiguration = observationGeneration
        Task {
            await worker?.configure(initialConfiguration)
            await worker?.start()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tick() }
            }
        }
        if smoke {
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await runSmoke()
            }
        }
    }

    private func injectFixtures() {
        let now = Date()
        var events: [ObservationEvent] = []
        for (index, end) in WorkEnd.allCases.enumerated() {
            for number in 0..<2 {
                events.append(ObservationEvent(key: SessionKey(workEnd: end, nativeID: "fixture-\(index)-\(number)"),
                    target: SessionTarget(bundleIdentifier: "fixture-only"),
                    timestamp: now, state: .stopped(number == 0 ? (end == .codexDesktop ? .approval : .question) : .turnEnded)))
            }
        }
        router.ingest(events)
        router.advance(to: now)
        let past = ObservationEvent(key: SessionKey(workEnd: .codexCLI, nativeID: "fixture-1-0"),
            target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable"), timestamp: now.addingTimeInterval(0.01), state: .running)
        let pastSecond = ObservationEvent(key: SessionKey(workEnd: .codexCLI, nativeID: "fixture-1-1"),
            target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable"), timestamp: now.addingTimeInterval(0.01), state: .running)
        router.ingest([past, pastSecond])
        publish()
    }

    private func tick() async {
        reloadPlugins()
        guard !polling, !busy else { return }
        polling = true
        defer { polling = false }
        let batch = await worker?.poll()
        let events = batch.map { batch in batch.events.filter { observationGeneration.accepts($0.key.workEnd, from: batch.configuration) } } ?? []
        let pluginEvents = capabilityHost?.drainEvents().filter { enabledWorkEnds.contains($0.key.workEnd) && $0.timestamp >= (observationGeneration.activatedAt[$0.key.workEnd] ?? .distantPast) } ?? []
        router.ingest((events + pluginEvents).sorted { $0.timestamp < $1.timestamp }) // A complete sleep/wake batch precedes any focus or time advancement.
        refreshCapabilityHealth()
        if let platform {
            var focus = platform.focusContext(for: router.snapshot.hold?.anchor)
            if let anchor = router.snapshot.hold?.anchor {
                let state = await originState(anchor)
                if state.valid == false { router.invalidateAnchor(id: anchor.id) }
                if state.active { focus.sourceAnchorID = anchor.id }
            }
            router.updateFocus(focus, at: Date())
        } else { router.advance(to: Date()) }
        publish()
    }

    func visit(_ workEnd: WorkEnd) {
        guard !busy, let item = router.nextVisit(for: workEnd) else { return }
        busy = true
        Task {
            let capture = effectiveOriginPolicy != .disabled && (router.snapshot.hold == nil || effectiveOriginPolicy == .latest)
            let source = capture ? (demo ? fixtureAnchor() : await captureOrigin()) : nil
            let outcome = await visitCapability(workEnd, target: item.target)
            if outcome != .unavailable { panel.surface.dismissFeedback(for: workEnd) }
            router.completeVisit(key: item.key, outcome: outcome, sourceAnchor: source, at: Date())
            if let source, router.snapshot.hold?.anchor.id != source.id { releaseOrigin(source) }
            busy = false
            publish()
            scheduleFeedbackClear()
        }
    }

    func ignore(_ workEnd: WorkEnd) { router.ignoreNext(for: workEnd); publish() }

    func returnHome() {
        guard router.snapshot.hold != nil else { return }
        petClicked()
    }
    func retryHomeShortcut() { homeShortcut.retry(); refreshHomeShortcutStatus() }
    func refreshHomeShortcutStatus() {
        let next: String
        switch homeShortcut.status {
        case .inactive: next = localized("Ctrl+B 未启用", "Ctrl+B inactive")
        case .registered: next = smoke ? localized("演示：Ctrl+B 回城", "Fixture: Ctrl+B return") : localized("Ctrl+B 已注册，可回城", "Ctrl+B ready")
        case let .failed(code): next = localized("Ctrl+B 注册失败（\(code)）", "Ctrl+B registration failed (\(code))")
        }
        if homeShortcutStatus != next { homeShortcutStatus = next }
    }
    func petClicked() {
        guard !busy else { return }
        guard let anchor = router.snapshot.hold?.anchor else {
            responseGeneration += 1
            let generation = responseGeneration
            panel.surface.pressFeedback()
            panel.surface.pet.responding = true
            panel.surface.pet.needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, generation == self.responseGeneration else { return }
                self.panel.surface.pet.responding = false; self.panel.surface.pet.needsDisplay = true
            }
            return
        }
        busy = true
        panel.surface.returnFeedback()
        appearanceEvent("return")
        Task {
            let outcome = await returnToOrigin(anchor)
            router.completeReturn(outcome: outcome)
            busy = false; publish(); scheduleFeedbackClear()
        }
    }

    func endHold() { router.endHold(); publish() }
    func toggleMute() { settings.soundEnabled.toggle(); saveSettings() }
    func saveSettings() {
        settings = settings.normalized()
        if !settings.soundEnabled { appearanceSoundCache.values.forEach { $0.stop() } }
        router.updateSettings(effectiveSettings)
        do { try store.save(settings) } catch { setupMessage = error.localizedDescription }
        publish()
    }
    func setLogin(_ enabled: Bool) {
        guard !demo else { return }
        do {
            _ = try login?.setEnabled(enabled)
            settings.launchAtLogin = enabled
            loginFailure = nil
            saveSettings()
        } catch {
            loginFailure = (error as? LoginItemError) ?? .failed(error.localizedDescription)
        }
        refreshStatus()
    }
    func requestAccessibility() {
        guard !demo else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshStatus()
    }
    func requestAutomation() {
        guard let platform else { return }
        Task { _ = await platform.requestTabbitAutomationPermission(); refreshStatus() }
    }
    func chooseAudio() {
        guard !demo else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.allowedContentTypes = [.audio]
        picker.title = localized("选择音频", "Choose audio")
        picker.prompt = localized("选择", "Choose")
        if picker.runModal() == .OK, let path = picker.url?.path {
            guard NSSound(contentsOfFile: path, byReference: true) != nil else {
                setupMessage = localized("无法播放所选音频。", "The selected audio file cannot be played by macOS."); return
            }
            settings.audioFilePath = path; saveSettings()
        }
    }
    func refreshStatus() {
        guard !demo else {
            loginStatus = localized("演示：启动状态不变", "Fixture: login unchanged")
            accessibilityStatus = localized("演示：不检查权限", "Fixture: permissions unchecked")
            automationStatus = localized("演示：无自动化", "Fixture: automation inactive")
            return
        }
        switch login?.status {
        case .enabled: loginStatus = localized("已启用", "Enabled")
        case .disabled: loginStatus = localized("已停用", "Disabled")
        case .requiresApproval: loginStatus = localized("需在登录项中批准", "Approval needed in Login Items")
        case let .unavailable(reason): loginStatus = reason.message(language: settings.language)
        case nil: loginStatus = localized("不可用", "Unavailable")
        }
        accessibilityStatus = AXIsProcessTrusted() ? localized("已授权", "Authorized") : localized("未授权（可选）", "Not authorized (optional)")
        switch platform?.tabbitAutomationStatus() {
        case .authorized: automationStatus = localized("已授权", "Authorized")
        case .needsConsent: automationStatus = localized("需要授权", "Permission needed")
        case .denied: automationStatus = localized("已拒绝，请检查自动化权限", "Denied — check Automation settings")
        default: automationStatus = localized("不可用", "Unavailable")
        }
    }
    func showSettings() {
        refreshStatus()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 630),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = localized("Char 设置", "Char Settings")
            window.collectionBehavior = [.fullScreenNone]
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(runtime: self))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // Release the hosting view and its preview clock when settings close.
        window.contentView = nil
        settingsWindow = nil
    }

    private func fixtureAnchor() -> ReturnAnchor {
        ReturnAnchor(id: "fixture-wechat", bundleIdentifier: MacOSPlatform.wechatBundleID, token: "fixture-only", accuracy: .application)
    }
    func publish() {
        let next = router.snapshot
        if let old = retainedAnchor, old.id != next.hold?.anchor.id { releaseOrigin(old) }
        if let anchor = next.hold?.anchor {
            badgeFadeGeneration += 1
            badgeFadeTimer?.invalidate(); badgeFadeTimer = nil
            sourceBadgeAnchor = anchor; sourceBadgeOpacity = 1
        } else if let old = retainedAnchor {
            fadeSourceBadge(old)
        }
        retainedAnchor = next.hold?.anchor
        if snapshot != next {
            let previous = snapshot
            snapshot = next
            for bubble in next.bubbles where previous.bubbles.first(where: { $0.workEnd == bubble.workEnd }) != bubble {
                let state = bubble.head.flatMap { $0.isPast ? nil : $0.reason.rawValue } ?? (bubble.pendingCount > 0 ? "pending" : "running")
                appearanceEvent("attention",workEnd: bubble.workEnd.rawValue,state: state)
            }
        }
        homeShortcut.updateHold(next.hold != nil)
        refreshHomeShortcutStatus()
        panel?.surface.refresh()
        statusBar?.refresh()
        for effect in router.drainEffects() {
            if effect == .playSound {
                if demo { demoSoundCount += 1 }
                else if let path = settings.audioFilePath, let sound = NSSound(contentsOfFile: path, byReference: true) { sound.play() }
                else { NSSound(named: NSSound.Name("Ping"))?.play() }
            }
        }
    }
    private func fadeSourceBadge(_ anchor: ReturnAnchor) {
        badgeFadeTimer?.invalidate()
        sourceBadgeAnchor = anchor; sourceBadgeOpacity = 1
        let began = Date()
        badgeFadeGeneration += 1
        let generation = badgeFadeGeneration
        badgeFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, generation == self.badgeFadeGeneration else { timer.invalidate(); return }
                let fraction = Date().timeIntervalSince(began) / 0.18
                self.sourceBadgeOpacity = CGFloat(max(0, 1 - fraction))
                if fraction >= 1 {
                    timer.invalidate(); self.badgeFadeTimer = nil; self.sourceBadgeAnchor = nil
                }
                self.panel.surface.pet.needsDisplay = true
            }
        }
    }

    private func scheduleFeedbackClear() {
        feedbackGeneration += 1
        let generation = feedbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, generation == self.feedbackGeneration else { return }
            self.router.clearNavigationFeedback(); self.publish()
        }
    }

    func setPetSize(_ size: Double) {
        companionPreferences.setSize(size)
        petSize = companionPreferences.petSize
        if let screen = panel.screen ?? NSScreen.main {
            position(on: screen, center: companionPreferences.center(in: screen.visibleFrame), placement: petPlacement, animated: false)
        }
        panel.surface.refresh()
        saveCompanionPreferences()
    }
    func showPet() { panel.orderFrontRegardless() }
    func setBubbleDistance(_ distance: Double) {
        companionPreferences.setBubbleDistance(distance)
        bubbleDistance = companionPreferences.bubbleDistance
        panel.surface.refresh()
        saveCompanionPreferences()
    }
    private func installDesktopTracking() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        guard !demo else { return }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackFocusedDisplay() }
        }
        if let displayTimer { RunLoop.main.add(displayTimer, forMode: .common) }
    }
    @objc private func workspaceActivated() { trackFocusedDisplay() }
    @objc private func spaceChanged() {
        trackFocusedDisplay()
        panel.surface.spaceFeedback()
    }
    private func trackFocusedDisplay() {
        // With one screen there can be no migration, so avoid repeated AX/CG window queries.
        guard appearanceBehavior?.followFocus != false, NSScreen.screens.count > 1, let id = platform?.foreground()?.displayID,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }) else { return }
        place(on: screen, animated: true)
    }

    func setPlacement(_ placement: PetPlacement) {
        petPlacement = placement
        companionPreferences.placement = placement
        if let screen = panel.screen ?? NSScreen.main {
            position(on: screen, center: petCenter(), placement: placement, animated: true, remember: true)
        }
        saveCompanionPreferences()
        appearanceEvent("placement")
    }
    private func petCenter() -> NSPoint {
        let pet = panel.surface.pet.frame
        return NSPoint(x: panel.frame.minX + pet.midX, y: panel.frame.minY + pet.midY)
    }
    func saveDraggedPosition() {
        let center = petCenter()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen else { return }
        let area = screen.visibleFrame
        let distances: [(PetPlacement, CGFloat)] = [(.left, abs(center.x-area.minX)), (.right, abs(center.x-area.maxX)),
            (.bottom, abs(center.y-area.minY)), (.top, abs(center.y-area.maxY))]
        let nearest = distances.min { $0.1 < $1.1 }!
        let previousPlacement = petPlacement
        let placement: PetPlacement = nearest.1 < (appearanceBehavior?.edgeSnapDistance ?? 64) ? nearest.0 : .desktop
        petPlacement = placement
        companionPreferences.placement = placement
        position(on: screen, center: center, placement: placement, animated: true, remember: true)
        saveCompanionPreferences()
        if previousPlacement != placement { appearanceEvent("placement") }
    }
    private func saveCompanionPreferences() {
        do { try JSONEncoder().encode(companionPreferences).write(to: companionPreferencesURL, options: .atomic) }
        catch { setupMessage = localized("无法保存桌宠位置：\(error.localizedDescription)", "Could not save pet position: \(error.localizedDescription)") }
    }
    private func position(on screen: NSScreen, center: NSPoint, placement: PetPlacement, animated: Bool, remember: Bool = false) {
        currentDisplay = displayKey(screen)
        let area = screen.visibleFrame
        let size = CompanionGeometry.canvasSize
        let pet = CompanionGeometry.petFrame(placement: placement, petSize: petSize)
        var point = center
        switch placement {
        case .desktop:
            point.x = min(max(point.x, area.minX + size.width/2), area.maxX-size.width/2)
            point.y = min(max(point.y, area.minY + size.height/2), area.maxY-size.height/2)
        case .left: point.x = area.minX + 8; point.y = min(max(point.y, area.minY+170), area.maxY-170)
        case .right: point.x = area.maxX - 8; point.y = min(max(point.y, area.minY+170), area.maxY-170)
        case .top: point.y = area.maxY - 8; point.x = min(max(point.x, area.minX+170), area.maxX-170)
        case .bottom: point.y = area.minY + 8; point.x = min(max(point.x, area.minX+170), area.maxX-170)
        }
        if remember { companionPreferences.remember(center: point, in: area) }
        let frame = NSRect(x: point.x-pet.midX, y: point.y-pet.midY, width: size.width, height: size.height)

        panel.transition(to: frame, placement: placement, animated: animated)
    }
    private func displayKey(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }
    private func place(on screen: NSScreen?, animated: Bool) {
        guard let screen else { return }
        let id = displayKey(screen)
        guard id != currentDisplay else { return }
        let point = companionPreferences.center(in: screen.visibleFrame)
        position(on: screen, center: point, placement: companionPreferences.placement, animated: animated)
    }
    private func runSmoke() async {
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data("Char fixture smoke failed: \(message)\n".utf8)); exit(1)
        }
        if CommandLine.arguments.contains("--capability-smoke") {
            do { try await runCapabilitySmoke() } catch { fail("capability integration: \(error)") }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--appearance-v2-check") {
            do { try await runAppearanceV2Check() } catch { fail("appearance v2: \(error)") }
            NSApp.terminate(nil); return
        }
        if CommandLine.arguments.contains("--appearance-edge-check") {
            do { try await runAppearanceEdgeCheck() } catch { fail("appearance edge: \(error)") }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--bubble-state-check") {
            for end in enabledWorkEnds { router.remove(workEnd: end) }
            var filtered = settings; filtered.filterSeconds = 10; filtered.soundEnabled = false
            router.updateSettings(filtered)
            setPlacement(.desktop)
            try? await Task.sleep(nanoseconds: 450_000_000)
            let epoch = Date()
            let key = SessionKey(workEnd: .pi, nativeID: "state-continuity-fixture")
            func event(_ seconds: Double, _ state: SessionState) -> ObservationEvent {
                ObservationEvent(key: key, target: SessionTarget(bundleIdentifier: "fixture-only"),
                                 timestamp: epoch.addingTimeInterval(seconds), state: state)
            }
            router.ingest([event(0, .running)]); router.advance(to: epoch); publish()
            guard let bubble = panel.surface.buttons.first(where: { $0.renderedWorkEnd == .pi }),
                  let shell = bubble.ownedShellImage else { fail("running continuity bubble missing") }
            let frame = bubble.frame
            let preview = CommandLine.arguments.contains("--bubble-state-preview")
            if preview { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            let cycles = preview ? 100 : 3
            for cycle in 0..<cycles {
                let start = Double(cycle * 20)
                router.ingest([event(start + 1, .stopped(.turnEnded))])
                router.advance(to: epoch.addingTimeInterval(start + 1)); publish()
                guard let fade = bubble.statusLayer.animation(forKey: "transition") as? CATransition,
                      fade.type == .fade else { fail("pending status missing compositor transition") }
                if !bubble.reducedMotion {
                    guard let settle = bubble.statusLayer.animation(forKey: "status-settle") as? CAAnimationGroup,
                          settle.animations?.count == 2 else { fail("pending status missing elastic settle") }
                }
                for _ in 0..<5 {
                    guard !bubble.isHidden, !bubble.graphicLayer.isHidden, bubble.graphicLayer.opacity == 1,
                          bubble.frame == frame, bubble.ownedShellImage === shell,
                          snapshot.bubbles.first?.pendingCount == 1, snapshot.bubbles.first?.count == 0,
                          bubble.statusLayer.contents != nil else { fail("filter interval hid or replaced the running bubble") }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                if preview { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                router.advance(to: epoch.addingTimeInterval(start + 11)); publish()
                guard !bubble.isHidden, bubble.graphicLayer.opacity == 1, bubble.frame == frame,
                      bubble.ownedShellImage === shell, snapshot.bubbles.first?.head?.reason == .turnEnded,
                      bubble.statusLayer.animation(forKey: "transition") != nil,
                      bubble.dismissalFragments(reducedMotion: false) != nil else { fail("completed state broke continuity or click artwork") }
                if preview { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                router.ignoreNext(for: .pi)
                router.ingest([event(start + 12, .running)]); router.advance(to: epoch.addingTimeInterval(start + 12)); publish()
                guard !bubble.isHidden, bubble.ownedShellImage === shell,
                      snapshot.bubbles.first?.runningCount == 1 else { fail("resume state broke continuity") }
                if preview { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
            bubble.reducedMotion = true
            router.ingest([event(Double(cycles * 20 + 1), .stopped(.question))]); router.advance(to: epoch.addingTimeInterval(Double(cycles * 20 + 1))); publish()
            guard bubble.statusLayer.animation(forKey: "status-settle") == nil,
                  let fade = bubble.statusLayer.animation(forKey: "transition") as? CATransition,
                  fade.duration == 0.12, bubble.graphicLayer.opacity == 1 else { fail("Reduce Motion continuity") }
            print("Char bubble continuity check passed: running → filtered stop → completed → running; stable shell/slot, status fade/settle, dismissal image and Reduce Motion")
            NSApp.terminate(nil); return
        }
        func iconPixels(_ image: NSImage?) -> Data? {
            guard let image else { return nil }
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.bitmapData!.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            let old = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 256, height: 256).fill()
            image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
            NSGraphicsContext.current = old
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        func iconsMatch(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
            guard let a = iconPixels(lhs), let b = iconPixels(rhs), a.count == b.count else { return false }
            // AppKit rebuilds the app icon's representations and antialiasing. Compare
            // visible pixels, allowing <1 eight-bit level of average error per channel.
            let error = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            return Double(error) / Double(a.count) < 1
        }
        if CommandLine.arguments.contains("--settings-preview-check") {
            func findPreview(in view: NSView) -> PetPreviewView? {
                if let preview = view as? PetPreviewView { return preview }
                return view.subviews.lazy.compactMap { findPreview(in: $0) }.first
            }
            var statusPublications = 0
            let subscription = $homeShortcutStatus.dropFirst().sink { _ in statusPublications += 1 }
            for _ in 0..<5 { publish() }
            guard statusPublications == 0 else { fail("unchanged shortcut status invalidated settings") }
            setLanguage(.chinese)
            guard statusPublications == 1, homeShortcutStatus == "Ctrl+B 未启用" else { fail("shortcut translation did not publish") }
            setLanguage(.english)
            guard statusPublications == 2, homeShortcutStatus == "Ctrl+B inactive" else { fail("shortcut translation did not restore") }
            subscription.cancel()
            showSettings()
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let content = settingsWindow?.contentView, let preview = findPreview(in: content) else { fail("settings preview missing") }
            preview.configure(reduceMotion: false)
            let initialElapsed = preview.animationElapsed
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard preview.isAnimating, preview.animationElapsed > initialElapsed else { fail("visible preview clock did not advance") }
            preview.isHidden = true
            let hiddenElapsed = preview.animationElapsed
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard preview.animationElapsed == hiddenElapsed else { fail("hidden preview kept rendering") }
            preview.isHidden = false
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard preview.animationElapsed > hiddenElapsed else { fail("visible preview did not resume rendering") }
            guard let skinStore, let sample = Bundle.main.resourceURL?.appendingPathComponent("Skins/example.charpet") else { fail("preview skin fixture missing") }
            do {
                let defaultArtwork = preview.artworkPixelData
                let skin = try skinStore.importPackage(at: sample)
                selectSkin(skin.id)
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard preview.artworkPixelData != nil, preview.artworkPixelData != defaultArtwork else { fail("preview did not update selected skin") }
                deleteSkin(skin.id)
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard preview.artworkPixelData == defaultArtwork else { fail("preview did not restore default skin") }
            } catch { fail("preview skin fixture: \(error)") }
            preview.configure(reduceMotion: true)
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !preview.isAnimating, preview.animationElapsed == 0 else { fail("Reduce Motion preview kept animating") }
            preview.configure(reduceMotion: false)
            guard preview.isAnimating else { fail("preview clock did not resume") }
            settingsWindow?.close()
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard settingsWindow == nil, preview.window == nil, !preview.isAnimating else { fail("closed preview retained its clock") }
            print("Char settings preview check passed: unchanged status gate/translation, visible/hidden clock, skin selection/restoration, Reduce Motion, resume, close cleanup")
            NSApp.terminate(nil); return
        }
        if CommandLine.arguments.contains("--appearance-icon-check") {
            guard let skinStore, let sample = Bundle.main.resourceURL?.appendingPathComponent("Skins/example.charpet") else { fail("icon fixture missing") }
            do {
                let originalApp = NSApp.applicationIconImage?.copy() as? NSImage
                let originalMenu = statusBar?.iconImage?.copy() as? NSImage
                let skin = try skinStore.importPackage(at: sample)
                selectSkin(skin.id)
                guard !iconsMatch(softwareIcon, originalApp) else { fail("icon fixture must distinguish default from authored artwork") }
                guard iconsMatch(NSApp.applicationIconImage, softwareIcon),
                      iconsMatch(statusBar?.iconImage, softwareIcon), statusBar?.representedSkinID == skin.id else { fail("targeted icon selection") }
                deleteSkin(skin.id)
                guard iconsMatch(NSApp.applicationIconImage, originalApp), iconsMatch(statusBar?.iconImage, originalMenu),
                      statusBar?.representedSkinID == "char.default" else { fail("targeted icon restoration") }
                print("Char appearance icon check passed: authored/default pixel content, menu binding and delete restoration")
                NSApp.terminate(nil); return
            } catch { fail("icon fixture: \(error)") }
        }
        if CommandLine.arguments.contains("--space-motion-check") {
            panel.surface.prepareSpaceAppearance()
            guard panel.surface.visualOpacity == 0,
                  panel.surface.sceneLayer?.opacity == 0 else { fail("hidden Space first frame is not transparent") }
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard panel.surface.isSpaceFeedbackActive, panel.surface.visualOpacity > 0,
                  panel.surface.visualOpacity < 1 else { fail("confirmed Space did not arrive") }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !panel.surface.isSpaceFeedbackActive, panel.surface.visualOpacity == 1 else { fail("arrival did not finish") }
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !panel.surface.isSpaceFeedbackActive, panel.surface.visualOpacity == 1 else { fail("already-visible Space replayed appearance") }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !panel.surface.isSpaceFeedbackActive, panel.surface.visualOpacity == 1 else { fail("visible Space did not remain continuous") }
            print("Char Space motion check passed: transparent preparation, confirmed arrival, no late visible replay")
            NSApp.terminate(nil); return
        }
        if CommandLine.arguments.contains("--orbit-path-check") {
            guard !panel.surface.reducesMotionForDiagnostics else {
                FileHandle.standardOutput.write(Data("Char orbit layer-path check NOT RUN: Reduce Motion is enabled; animated coverage skipped\n".utf8))
                exit(2)
            }
            setBubbleDistance(8)
            var findings: [String] = []
            for placement in PetPlacement.allCases {
                setPlacement(placement)
                try? await Task.sleep(nanoseconds: 300_000_000)
                let steps = Array(repeating: 1, count: WorkEnd.allCases.count) + Array(repeating: -1, count: WorkEnd.allCases.count) + [1, -1, 1, -1]
                for (index, step) in steps.enumerated() {
                    findings += panel.surface.orbitPathFindings(step: step)
                    // The second input retargets a live presentation; later steps settle.
                    try? await Task.sleep(nanoseconds: index < WorkEnd.allCases.count * 2 || step == -1 ? 230_000_000 : 40_000_000)
                }
            }
            guard findings.isEmpty else { fail("actual folded layer paths oppose input: \(findings.joined(separator: "; "))") }
            print("Char orbit layer-path check passed")
            NSApp.terminate(nil); return
        }
        guard snapshot.bubbles.count == WorkEnd.allCases.count, snapshot.bubbles.allSatisfy({ $0.count == 2 }) else { fail("initial bubbles") }
        guard snapshot.bubbles.first(where: { $0.workEnd == .codexCLI })?.head?.isPast == true else { fail("visible past head marker") }
        setBubbleDistance(8)
        guard panel.surface.capacity < snapshot.bubbles.count,
              let bubble = panel.surface.buttons.first(where: { !$0.isHidden && !$0.miniature }),
              case let .bubble(end) = bubble.kind else { fail("folded orbit fixture") }
        let oldFrame = bubble.frame
        guard panel.surface.cycleBubbles(by: 1), bubble.frame != oldFrame,
              bubble.renderedWorkEnd == end, bubble.hasOwnedImage,
              bubble.graphicLayer.animation(forKey: "orbit") != nil,
              bubble.accessibilityLabel()?.hasPrefix(end.title) == true else { fail("accepted orbit step did not animate owned artwork") }
        try? await Task.sleep(nanoseconds: 240_000_000)
        guard abs(bubble.presentationFrame.width - bubble.frame.width) < 0.5,
              abs(bubble.presentationFrame.midX - bubble.frame.midX) < 0.5 else { fail("orbit artwork failed to arrive") }
        guard let reducedBurst = bubble.dismissalFragments(reducedMotion: true),
              reducedBurst.sublayers?.count == 1,
              let reducedAnimation = reducedBurst.sublayers?.first?.animation(forKey: "dismissal") as? CAAnimationGroup,
              reducedAnimation.animations?.count == 1,
              reducedAnimation.animations?.first is CAKeyframeAnimation else { fail("Reduce Motion dismissal must be fade-only") }
        bubble.beginBubblePress()
        guard !bubble.finishBubblePress(atSurfacePoint: NSPoint(x: -100, y: -100)),
              snapshot.hold == nil, router.nextVisit(for: end)?.navigationOutcome == nil else { fail("outside bubble release navigated or created Hold") }
        let clickedKey = router.nextVisit(for: end)?.key
        bubble.beginBubblePress()
        guard bubble.finishBubblePress(atSurfacePoint: NSPoint(x: bubble.presentationFrame.midX, y: bubble.presentationFrame.midY)) else { fail("inside presented bubble release cancelled") }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard router.nextVisit(for: end)?.key != clickedKey, snapshot.navigationFeedback == .fallback,
              snapshot.bubbles.first(where: { $0.workEnd == end })?.count == 1,
              panel.surface.activeBurstFragmentCount > 0 else { fail("successful click dismissal / burst / remaining item") }
        _ = panel.surface.cycleBubbles(by: -1)
        setBubbleDistance(72)
        guard !panel.surface.canCycle, !panel.surface.cycleBubbles(by: 1),
              let savedOrbit = try? JSONDecoder().decode(CompanionPreferences.self, from: Data(contentsOf: companionPreferencesURL)),
              savedOrbit.bubbleDistance == 72 else { fail("distance capacity/persistence or unfolded scroll gate") }
        setBubbleDistance(20)
        let claudeCount = snapshot.bubbles.first(where: { $0.workEnd == .claudeCode })?.count ?? 0
        visit(.claudeCode)
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold?.anchor.accuracy == .application,
              snapshot.bubbles.first(where: { $0.workEnd == .claudeCode })?.count ?? 0 == claudeCount - 1,
              snapshot.navigationFeedback == .fallback else { fail("fallback dismissal / degraded Hold") }
        visit(.codexDesktop)
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold?.anchor.id == "fixture-wechat" else { fail("original anchor") }
        let beforeIgnore = snapshot.bubbles.first(where: { $0.workEnd == .pi })?.count ?? 0
        ignore(.pi)
        guard snapshot.bubbles.first(where: { $0.workEnd == .pi })?.count ?? 0 == beforeIgnore - 1 else { fail("head-only ignore") }
        let soundBeforeReturn = demoSoundCount
        guard homeShortcut.status == .registered else { fail("Hold shortcut registration") }
        fixtureHotKey?.fire()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold == nil, snapshot.navigationFeedback == .fallback, homeShortcut.status == .inactive else { fail("degraded return") }
        guard sourceBadgeAnchor != nil, sourceBadgeOpacity > 0, sourceBadgeOpacity < 1 else { fail("source badge fade") }
        petClicked() // The actual Hold is already gone; controls remain available during the graphic fade.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard sourceBadgeAnchor == nil, demoSoundCount == soundBeforeReturn else { fail("quiet fade completion") }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard panel.surface.activeBurstFragmentCount == 0 else { fail("burst layers did not clean up") }
        guard panel.surface.buttons.filter({ !$0.isHidden && !$0.miniature }).allSatisfy({ $0.frame.width >= 44 && $0.frame.height >= 44 && panel.surface.bounds.contains($0.frame) }) else { fail("visible hit target size") }
        let piID = pluginEntries.first { $0.plugin.workEnd == .pi }!.id
        setPlugin(piID, enabled: false)
        guard !snapshot.bubbles.contains(where: { $0.workEnd == .pi }) else { fail("disabled Agent still visible") }
        setPlugin(piID, enabled: true)
        guard !snapshot.bubbles.contains(where: { $0.workEnd == .pi }) else { fail("re-enabled Agent replayed history") }
        visit(.deepseekDesktop)
        try? await Task.sleep(nanoseconds: 100_000_000)
        deletePlugin("builtin.source.wechat")
        guard snapshot.hold?.anchor.id == "fixture-wechat", homeShortcut.status == .registered else { fail("generic origin was invalidated by plugin deletion") }
        endHold()
        restorePlugins()
        guard pluginEntries.contains(where: { $0.id == "builtin.source.wechat" }) else { fail("source restore") }
        setPetSize(64)
        guard petSize == 64, panel.surface.pet.frame.width == 64,
              let saved = try? JSONDecoder().decode(CompanionPreferences.self, from: Data(contentsOf: companionPreferencesURL)), saved.petSize == 64 else { fail("size apply/persistence") }
        setPetSize(48)
        for placement in PetPlacement.allCases {
            setPlacement(placement)
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard panel.alphaValue == 1, panel.surface.pet.motionScale == 1 else { fail("placement transition completion") }
            if let screen = panel.screen {
                let remembered = companionPreferences.center(in: screen.visibleFrame)
                guard hypot(petCenter().x - remembered.x, petCenter().y - remembered.y) < 0.5 else { fail("placement normalization after clamp") }
                let global = companionPreferences
                setPetSize(88)
                guard hypot(petCenter().x - remembered.x, petCenter().y - remembered.y) < 0.5,
                      companionPreferences.normalizedX == global.normalizedX,
                      companionPreferences.normalizedY == global.normalizedY else { fail("size changed shared placement") }
                setPetSize(48)
            }
        }
        setPlacement(.desktop)
        try? await Task.sleep(nanoseconds: 450_000_000)
        // A scene already visible after the system transition must never replay.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        guard !panel.surface.isSpaceFeedbackActive else { fail("visible Space replayed appearance") }
        try? await Task.sleep(nanoseconds: 900_000_000)
        panel.surface.prepareSpaceAppearance()
        guard panel.surface.visualOpacity == 0, panel.surface.sceneLayer?.opacity == 0 else { fail("hidden Space first frame visible") }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        try? await Task.sleep(nanoseconds: 70_000_000)
        guard panel.surface.isSpaceFeedbackActive, panel.surface.visualOpacity > 0, panel.surface.visualOpacity < 1 else { fail("Space notification arrival feedback") }
        panel.surface.prepareSpaceAppearance()
        guard !panel.surface.isSpaceFeedbackActive else { fail("second hidden cycle failed to interrupt arrival") }
        panel.surface.spaceFeedback()
        guard panel.surface.isSpaceFeedbackActive else { fail("second hidden cycle did not begin a fresh arrival") }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !panel.surface.isSpaceFeedbackActive, panel.surface.pet.spaceTuck == 0, panel.surface.visualOpacity == 1, panel.surface.sceneLayer?.opacity == 1, panel.alphaValue == 1 else { fail("Space feedback completion") }
        if let sample = Bundle.main.resourceURL?.appendingPathComponent("Skins/example.charpet"), let skinStore {
            do {
                let defaultIcon = NSApp.applicationIconImage?.copy() as? NSImage
                let defaultMenuIcon = statusBar?.iconImage?.copy() as? NSImage
                let skin = try skinStore.importPackage(at: sample)
                selectSkin(skin.id)
                guard customPetImage(clip: "idle", elapsed: 0) != nil else { fail("imported skin rendering") }
                guard !iconsMatch(softwareIcon, defaultIcon), iconsMatch(NSApp.applicationIconImage, softwareIcon),
                      iconsMatch(statusBar?.iconImage, softwareIcon), statusBar?.representedSkinID == skin.id else { fail("appearance software/menu icon did not follow selection") }
                let pet = panel.surface.pet
                pet.clip = "idle"; pet.clipElapsed = 0; pet.feedbackElapsed = nil
                router.clearNavigationFeedback(); publish()
                sourceBadgeAnchor = nil; sourceBadgeOpacity = 0
                pet.refreshPetArtwork()
                let withoutBadge = pet.artworkPixelData
                let staticFrame = customPetImage(clip: "idle", elapsed: 0)
                sourceBadgeAnchor = fixtureAnchor(); sourceBadgeOpacity = 1
                pet.refreshPetArtwork()
                let withBadge = pet.artworkPixelData
                guard staticFrame === customPetImage(clip: "idle", elapsed: 0),
                      withoutBadge != nil, withBadge != withoutBadge else { fail("static custom frame missed source badge addition") }
                sourceBadgeOpacity = 0.5; pet.refreshPetArtwork()
                guard pet.artworkPixelData != withBadge else { fail("static custom frame missed source badge fade") }
                sourceBadgeAnchor = nil; sourceBadgeOpacity = 0; pet.refreshPetArtwork()
                guard pet.artworkPixelData == withoutBadge else { fail("static custom frame retained removed source badge") }
                // A failed return requires an active Hold. This fixture has already
                // ended it, so exercise a failed visit to create navigation feedback.
                let navigationKey = SessionKey(workEnd: .claudeCode, nativeID: "fixture-static-navigation")
                router.ingest([ObservationEvent(key: navigationKey, target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable"),
                                                timestamp: Date(), state: .stopped(.question))])
                router.advance(to: Date())
                guard let attention = router.nextVisit(for: .claudeCode) else { fail("static frame navigation fixture missing") }
                router.completeVisit(key: attention.key, outcome: .unavailable, sourceAnchor: nil, at: Date())
                publish(); pet.refreshPetArtwork()
                guard snapshot.navigationFeedback == .unavailable else { fail("static frame navigation fixture did not create feedback") }
                guard pet.artworkPixelData != withoutBadge else { fail("static custom frame missed navigation feedback") }
                router.clearNavigationFeedback(); publish(); pet.refreshPetArtwork()
                guard pet.artworkPixelData == withoutBadge else { fail("static custom frame retained navigation feedback") }
                deleteSkin(skin.id)
                guard selectedSkinID == "char.default" else { fail("skin deletion fallback") }
                guard iconsMatch(NSApp.applicationIconImage, defaultIcon),
                      iconsMatch(statusBar?.iconImage, defaultMenuIcon),
                      statusBar?.representedSkinID == "char.default" else { fail("deleted skin did not restore software/menu icon") }
            } catch { fail("sample skin import: \(error)") }
        } else { fail("bundled sample missing") }
        do { try await runCapabilitySmoke() } catch { fail("capability integration: \(error)") }
        print("Char fixture smoke passed: \(WorkEnd.allCases.count) work ends, Ctrl+B 回城, past/fallback, first anchor, ignore, return, orbit targets, plugin hot unplug/source removal, five placements and bundled skin; no real integrations")
        NSApp.terminate(nil)
    }
}


@MainActor final class FixtureHomeHotKeyService: HomeHotKeyService {
    private var action: (@MainActor () -> Void)?
    func register(_ action: @escaping @MainActor () -> Void) -> Int32 { self.action = action; return 0 }
    func unregister() -> Int32 { action = nil; return 0 }
    func fire() { action?() }
}
