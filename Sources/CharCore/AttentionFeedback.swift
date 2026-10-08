import Foundation

/// A stop occurrence survives reason changes, but never a resume followed by a new stop.
public struct AttentionOccurrence: Hashable, Sendable {
    public let key: SessionKey
    public let stoppedAt: Date
    public var id: String { "\(key.workEnd.rawValue)/\(key.nativeID)/\(stoppedAt.timeIntervalSince1970)" }
}

public struct AttentionNotice: Equatable, Sendable {
    public enum Stage: String, Sendable { case initial, escalation }
    public let occurrence: AttentionOccurrence
    public let reason: StopReason
    public let stage: Stage
    public let issuedAt: Date
    public var audible: Bool = true
    public var group: AttentionPresentationGroup { .forReason(reason) }
}

public enum AttentionEffect: Equatable, Sendable {
    case notify(AttentionPresentationGroup, [AttentionNotice])
    public var notices: [AttentionNotice] { if case let .notify(_, notices) = self { return notices }; return [] }
}

/// Owns reminder age, reason-change deduplication and one escalation per waiting occurrence.
/// Time and attention records are inputs; consumers receive category batches, never a timer.
public struct AttentionFeedback: Sendable {
    private struct Record: Sendable {
        var reason: StopReason
        let firstNotifiedAt: Date
        var escalated = false
    }
    private var records: [AttentionOccurrence: Record] = [:]
    private var pending: [AttentionOccurrence: AttentionNotice] = [:]
    private var due: Date?
    public init() {}
    public mutating func mutePending() {
        pending = pending.mapValues { notice in var muted = notice; muted.audible = false; return muted }
    }
    public static let escalationSeconds: TimeInterval = 300
    public static func scale(age: TimeInterval) -> Double {
        let t = min(1, max(0, age / escalationSeconds))
        return 1 + 0.5 * (1 - pow(1 - t, 3))
    }
    public func firstNotifiedAt(for item: AttentionItem) -> Date? { records[item.occurrence]?.firstNotifiedAt }
    public mutating func advance(items: [AttentionItem], at now: Date, soundEnabled: Bool) -> [AttentionEffect] {
        let active = Dictionary(uniqueKeysWithValues: items.filter { !$0.isPast }.map { ($0.occurrence, $0) })
        records = records.filter { active[$0.key] != nil }
        pending = pending.filter { active[$0.key]?.reason == $0.value.reason }
        for item in active.values {
            let identity = item.occurrence
            if var record = records[identity] {
                if record.reason != item.reason {
                    record.reason = item.reason; records[identity] = record
                    pending[identity] = AttentionNotice(occurrence: identity, reason: item.reason, stage: .initial, issuedAt: now, audible: soundEnabled)
                }
            } else {
                // Presentation starts immediately, including while muted.
                records[identity] = Record(reason: item.reason, firstNotifiedAt: now)
                pending[identity] = AttentionNotice(occurrence: identity, reason: item.reason, stage: .initial, issuedAt: now, audible: soundEnabled)
            }
        }
        // Only the oldest waiting item drives each aggregate bubble's escalation.
        let ends = Set(active.keys.map { $0.key.workEnd })
        for end in ends {
            let oldest = active.values.filter { $0.key.workEnd == end }.min {
                let a = records[$0.occurrence]!.firstNotifiedAt, b = records[$1.occurrence]!.firstNotifiedAt
                return a == b ? $0.occurrence.id < $1.occurrence.id : a < b
            }
            if let item = oldest, var record = records[item.occurrence], !record.escalated,
               now.timeIntervalSince(record.firstNotifiedAt) >= Self.escalationSeconds {
                record.escalated = true; records[item.occurrence] = record
                pending[item.occurrence] = AttentionNotice(occurrence: item.occurrence, reason: item.reason, stage: .escalation, issuedAt: now, audible: soundEnabled)
            }
        }
        if !soundEnabled { mutePending() }
        if pending.isEmpty { due = nil; return [] }
        if due == nil { due = now.addingTimeInterval(0.25) }
        guard now >= due! else { return [] }
        let notices = pending.values.sorted { $0.occurrence.id < $1.occurrence.id }
        pending.removeAll(); due = nil
        return AttentionPresentationGroup.allCases.compactMap { group in
            let batch = notices.filter { $0.group == group }
            return batch.isEmpty ? nil : .notify(group, batch)
        }
    }
}

public extension AttentionItem {
    var occurrence: AttentionOccurrence { AttentionOccurrence(key: key, stoppedAt: stoppedAt) }
}
public extension AttentionBubble {
    var oldestWaiting: AttentionItem? {
        items.filter { !$0.isPast && $0.firstNotifiedAt != nil }.min {
            let a = $0.firstNotifiedAt!, b = $1.firstNotifiedAt!
            return a == b ? $0.occurrence.id < $1.occurrence.id : a < b
        }
    }
    func scale(at date: Date) -> Double {
        oldestWaiting?.firstNotifiedAt.map { AttentionFeedback.scale(age: date.timeIntervalSince($0)) } ?? 1
    }
}
