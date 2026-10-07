import CharCore
import CharPlatform
import Foundation
import CoreGraphics
import ServiceManagement

@MainActor final class MockApps: ApplicationRuntime {
    var current: ForegroundSnapshot?
    var live: Set<Int32> = []
    var activationSucceeds = true
    var uniqueInstance = true
    var activations: [(String, Int32?)] = []
    var geometryQueries = 0
    var identityQueries = 0

    func foregroundApplication() -> ForegroundSnapshot? {
        identityQueries += 1
        return current.map { ForegroundSnapshot(bundleIdentifier: $0.bundleIdentifier, processID: $0.processID) }
    }
    func foreground() -> ForegroundSnapshot? { geometryQueries += 1; return current }
    func isRunning(bundleID: String, processID: Int32) -> Bool { live.contains(processID) }
    func hasUniqueRunningInstance(bundleID: String) -> Bool { uniqueInstance }
    func activate(bundleID: String, preferredProcessID: Int32?) async -> Bool {
        activations.append((bundleID, preferredProcessID))
        if activationSucceeds, let pid = preferredProcessID ?? live.first {
            current = ForegroundSnapshot(bundleIdentifier: bundleID, processID: pid)
        }
        return activationSucceeds
    }
}

@MainActor final class MockTabbit: TabbitControlling {
    var capturedID: String?
    var live: Set<String> = []
    var activeID: String?
    var focusSucceeds = true
    var queryAvailable = true
    func captureActiveTabID() -> String? { capturedID }
    func contains(tabID: String) -> Bool? { queryAvailable ? live.contains(tabID) : nil }
    func focus(tabID: String) -> Bool {
        if focusSucceeds { activeID = tabID }
        return focusSucceeds
    }
    func isActive(tabID: String) -> Bool { activeID == tabID }
}

@MainActor final class MockVSCode: VSCodeControlling {
    var capturedToken: String?
    var live: Set<String> = []
    var activeToken: String?
    var focusSucceeds = true
    var queryAvailable = true
    func captureFocusedTab() -> String? { capturedToken }
    func contains(token: String) -> Bool? { queryAvailable ? live.contains(token) : nil }
    func focus(token: String) -> Bool {
        if focusSucceeds { activeToken = token }
        return focusSucceeds
    }
    func isActive(token: String) -> Bool { activeToken == token }
}

@MainActor final class MockLogin: LoginService {
    var state: LoginItemState = .disabled
    var changes = 0
    var failure: LoginItemError?
    func register() throws { if let failure { throw failure }; changes += 1; state = .requiresApproval }
    func unregister() throws { changes += 1; state = .disabled }
}

@main struct PlatformChecks {
    @MainActor static func main() async {
        if ProcessInfo.processInfo.environment["CHAR_NATIVE_HOTKEY_CHECK"] == "1" {
            do { try nativeHomeDispatchCheck() }
            catch { print("Native Carbon contract failed: \(error)"); exit(1) }
            return
        }
        assert(MainAppLoginService.state(for: .notFound) == .disabled, "a packaged unregistered main app must be allowed to register")
        let left = DisplayGeometry(id: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let right = DisplayGeometry(id: 2, bounds: CGRect(x: 150, y: 0, width: 100, height: 100))
        let front = WindowGeometry(processID: 40, number: 5, layer: 0, bounds: CGRect(x: 160, y: 10, width: 80, height: 80))
        let other = WindowGeometry(processID: 99, number: 6, layer: 0, bounds: left.bounds)
        assert(DisplayFocusGeometry.windowBounds(axBounds: nil, processID: 40, windows: [other, front]) == front.bounds, "missing AX authorization must not stop geometry following")
        assert(DisplayFocusGeometry.displayID(for: CGRect(x: 50, y: 10, width: 140, height: 80), displays: [left, right]) == 1, "window center in screen gap must use actual overlap")
        assert(DisplayFocusGeometry.windowBounds(axBounds: nil, processID: 41, windows: [other, front]) == nil, "never use another application's geometry")
        assert(DisplayFocusGeometry.windowBounds(axBounds: left.bounds, processID: 40, windows: [front]) == left.bounds, "authorized focused-window geometry has precedence")
        let overlay = WindowGeometry(processID: 40, number: 7, layer: 3, bounds: left.bounds)
        let empty = WindowGeometry(processID: 40, number: 8, layer: 0, bounds: .zero)
        assert(DisplayFocusGeometry.windowBounds(axBounds: nil, processID: 40, windows: [overlay, empty, front]) == front.bounds, "ignore overlays and empty windows")
        assert(DisplayFocusGeometry.displayID(for: CGRect(x: 300, y: 0, width: 10, height: 10), displays: [left, right]) == nil, "offscreen windows do not follow a guessed display")
        let apps = MockApps()
        let tabbit = MockTabbit()
        let vscode = MockVSCode()
        let platform = MacOSPlatform(apps: apps, tabbit: tabbit, vscode: vscode)
        apps.live = [10, 20, 30]
        let target = SessionTarget(bundleIdentifier: "ignored.example", tmuxPaneID: "%5")

        let claudeVisit = await platform.activate(workEnd: .claudeCode, target: target)
        assert(claudeVisit == .fallback)
        assert(apps.activations.last?.0 == MacOSPlatform.warpBundleID)
        let desktopVisit = await platform.activate(workEnd: .codexDesktop, target: target)
        assert(desktopVisit == .fallback)
        assert(apps.activations.last?.0 == MacOSPlatform.codexBundleID)
        apps.activationSucceeds = false
        let failedVisit = await platform.activate(workEnd: .codexCLI, target: target)
        assert(failedVisit == .unavailable)
        apps.activationSucceeds = true

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.warpBundleID, processID: 10, windowNumber: 5, displayID: 2)
        assert(platform.foreground()?.displayID == 2)
        let geometryQueries = apps.geometryQueries
        assert(platform.captureSource()?.accuracy == .application)
        assert(platform.focusContext(for: nil).isAgent)
        assert(apps.geometryQueries == geometryQueries && apps.identityQueries == 2, "capture and route checks must use identity without window geometry")

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.tabbitBundleID, processID: 10)
        assert(platform.captureSource()?.accuracy == .application)
        tabbit.capturedID = "opaque-tab"
        tabbit.live = ["opaque-tab"]
        apps.uniqueInstance = false
        assert(platform.captureSource()?.accuracy == .application)
        apps.uniqueInstance = true
        let tabbitAnchor = platform.captureSource()!
        assert(tabbitAnchor.accuracy == .exact)
        assert(platform.isAnchorValid(tabbitAnchor) == true)
        tabbit.activeID = "opaque-tab"
        assert(platform.focusContext(for: tabbitAnchor).sourceAnchorID == tabbitAnchor.id)
        tabbit.activeID = nil
        let tabbitReturn = await platform.returnToSource(tabbitAnchor)
        assert(tabbitReturn == .exact)
        tabbit.queryAvailable = false
        assert(platform.isAnchorValid(tabbitAnchor) != false, "Temporary Tabbit query failure invalidated a live source")
        let unavailableTabbitReturn = await platform.returnToSource(tabbitAnchor)
        assert(unavailableTabbitReturn == .unavailable)
        tabbit.queryAvailable = true
        assert(platform.isAnchorValid(tabbitAnchor) == true)
        tabbit.live = []
        assert(platform.isAnchorValid(tabbitAnchor) == false)
        let closedTabReturn = await platform.returnToSource(tabbitAnchor)
        assert(closedTabReturn == .unavailable)

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.vscodeBundleID, processID: 20)
        assert(platform.captureSource()?.accuracy == .application)
        vscode.capturedToken = "live-token"
        vscode.live = ["live-token"]
        let vscodeAnchor = platform.captureSource()!
        assert(vscodeAnchor.accuracy == .exact)
        vscode.queryAvailable = false
        assert(platform.isAnchorValid(vscodeAnchor) != false, "Temporary VS Code query failure invalidated a live source")
        let unavailableVSCodeReturn = await platform.returnToSource(vscodeAnchor)
        assert(unavailableVSCodeReturn == .unavailable)
        vscode.queryAvailable = true
        assert(platform.isAnchorValid(vscodeAnchor) == true)
        vscode.focusSucceeds = false
        let vscodeFallback = await platform.returnToSource(vscodeAnchor)
        assert(vscodeFallback == .fallback)
        vscode.focusSucceeds = true
        let vscodeReturn = await platform.returnToSource(vscodeAnchor)
        assert(vscodeReturn == .exact)

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.wechatBundleID, processID: 30)
        let wechatAnchor = platform.captureSource()!
        assert(wechatAnchor.accuracy == .application)
        assert(platform.focusContext(for: wechatAnchor).sourceAnchorID == wechatAnchor.id)
        let wechatReturn = await platform.returnToSource(wechatAnchor)
        assert(wechatReturn == .fallback)
        apps.live.remove(30)
        assert(platform.isAnchorValid(wechatAnchor) == false)
        platform.release(wechatAnchor)
        assert(apps.geometryQueries == geometryQueries, "exact/application anchors and focus checks must not enumerate windows")

        let login = MockLogin()
        let controller = LoginItemController(service: login)
        assert(controller.status == .disabled)
        assert(try! controller.setEnabled(true) == .requiresApproval)
        assert(try! controller.setEnabled(true) == .requiresApproval)
        assert(login.changes == 1)
        assert(try! controller.setEnabled(false) == .disabled)
        login.state = .unavailable(.notPackaged)
        do { _ = try controller.setEnabled(true); assertionFailure("unavailable login registered") }
        catch let failure as LoginItemError {
            assert(failure == .unavailable(.notPackaged))
            assert(failure.message(language: .chinese) == "登录时启动需要打包的 Char.app。")
            assert(failure.message(language: .english) == "Launch-at-login requires the packaged Char.app.")
        } catch { assertionFailure("login failure lost its typed reason") }
        let diagnostic = "OS diagnostic 42"
        let failure = LoginItemError.failed(diagnostic)
        assert(failure.message(language: .chinese) == "无法更新登录时启动：" + diagnostic)
        assert(failure.message(language: .english) == "Could not update launch-at-login: " + diagnostic)
        login.state = .disabled
        login.failure = .notPackaged
        do { _ = try controller.setEnabled(true); assertionFailure("login failure ignored") }
        catch let failure as LoginItemError { assert(failure == .notPackaged, "typed service error must not be wrapped in an English string") }
        catch { assertionFailure("unexpected login error") }
        login.failure = nil
        assert(try! controller.setEnabled(true) == .requiresApproval, "successful retry remains available")
        try! await pluginPlatformChecks()
        try! petSkinChecks()
        try! petSkinV2Checks()
        try! homeShortcutChecks()
        try! await workEndDestinationChecks()
        print("CharPlatform: 8 contract groups passed without controlling user apps")
    }
}
