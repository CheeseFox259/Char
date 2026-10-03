import Foundation
import CharCore
import CharPlatform

@MainActor final class MockHomeHotKey: HomeHotKeyService {
    var result: Int32 = 0
    var releaseResult: Int32 = 0
    var registrations = 0
    var releases = 0
    var action: (@MainActor () -> Void)?
    func register(_ action: @escaping @MainActor () -> Void) -> Int32 {
        registrations += 1
        if result == 0 { self.action = action }
        return result
    }
    func unregister() -> Int32 {
        releases += 1
        if releaseResult == 0 { action = nil }
        return releaseResult
    }
    func fire() { action?() }
}

enum HomeCheckFailure: Error { case failed(String) }
@MainActor func checkHome(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw HomeCheckFailure.failed(message) }
}

@MainActor func homeShortcutChecks() throws {
    let service = MockHomeHotKey()
    var returns = 0
    let shortcut = HomeShortcutController(service: service) { returns += 1 }
    shortcut.updateHold(false)
    try checkHome(service.registrations == 0 && shortcut.status == .inactive, "ordinary state must not register")
    shortcut.updateHold(true)
    shortcut.updateHold(true)
    try checkHome(service.registrations == 1 && shortcut.status == .registered, "one registration per Hold")
    service.fire()
    try checkHome(returns == 1, "shortcut invokes return action")
    service.releaseResult = -1
    shortcut.updateHold(false)
    service.fire()
    try checkHome(returns == 1 && shortcut.status == .failed(-1), "failed unregister cannot return without Hold")
    service.releaseResult = 0
    shortcut.updateHold(false)
    try checkHome(shortcut.status == .inactive && service.action == nil, "unregister retry releases shortcut")
    service.result = -9878
    shortcut.updateHold(true)
    try checkHome(shortcut.status == .failed(-9878), "registration conflict surfaces status")
    shortcut.updateHold(true)
    try checkHome(service.registrations == 2, "failure does not busy-loop registrations")
    service.result = 0
    shortcut.retry()
    service.fire()
    try checkHome(shortcut.status == .registered && returns == 2, "explicit retry succeeds")
    shortcut.updateHold(false)
    shortcut.retry()
    try checkHome(shortcut.status == .inactive && service.registrations == 3, "retry outside Hold does not register")
    print("CharPlatform: Hold-only shortcut registration, failure, retry and gated action checks passed")
}

@MainActor func workEndDestinationChecks() async throws {
    let apps = MockApps()
    apps.live = [10]
    let platform = MacOSPlatform(apps: apps, tabbit: MockTabbit(), vscode: MockVSCode())
    let expected: [WorkEnd: String] = [.claudeCode: MacOSPlatform.warpBundleID, .codexCLI: MacOSPlatform.warpBundleID,
        .codexDesktop: MacOSPlatform.codexBundleID, .deepseekDesktop: MacOSPlatform.deepseekBundleID,
        .kimiCLI: MacOSPlatform.warpBundleID, .kimiDesktop: MacOSPlatform.kimiBundleID, .pi: MacOSPlatform.warpBundleID]
    for end in WorkEnd.allCases {
        let result = await platform.activate(workEnd: end, target: SessionTarget(bundleIdentifier: "untrusted.destination"))
        try checkHome(result == .fallback && apps.activations.last?.0 == expected[end], "owning application for \(end)")
        try checkHome(platform.focusContext(for: nil).isAgent, "Agent app pauses Hold grace for \(end)")
    }
    print("CharPlatform: seven work-end destinations passed without tmux or user app activation")
}
