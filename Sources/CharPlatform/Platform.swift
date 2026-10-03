import Foundation
import CharCore

public struct ForegroundSnapshot: Equatable, Sendable {
    public let bundleIdentifier: String
    public let processID: Int32
    public let windowNumber: UInt32?
    public let displayID: UInt32?

    public init(bundleIdentifier: String, processID: Int32, windowNumber: UInt32? = nil, displayID: UInt32? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.windowNumber = windowNumber
        self.displayID = displayID
    }
}

@MainActor public protocol ApplicationRuntime {
    func foreground() -> ForegroundSnapshot?
    func isRunning(bundleID: String, processID: Int32) -> Bool
    func hasUniqueRunningInstance(bundleID: String) -> Bool
    func activate(bundleID: String, preferredProcessID: Int32?) async -> Bool
}

@MainActor public protocol TabbitControlling {
    /// Returns only an opaque tab ID; never URL, title, or page content.
    func captureActiveTabID() -> String?
    /// nil means the integration could not verify source lifetime.
    func contains(tabID: String) -> Bool?
    func focus(tabID: String) -> Bool
    func isActive(tabID: String) -> Bool
}

@MainActor public protocol VSCodeControlling {
    /// Returns a token only when the extension can identify one active live tab.
    func captureFocusedTab() -> String?
    /// nil means the integration could not verify source lifetime.
    func contains(token: String) -> Bool?
    func focus(token: String) -> Bool
    func isActive(token: String) -> Bool
}

@MainActor public final class MacOSPlatform {
    public static let warpBundleID = "dev.warp.Warp-Stable"
    public static let codexBundleID = "com.openai.codex"
    public static let deepseekBundleID = "com.deepseek.dsh"
    public static let kimiBundleID = "com.kimi.code.desktop"
    public static let tabbitBundleID = "com.tabbit-ai.Tabbit"
    public static let wechatBundleID = "com.tencent.xinWeChat"
    public static let vscodeBundleID = "com.microsoft.VSCode"

    private enum Captured {
        case tabbit(processID: Int32, tabID: String)
        case vscode(processID: Int32, token: String)
        case wechat(processID: Int32)
    }

    private let apps: any ApplicationRuntime
    private let tabbit: any TabbitControlling
    private let vscode: any VSCodeControlling
    private var anchors: [String: Captured] = [:]

    public init(apps: any ApplicationRuntime, tabbit: any TabbitControlling, vscode: any VSCodeControlling) {
        self.apps = apps
        self.tabbit = tabbit
        self.vscode = vscode
    }

    public convenience init() {
        self.init(apps: WorkspaceRuntime(), tabbit: TabbitAppleScript(), vscode: VSCodeSocketBridge())
    }

    public func foreground() -> ForegroundSnapshot? { apps.foreground() }

    public func tabbitAutomationStatus() -> TabbitAutomationStatus {
        (tabbit as? TabbitAppleScript)?.permissionStatus() ?? .unavailable
    }

    public func requestTabbitAutomationPermission() async -> TabbitAutomationStatus {
        guard let integration = tabbit as? TabbitAppleScript else { return .unavailable }
        return await integration.requestPermission()
    }

    /// A visit never opens a native session URI or selects a Warp pane.
    public func activate(workEnd: WorkEnd, target: SessionTarget) async -> NavigationOutcome {
        let bundleID: String
        switch workEnd {
        case .codexDesktop: bundleID = Self.codexBundleID
        case .deepseekDesktop: bundleID = Self.deepseekBundleID
        case .kimiDesktop: bundleID = Self.kimiBundleID
        case .claudeCode, .codexCLI, .kimiCLI, .pi: bundleID = Self.warpBundleID
        }
        return await apps.activate(bundleID: bundleID, preferredProcessID: nil) ? .fallback : .unavailable
    }

    public func captureSource() -> ReturnAnchor? {
        guard let source = apps.foreground() else { return nil }
        let captured: Captured
        let accuracy: AnchorAccuracy
        switch source.bundleIdentifier {
        case Self.tabbitBundleID:
            guard apps.hasUniqueRunningInstance(bundleID: Self.tabbitBundleID) else { return nil }
            guard let tabID = tabbit.captureActiveTabID(), !tabID.isEmpty else { return nil }
            captured = .tabbit(processID: source.processID, tabID: tabID)
            accuracy = .exact
        case Self.vscodeBundleID:
            guard apps.hasUniqueRunningInstance(bundleID: Self.vscodeBundleID) else { return nil }
            guard let token = vscode.captureFocusedTab() else { return nil }
            captured = .vscode(processID: source.processID, token: token)
            accuracy = .exact
        case Self.wechatBundleID:
            captured = .wechat(processID: source.processID)
            accuracy = .application
        default:
            return nil
        }
        let id = UUID().uuidString
        anchors[id] = captured
        return ReturnAnchor(id: id, bundleIdentifier: source.bundleIdentifier, token: id, accuracy: accuracy)
    }

    /// false confirms invalidation; nil preserves an anchor through a temporary query failure.
    public func isAnchorValid(_ anchor: ReturnAnchor) -> Bool? {
        guard let captured = anchors[anchor.id], anchor.token == anchor.id else { return false }
        switch captured {
        case let .tabbit(pid, tabID):
            guard anchor.accuracy == .exact, anchor.bundleIdentifier == Self.tabbitBundleID,
                  apps.isRunning(bundleID: Self.tabbitBundleID, processID: pid) else { return false }
            return tabbit.contains(tabID: tabID)
        case let .vscode(pid, token):
            guard anchor.accuracy == .exact, anchor.bundleIdentifier == Self.vscodeBundleID,
                  apps.isRunning(bundleID: Self.vscodeBundleID, processID: pid) else { return false }
            return vscode.contains(token: token)
        case let .wechat(pid):
            return anchor.accuracy == .application && anchor.bundleIdentifier == Self.wechatBundleID &&
                apps.isRunning(bundleID: Self.wechatBundleID, processID: pid)
        }
    }

    public func focusContext(for anchor: ReturnAnchor?) -> FocusContext {
        let current = apps.foreground()
        let isAgent = current.map { [Self.warpBundleID, Self.codexBundleID, Self.deepseekBundleID, Self.kimiBundleID].contains($0.bundleIdentifier) } ?? false
        guard let anchor, let current, isAnchorValid(anchor) == true, let captured = anchors[anchor.id] else {
            return FocusContext(isAgent: isAgent)
        }
        let matched: Bool
        switch captured {
        case let .tabbit(pid, tabID):
            matched = current.processID == pid && tabbit.isActive(tabID: tabID)
        case let .vscode(pid, token):
            matched = current.processID == pid && vscode.isActive(token: token)
        case let .wechat(pid):
            matched = current.processID == pid
        }
        return FocusContext(isAgent: isAgent, sourceAnchorID: matched ? anchor.id : nil)
    }

    public func returnToSource(_ anchor: ReturnAnchor) async -> NavigationOutcome {
        guard isAnchorValid(anchor) == true, let captured = anchors[anchor.id] else { return .unavailable }
        switch captured {
        case let .tabbit(pid, tabID):
            guard await apps.activate(bundleID: Self.tabbitBundleID, preferredProcessID: pid) else { return .unavailable }
            return tabbit.focus(tabID: tabID) && tabbit.isActive(tabID: tabID) ? .exact : .fallback
        case let .vscode(pid, token):
            guard await apps.activate(bundleID: Self.vscodeBundleID, preferredProcessID: pid) else { return .unavailable }
            return vscode.focus(token: token) && vscode.isActive(token: token) ? .exact : .fallback
        case let .wechat(pid):
            return await apps.activate(bundleID: Self.wechatBundleID, preferredProcessID: pid) ? .fallback : .unavailable
        }
    }

    public func release(_ anchor: ReturnAnchor) { anchors.removeValue(forKey: anchor.id) }
}
