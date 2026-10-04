import Foundation

/// Configuration identity follows each work end across unloading and reloading.
/// A returned batch retains the identity under which its bytes were read.
public struct ObservationGeneration: Sendable {
    public private(set) var revision: UInt64 = 0
    public private(set) var enabled: Set<WorkEnd>
    public private(set) var generations: [WorkEnd: UInt64] = [:]
    public private(set) var activatedAt: [WorkEnd: Date] = [:]
    public private(set) var changedAt: Date
    public init(enabled: Set<WorkEnd> = Set(WorkEnd.allCases), at date: Date = Date()) {
        self.enabled = enabled; changedAt = date
    }
    public mutating func configure(enabled next: Set<WorkEnd>, at date: Date) {
        revision += 1
        for end in enabled.symmetricDifference(next) {
            generations[end] = revision
            if next.contains(end) { activatedAt[end] = date }
        }
        enabled = next; changedAt = date
    }
    public func accepts(_ end: WorkEnd, from batch: ObservationGeneration) -> Bool {
        enabled.contains(end) && batch.enabled.contains(end) && generations[end, default: 0] == batch.generations[end, default: 0]
    }
    public func isNewer(than configuration: ObservationGeneration) -> Bool { revision > configuration.revision }
}
