import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor public final class WorkspaceRuntime: ApplicationRuntime {
    public init() {}

    public func foregroundApplication() -> ForegroundSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        return ForegroundSnapshot(bundleIdentifier: bundleID, processID: app.processIdentifier)
    }

    public func foreground() -> ForegroundSnapshot? {
        guard let identity = foregroundApplication() else { return nil }
        let bundleID = identity.bundleIdentifier, pid = identity.processID
        // Read geometry and numeric IDs only. Window titles and contents are never requested.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let geometry = windows.compactMap { window -> WindowGeometry? in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let dictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return WindowGeometry(processID: pid, number: number, layer: layer, bounds: bounds)
        }
        guard let focusedBounds = DisplayFocusGeometry.windowBounds(axBounds: focusedWindowBounds(processID: pid), processID: pid, windows: geometry) else {
            return ForegroundSnapshot(bundleIdentifier: bundleID, processID: pid)
        }
        let matches = windows.filter { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            return abs(bounds.minX - focusedBounds.minX) < 3 &&
                abs(bounds.minY - focusedBounds.minY) < 3 &&
                abs(bounds.width - focusedBounds.width) < 3 &&
                abs(bounds.height - focusedBounds.height) < 3
        }
        let windowID = matches.count == 1 ? (matches[0][kCGWindowNumber as String] as? UInt32) : nil
        var displayID: UInt32?
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        if CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success {
            displayID = DisplayFocusGeometry.displayID(for: focusedBounds, displays: displays.prefix(Int(count)).map {
                DisplayGeometry(id: $0, bounds: CGDisplayBounds($0))
            })
        }
        return ForegroundSnapshot(bundleIdentifier: bundleID, processID: pid,
                                  windowNumber: windowID, displayID: displayID)
    }

    private func focusedWindowBounds(processID: Int32) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let window = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.1)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    public func isRunning(bundleID: String, processID: Int32) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier == processID && !$0.isTerminated }
    }

    public func hasUniqueRunningInstance(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }.count == 1
    }

    public func activate(bundleID: String, preferredProcessID: Int32?) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let preferredProcessID {
            guard let preferred = running.first(where: { $0.processIdentifier == preferredProcessID }) else { return false }
            return await activateAndVerify(preferred)
        }
        if let app = running.first(where: { !$0.isTerminated }) {
            return await activateAndVerify(app)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let launched: NSRunningApplication? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
                continuation.resume(returning: app)
            }
        }
        guard let launched else { return false }
        return await activateAndVerify(launched)
    }

    private func activateAndVerify(_ app: NSRunningApplication) async -> Bool {
        guard app.activate(options: [.activateIgnoringOtherApps]) else { return false }
        for _ in 0..<8 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
}
