/// A Space arrival belongs to an observed hide/show cycle, not every workspace notification.
public struct CompanionSpaceLifecycle: Sendable {
    public enum State: Equatable, Sendable { case visible, prepared, arriving }
    public private(set) var state: State = .visible
    public init() {}
    @discardableResult public mutating func prepareHiddenAppearance() -> Bool {
        guard state == .visible else { return false }
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
