import Foundation
import CharCore
import CharPlatform

@MainActor func pluginPlatformChecks() async throws {
    let apps = MockApps(); let platform = MacOSPlatform(apps: apps, tabbit: MockTabbit(), vscode: MockVSCode())
    apps.live = [77]
    let browser = IntegrationPlugin(id: "test.browser", name: "Browser", kind: .source,
        bundleIdentifier: "com.test.browser", sourceAdapter: .application)
    var plugins = IntegrationPluginStore.builtIns + [browser]
    platform.configure(plugins: plugins)
    apps.current = ForegroundSnapshot(bundleIdentifier: browser.bundleIdentifier, processID: 77)
    let anchor = platform.captureSource()!
    assert(anchor.accuracy == .application)
    let outcome = await platform.returnToSource(anchor)
    assert(outcome == .fallback && apps.activations.last?.1 == 77)
    plugins.removeAll { $0.id == browser.id || $0.workEnd == .pi }
    platform.configure(plugins: plugins)
    assert(platform.isAnchorValid(anchor) == false && platform.captureSource() == nil)
    let disabled = await platform.activate(workEnd: .pi, target: SessionTarget(bundleIdentifier: "com.test.app"))
    assert(disabled == .unavailable)
    plugins.append(IntegrationPlugin(id: "test.pi", name: "pi in another terminal", kind: .agent,
        workEnd: .pi, bundleIdentifier: "com.test.terminal"))
    platform.configure(plugins: plugins)
    let visit = await platform.activate(workEnd: .pi, target: SessionTarget(bundleIdentifier: "com.test.app"))
    assert(visit == .fallback && apps.activations.last?.0 == "com.test.terminal")
    print("CharPlatform: enabled-source capture/PID return/removal and Agent destination override passed")
}
