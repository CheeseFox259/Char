import CoreGraphics

/// Only numeric window geometry. No titles, contents or screen images.
public struct WindowGeometry: Sendable {
    public let processID: Int32
    public let number: UInt32
    public let layer: Int
    public let bounds: CGRect
    public init(processID: Int32, number: UInt32, layer: Int, bounds: CGRect) {
        self.processID = processID; self.number = number; self.layer = layer; self.bounds = bounds
    }
}
public struct DisplayGeometry: Sendable {
    public let id: UInt32
    public let bounds: CGRect
    public init(id: UInt32, bounds: CGRect) { self.id = id; self.bounds = bounds }
}
public enum DisplayFocusGeometry {
    public static func windowBounds(axBounds: CGRect?, processID: Int32, windows: [WindowGeometry]) -> CGRect? {
        if let axBounds, valid(axBounds) { return axBounds }
        // CGWindowList supplies front-to-back order; keep that order within the foreground app.
        return windows.first { $0.processID == processID && $0.layer == 0 && valid($0.bounds) }?.bounds
    }
    public static func displayID(for bounds: CGRect, displays: [DisplayGeometry]) -> UInt32? {
        guard valid(bounds) else { return nil }
        var bestID: UInt32?, bestArea: CGFloat = 0
        for display in displays where valid(display.bounds) {
            let overlap = bounds.intersection(display.bounds)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea { bestArea = area; bestID = display.id }
        }
        return bestID
    }
    private static func valid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite && bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
    }
}
