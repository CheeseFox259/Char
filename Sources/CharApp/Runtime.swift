import AppKit
import ApplicationServices
import UniformTypeIdentifiers
import SwiftUI
import CharCore
import CharObservations
import CharPlatform

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
    func poll() -> [ObservationEvent] { poller.poll() }
    func configure(enabled: Set<WorkEnd>) { poller.setEnabledWorkEnds(enabled) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: CompanionRuntime?
    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = CompanionRuntime()
        runtime?.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor final class CompanionRuntime: NSObject, ObservableObject {
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
    @Published var pluginEntries: [IntegrationPluginEntry] = []
    @Published var skins: [PetSkinManifest] = []
    @Published var selectedSkinID = "char.default"
    @Published var petPlacement: PetPlacement = .desktop
    private var companionPreferences = CompanionPreferences()
    private let companionPreferencesURL: URL
    @Published var settings: CharSettings
    @Published var snapshot: AttentionSnapshot
    @Published var setupMessage = ""
    @Published var loginStatus = ""
    @Published var accessibilityStatus = ""
    @Published var automationStatus = ""
    @Published var busy = false
    @Published var homeShortcutStatus = "回城仅在 Hold 中可用"
    private var homeShortcut: HomeShortcutController!
    private var fixtureHotKey: FixtureHomeHotKeyService?
    private var timer: Timer?
    private var polling = false
    private var retainedAnchor: ReturnAnchor?
    private(set) var sourceBadgeAnchor: ReturnAnchor?
    private(set) var sourceBadgeOpacity: CGFloat = 0
    private var badgeFadeTimer: Timer?
    private var badgeFadeGeneration = 0
    var panel: CompanionPanel!
    private var settingsWindow: NSWindow?
    private var currentDisplay: String?
    private var feedbackGeneration = 0
    private var responseGeneration = 0
    private var demoSoundCount = 0

    override init() {
        smoke = CommandLine.arguments.contains("--smoke")
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
        catch { loaded = CharSettings(); loadMessage = "Could not load preferences: \(error.localizedDescription)" }
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
        else { setupMessage = "插件目录无法加载；请检查本地配置。" }
        platform?.configure(plugins: pluginEntries.filter(\.enabled).map(\.plugin))
        refreshSkins()
        if let data = try? Data(contentsOf: companionPreferencesURL),
           let saved = try? JSONDecoder().decode(CompanionPreferences.self, from: data) {
            companionPreferences = saved; petPlacement = saved.placement
        }

    }

    func start() {
        panel = CompanionPanel(runtime: self)
        place(on: NSScreen.main ?? NSScreen.screens.first, animated: false)
        panel.orderFrontRegardless()
        if demo { injectFixtures() }
        else {
            refreshStatus()
            if settings.launchAtLogin {
                do { _ = try login?.setEnabled(true) } catch { setupMessage = error.localizedDescription }
                refreshStatus()
            }
        }
        Task {
            await worker?.configure(enabled: enabledWorkEnds)
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
        let events = await worker?.poll() ?? []
        router.ingest(events.filter { enabledWorkEnds.contains($0.key.workEnd) }) // A complete sleep/wake batch precedes any focus or time advancement.
        if let platform {
            if let anchor = router.snapshot.hold?.anchor, platform.isAnchorValid(anchor) == false { router.invalidateAnchor(id: anchor.id) }
            router.updateFocus(platform.focusContext(for: router.snapshot.hold?.anchor), at: Date())
            if let id = platform.foreground()?.displayID,
               let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }) {
                place(on: screen, animated: true)
            }
        } else { router.advance(to: Date()) }
        publish()
    }

    func visit(_ workEnd: WorkEnd) {
        guard !busy, let item = router.nextVisit(for: workEnd) else { return }
        busy = true
        Task {
            let source = router.snapshot.hold == nil ? (demo ? fixtureAnchor() : platform?.captureSource()) : nil
            let outcome: NavigationOutcome
            if let platform { outcome = await platform.activate(workEnd: workEnd, target: item.target) }
            else { outcome = .fallback }
            router.completeVisit(key: item.key, outcome: outcome, sourceAnchor: source, at: Date())
            if let source, router.snapshot.hold?.anchor.id != source.id { platform?.release(source) }
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
    private func refreshHomeShortcutStatus() {
        switch homeShortcut.status {
        case .inactive: homeShortcutStatus = "Ctrl+B 未注册；保存来源后启用回城"
        case .registered: homeShortcutStatus = smoke ? "Fixture：模拟 Ctrl+B 回城" : "Ctrl+B 已注册，可回城"
        case let .failed(code): homeShortcutStatus = "Ctrl+B 注册失败（系统错误 \(code)）。可能与其他应用冲突；可重试，或点击桌宠回城。"
        }
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
        Task {
            let outcome: NavigationOutcome
            if let platform { outcome = await platform.returnToSource(anchor) }
            else { outcome = anchor.accuracy == .application ? .fallback : .exact }
            router.completeReturn(outcome: outcome)
            busy = false; publish(); scheduleFeedbackClear()
        }
    }

    func endHold() { router.endHold(); publish() }
    func toggleMute() { settings.soundEnabled.toggle(); saveSettings() }
    func saveSettings() {
        settings = settings.normalized()
        router.updateSettings(settings)
        do { try store.save(settings) } catch { setupMessage = error.localizedDescription }
        publish()
    }
    func setLogin(_ enabled: Bool) {
        guard !demo else { return }
        do {
            _ = try login?.setEnabled(enabled)
            settings.launchAtLogin = enabled
            saveSettings()
        } catch { setupMessage = error.localizedDescription }
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
        if picker.runModal() == .OK, let path = picker.url?.path {
            guard NSSound(contentsOfFile: path, byReference: true) != nil else {
                setupMessage = "The selected audio file cannot be played by macOS."; return
            }
            settings.audioFilePath = path; saveSettings()
        }
    }
    func refreshStatus() {
        guard !demo else {
            loginStatus = "Fixture mode — login unchanged"
            accessibilityStatus = "Fixture mode — no permission checks"
            automationStatus = "Fixture mode — no automation"
            return
        }
        switch login?.status {
        case .enabled: loginStatus = "Enabled"
        case .disabled: loginStatus = "Disabled"
        case .requiresApproval: loginStatus = "Requires approval in System Settings → General → Login Items"
        case let .unavailable(message): loginStatus = message
        case nil: loginStatus = "Unavailable"
        }
        accessibilityStatus = AXIsProcessTrusted() ? "Authorized" : "Not authorized — focused-display tracking unavailable"
        switch platform?.tabbitAutomationStatus() {
        case .authorized: automationStatus = "Authorized"
        case .needsConsent: automationStatus = "Permission needed for exact tab return"
        case .denied: automationStatus = "Denied — enable Char in Privacy & Security → Automation"
        default: automationStatus = "Unavailable — Tabbit may not be running"
        }
    }
    func showSettings() {
        refreshStatus()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 630),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Char Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(runtime: self))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func fixtureAnchor() -> ReturnAnchor {
        ReturnAnchor(id: "fixture-wechat", bundleIdentifier: MacOSPlatform.wechatBundleID, token: "fixture-only", accuracy: .application)
    }
    func publish() {
        let next = router.snapshot
        if let old = retainedAnchor, old.id != next.hold?.anchor.id { platform?.release(old) }
        if let anchor = next.hold?.anchor {
            badgeFadeGeneration += 1
            badgeFadeTimer?.invalidate(); badgeFadeTimer = nil
            sourceBadgeAnchor = anchor; sourceBadgeOpacity = 1
        } else if let old = retainedAnchor {
            fadeSourceBadge(old)
        }
        retainedAnchor = next.hold?.anchor
        snapshot = next
        homeShortcut.updateHold(next.hold != nil)
        refreshHomeShortcutStatus()
        panel?.surface.refresh()
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

    func setPlacement(_ placement: PetPlacement) {
        petPlacement = placement
        companionPreferences.placement = placement
        if let screen = panel.screen ?? NSScreen.main {
            position(on: screen, center: petCenter(), placement: placement, animated: true)
        }
        saveCompanionPreferences()
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
        let placement: PetPlacement = nearest.1 < 64 ? nearest.0 : .desktop
        petPlacement = placement
        companionPreferences.placement = placement
        position(on: screen, center: center, placement: placement, animated: true)
        saveCompanionPreferences()
    }
    private func saveCompanionPreferences() {
        do { try JSONEncoder().encode(companionPreferences).write(to: companionPreferencesURL, options: .atomic) }
        catch { setupMessage = "无法保存桌宠位置：\(error.localizedDescription)" }
    }
    private func position(on screen: NSScreen, center: NSPoint, placement: PetPlacement, animated: Bool) {
        currentDisplay = displayKey(screen)
        let area = screen.visibleFrame
        let size = CompanionGeometry.canvasSize
        let pet = CompanionGeometry.petFrame(placement: placement)
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
        let frame = NSRect(x: point.x-pet.midX, y: point.y-pet.midY, width: size.width, height: size.height)
        companionPreferences.displays[currentDisplay!] = CompanionPosition(x: point.x, y: point.y, placement: placement)
        panel.transition(to: frame, placement: placement, animated: animated)
    }
    private func displayKey(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }
    private func place(on screen: NSScreen?, animated: Bool) {
        guard let screen else { return }
        let id = displayKey(screen)
        guard id != currentDisplay else { return }
        let saved = companionPreferences.displays[id]
        let placement = saved?.placement ?? companionPreferences.placement
        petPlacement = placement
        let point = NSPoint(x: saved?.x ?? screen.visibleFrame.maxX-200,
                            y: saved?.y ?? screen.visibleFrame.minY+200)
        position(on: screen, center: point, placement: placement, animated: animated)
    }
    private func runSmoke() async {
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data("Char fixture smoke failed: \(message)\n".utf8)); exit(1)
        }
        guard snapshot.bubbles.count == WorkEnd.allCases.count, snapshot.bubbles.allSatisfy({ $0.count == 2 }) else { fail("initial bubbles") }
        guard snapshot.bubbles.first(where: { $0.workEnd == .codexCLI })?.head?.isPast == true else { fail("visible past head marker") }
        visit(.claudeCode)
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold?.anchor.accuracy == .application,
              router.nextVisit(for: .claudeCode)?.navigationOutcome == .fallback else { fail("fallback visit / degraded Hold") }
        visit(.codexDesktop)
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold?.anchor.id == "fixture-wechat" else { fail("original anchor") }
        ignore(.claudeCode)
        guard snapshot.bubbles.first(where: { $0.workEnd == .claudeCode })?.count == 1 else { fail("head-only ignore") }
        let soundBeforeReturn = demoSoundCount
        guard homeShortcut.status == .registered else { fail("Hold shortcut registration") }
        fixtureHotKey?.fire()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard snapshot.hold == nil, snapshot.navigationFeedback == .fallback, homeShortcut.status == .inactive else { fail("degraded return") }
        guard sourceBadgeAnchor != nil, sourceBadgeOpacity > 0, sourceBadgeOpacity < 1 else { fail("source badge fade") }
        petClicked() // The actual Hold is already gone; controls remain available during the graphic fade.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard sourceBadgeAnchor == nil, demoSoundCount == soundBeforeReturn else { fail("quiet fade completion") }
        guard panel.surface.buttons.filter({ !$0.isHidden && !$0.miniature }).allSatisfy({ $0.frame.width >= 44 && $0.frame.height >= 44 && panel.surface.bounds.contains($0.frame) }) else { fail("visible hit target size") }
        let piID = pluginEntries.first { $0.plugin.workEnd == .pi }!.id
        setPlugin(piID, enabled: false)
        guard !snapshot.bubbles.contains(where: { $0.workEnd == .pi }) else { fail("disabled Agent still visible") }
        setPlugin(piID, enabled: true)
        guard !snapshot.bubbles.contains(where: { $0.workEnd == .pi }) else { fail("re-enabled Agent replayed history") }
        visit(.deepseekDesktop)
        try? await Task.sleep(nanoseconds: 100_000_000)
        deletePlugin("builtin.source.wechat")
        guard snapshot.hold == nil, homeShortcut.status == .inactive else { fail("source deletion retained Hold") }
        restorePlugins()
        guard pluginEntries.contains(where: { $0.id == "builtin.source.wechat" }) else { fail("source restore") }
        for placement in PetPlacement.allCases {
            setPlacement(placement)
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard panel.alphaValue == 1, panel.surface.pet.motionScale == 1 else { fail("placement transition completion") }
        }
        setPlacement(.desktop)
        if let sample = Bundle.main.resourceURL?.appendingPathComponent("Skins/example.charpet"), let skinStore {
            do {
                let skin = try skinStore.importPackage(at: sample)
                selectSkin(skin.id)
                guard customPetImage(clip: "idle", elapsed: 0) != nil else { fail("imported skin rendering") }
                deleteSkin(skin.id)
                guard selectedSkinID == "char.default" else { fail("skin deletion fallback") }
            } catch { fail("sample skin import: \(error)") }
        } else { fail("bundled sample missing") }
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
