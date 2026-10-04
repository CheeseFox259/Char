import Foundation
import CharCore
import CharPlatform

@MainActor func pluginPlatformChecks() async throws {
    let apps = MockApps(); let platform = MacOSPlatform(apps: apps, tabbit: MockTabbit(), vscode: MockVSCode())
    apps.live = [77]
    let browser = IntegrationPlugin(id: "test.browser", name: "Browser",
        bundleIdentifier: "com.test.browser", returnAdapter: .application)
    var plugins = IntegrationPluginStore.builtIns + [browser]
    platform.configure(plugins: plugins)
    apps.current = ForegroundSnapshot(bundleIdentifier: browser.bundleIdentifier, processID: 77)
    let anchor = platform.captureSource()!
    assert(anchor.accuracy == .application)
    let outcome = await platform.returnToSource(anchor)
    assert(outcome == .fallback && apps.activations.last?.1 == 77)
    plugins.removeAll { $0.id == browser.id || $0.workEnd == .pi }
    platform.configure(plugins: plugins)
    assert(platform.isAnchorValid(anchor) == true && platform.captureSource()?.accuracy == .application)
    let disabled = await platform.activate(workEnd: .pi, target: SessionTarget(bundleIdentifier: "com.test.app"))
    assert(disabled == .unavailable)
    plugins.append(IntegrationPlugin(id: "test.pi", name: "pi in another terminal",
        workEnd: .pi, bundleIdentifier: "com.test.terminal"))
    platform.configure(plugins: plugins)
    let visit = await platform.activate(workEnd: .pi, target: SessionTarget(bundleIdentifier: "com.test.app"))
    assert(visit == .fallback && apps.activations.last?.0 == "com.test.terminal")
    // Agent origins need no source allowlist and survive observation disable.
    apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.warpBundleID, processID: 77)
    let agentOrigin = platform.captureSource()!
    assert(agentOrigin.accuracy == .application)
    platform.configure(plugins: [])
    assert(platform.isAnchorValid(agentOrigin) == true)
    assert(platform.focusContext(for: agentOrigin).sourceAnchorID == agentOrigin.id)
    let agentReturn = await platform.returnToSource(agentOrigin)
    assert(agentReturn == .fallback)
    apps.current = ForegroundSnapshot(bundleIdentifier: "com.cheesefox.char", processID: 77)
    assert(platform.captureSource() == nil)
    let tabbit = MockTabbit(); tabbit.capturedID = "private-id"; tabbit.live = ["private-id"]
    let exactPlatform = MacOSPlatform(apps: apps, tabbit: tabbit, vscode: MockVSCode())
    apps.current = ForegroundSnapshot(bundleIdentifier: MacOSPlatform.tabbitBundleID, processID: 77)
    let exact = exactPlatform.captureSource()!
    exactPlatform.configure(plugins: [])
    assert(exactPlatform.isAnchorValid(exact) == false)
    assert(exactPlatform.captureSource()?.accuracy == .application)
    print("CharPlatform: free capture, Agent PID return, observer independence, precise removal and destination override passed")
}
