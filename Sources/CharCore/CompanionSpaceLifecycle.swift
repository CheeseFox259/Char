/// Visibility prepares a pose; only a confirmed workspace change starts motion.
public struct CompanionSpaceLifecycle: Sendable {
    public enum State: Equatable, Sendable { case visible, prepared, arriving }
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
    public mutating func finishArrival() { state = .visible }
}
