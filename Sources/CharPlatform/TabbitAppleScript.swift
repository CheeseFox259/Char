import AppKit
import CoreServices
import Foundation

public enum TabbitAutomationStatus: Equatable, Sendable {
    case authorized, needsConsent, denied, unavailable
}

private func tabbitAutomationStatus(askUser: Bool) -> TabbitAutomationStatus {
    let bytes = Array("com.tabbit-ai.Tabbit".utf8)
    var target = AEAddressDesc()
    let created = bytes.withUnsafeBytes {
        AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, bytes.count, &target)
    }
    guard created == noErr else { return .unavailable }
    defer { AEDisposeDesc(&target) }
    let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), askUser)
    switch status {
    case noErr: return .authorized
    case OSStatus(errAEEventWouldRequireUserConsent): return .needsConsent
    case OSStatus(errAEEventNotPermitted): return .denied
    default: return .unavailable
    }
}

/// Uses only tab IDs from Tabbit's bundled scripting dictionary. The app asks for Automation consent.
@MainActor public final class TabbitAppleScript: TabbitControlling {
    public init() {}

    /// Passive status checks never display an Automation prompt.
    public func permissionStatus() -> TabbitAutomationStatus { tabbitAutomationStatus(askUser: false) }

    /// Invoke only from an explicit settings action; the prompt-capable API runs off the UI thread.
    public func requestPermission() async -> TabbitAutomationStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: tabbitAutomationStatus(askUser: true))
            }
        }
    }

    private func evaluate(_ body: String) -> String? {
        guard permissionStatus() == .authorized else { return nil }
        let source = "tell application id \"\(MacOSPlatform.tabbitBundleID)\"\n\(body)\nend tell"
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let value = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return value.stringValue
    }

    private func literal(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public func captureActiveTabID() -> String? {
        evaluate("return id of active tab of front window as text")
    }

    public func contains(tabID: String) -> Bool? {
        guard let result = evaluate("""
        repeat with w in windows
            set tabIDs to get id of tabs of w
            repeat with tabIDValue in tabIDs
                if (tabIDValue as text) is \(literal(tabID)) then return "yes"
            end repeat
        end repeat
        return "no"
        """), ["yes", "no"].contains(result) else { return nil }
        return result == "yes"
    }

    public func focus(tabID: String) -> Bool {
        evaluate("""
        repeat with w in windows
            set tabIDs to get id of tabs of w
            repeat with i from 1 to count of tabIDs
                if (item i of tabIDs as text) is \(literal(tabID)) then
                    set active tab index of w to i
                    set index of w to 1
                    return "yes"
                end if
            end repeat
        end repeat
        return "no"
        """) == "yes"
    }

    public func isActive(tabID: String) -> Bool {
        captureActiveTabID() == tabID
    }
}
