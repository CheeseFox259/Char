import CharCore
import CharPlatform
import Foundation

@MainActor final class MockApps: ApplicationRuntime {
    var current: ForegroundSnapshot?
    var live: Set<Int32> = []
    var activationSucceeds = true
    var uniqueInstance = true
    var activations: [(String, Int32?)] = []

    func foreground() -> ForegroundSnapshot? { current }
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
    func captureActiveTabID() -> String? { capturedID }
    func contains(tabID: String) -> Bool { live.contains(tabID) }
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
    func captureFocusedTab() -> String? { capturedToken }
    func contains(token: String) -> Bool { live.contains(token) }
    func focus(token: String) -> Bool {
        if focusSucceeds { activeToken = token }
        return focusSucceeds
    }
    func isActive(token: String) -> Bool { activeToken == token }
}

@MainActor final class MockLogin: LoginService {
    var state: LoginItemState = .disabled
    var changes = 0
    func register() throws { changes += 1; state = .requiresApproval }
    func unregister() throws { changes += 1; state = .disabled }
}

@main struct PlatformChecks {
    @MainActor static func main() async {
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
        assert(platform.captureSource() == nil)
        assert(platform.focusContext(for: nil).isAgent)

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.tabbitBundleID, processID: 10)
        assert(platform.captureSource() == nil)
        tabbit.capturedID = "opaque-tab"
        tabbit.live = ["opaque-tab"]
        apps.uniqueInstance = false
        assert(platform.captureSource() == nil)
        apps.uniqueInstance = true
        let tabbitAnchor = platform.captureSource()!
        assert(tabbitAnchor.accuracy == .exact)
        assert(platform.isAnchorValid(tabbitAnchor))
        tabbit.activeID = "opaque-tab"
        assert(platform.focusContext(for: tabbitAnchor).sourceAnchorID == tabbitAnchor.id)
        tabbit.activeID = nil
        let tabbitReturn = await platform.returnToSource(tabbitAnchor)
        assert(tabbitReturn == .exact)
        tabbit.live = []
        assert(!platform.isAnchorValid(tabbitAnchor))
        let closedTabReturn = await platform.returnToSource(tabbitAnchor)
        assert(closedTabReturn == .unavailable)

        apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.vscodeBundleID, processID: 20)
        assert(platform.captureSource() == nil)
        vscode.capturedToken = "live-token"
        vscode.live = ["live-token"]
        let vscodeAnchor = platform.captureSource()!
        assert(vscodeAnchor.accuracy == .exact)
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
        assert(!platform.isAnchorValid(wechatAnchor))
        platform.release(wechatAnchor)

        let login = MockLogin()
        let controller = LoginItemController(service: login)
        assert(controller.status == .disabled)
        assert(try! controller.setEnabled(true) == .requiresApproval)
        assert(try! controller.setEnabled(true) == .requiresApproval)
        assert(login.changes == 1)
        assert(try! controller.setEnabled(false) == .disabled)
        print("CharPlatform: 7 contract groups passed without controlling user apps")
    }
}
