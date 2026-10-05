/// Visibility prepares a pose; only a confirmed workspace change starts motion.
public struct CompanionSpaceLifecycle: Sendable {
    public enum State: Equatable, Sendable { case visible, prepared, departing, arriving }
    public private(set) var state: State = .visible
    public init() {}
    @discardableResult public mutating func prepareHiddenAppearance() -> Bool {
        guard state != .prepared else { return false }
        state = .prepared
        return true
    }
    @discardableResult public mutating func beginPreparedArrival() -> Bool {
        guard state == .prepared else { return false }
        state = .arriving
        return true
    }
    @discardableResult public mutating func beginVisibleDeparture() -> Bool {
        guard state == .visible else { return false }
        state = .departing
        return true
    }
    @discardableResult public mutating func beginArrivalAfterDeparture() -> Bool {
        guard state == .departing else { return false }
        state = .arriving
        return true
    }
    public mutating func finishArrival() { state = .visible }
}
