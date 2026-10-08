import Foundation

public struct AttentionItem: Equatable, Sendable {
    public var key: SessionKey
    public var target: SessionTarget
    public var reason: StopReason
    public var stoppedAt: Date
    public var firstNotifiedAt: Date?
    public var isPast: Bool
    public var navigationOutcome: NavigationOutcome?
    public init(key: SessionKey, target: SessionTarget, reason: StopReason, stoppedAt: Date,
                isPast: Bool = false, navigationOutcome: NavigationOutcome? = nil) {
        self.key = key; self.target = target; self.reason = reason; self.stoppedAt = stoppedAt
        self.isPast = isPast; self.navigationOutcome = navigationOutcome
    }
}

public struct AttentionBubble: Equatable, Sendable {
    public var workEnd: WorkEnd
    public var items: [AttentionItem]
    public var runningCount: Int
    /// Stops following observed running activity, still inside the notification filter.
    public var pendingCount: Int
    public var count: Int { items.count }
    public var head: AttentionItem? { items.first }
    public init(workEnd: WorkEnd, items: [AttentionItem], runningCount: Int, pendingCount: Int = 0) {
        self.workEnd = workEnd; self.items = items; self.runningCount = runningCount; self.pendingCount = pendingCount
    }
}

public struct HoldSnapshot: Equatable, Sendable {
    public var anchor: ReturnAnchor
    public var elapsedGraceSeconds: TimeInterval
    public init(anchor: ReturnAnchor, elapsedGraceSeconds: TimeInterval) {
        self.anchor = anchor; self.elapsedGraceSeconds = elapsedGraceSeconds
    }
}

public struct AttentionSnapshot: Equatable, Sendable {
    public var bubbles: [AttentionBubble]
    public var hold: HoldSnapshot?
    public var navigationFeedback: NavigationOutcome?
    public init(bubbles: [AttentionBubble], hold: HoldSnapshot?, navigationFeedback: NavigationOutcome?) {
        self.bubbles = bubbles; self.hold = hold; self.navigationFeedback = navigationFeedback
    }
}


/// Deterministic, local-only state. Callers ingest a complete observation batch before advancing time.
/// All calls belong on the same executor (the app's main thread); this type owns no timers or effects.
public final class AttentionRouter {
    private struct Session {
        var event: ObservationEvent
        var stoppedAt: Date?
        var acknowledged = false
        var hasObservedRunning = false
    }
    private let startedAt: Date
    private var now: Date
    private var settings: CharSettings
    private var sessions: [SessionKey: Session] = [:]
    private var items: [SessionKey: AttentionItem] = [:]
    private var focus = FocusContext()
    private var hold: HoldSnapshot?
    private var navigationFeedback: NavigationOutcome?
    private var feedback = AttentionFeedback()
    private var effects: [AttentionEffect] = []

    public init(startedAt: Date = Date(), settings: CharSettings = CharSettings()) {
        self.startedAt = startedAt; self.now = startedAt; self.settings = settings.normalized()
    }

    public var snapshot: AttentionSnapshot {
        let ends = Set(sessions.keys.map(\.workEnd)).union(items.keys.map(\.workEnd)).sorted()
        let bubbles = ends.compactMap { end -> AttentionBubble? in
            let queue = items.values.filter { $0.key.workEnd == end }.sorted(by: Self.precedes)
            let running = sessions.values.filter { $0.event.key.workEnd == end && $0.event.state == .running }.count
            let pending = sessions.values.filter {
                guard $0.event.key.workEnd == end, $0.hasObservedRunning, !$0.acknowledged,
                      items[$0.event.key] == nil, case .stopped = $0.event.state else { return false }
                return true
            }.count
            return queue.isEmpty && running == 0 && pending == 0 ? nil
                : AttentionBubble(workEnd: end, items: queue, runningCount: running, pendingCount: pending)
        }
        return AttentionSnapshot(bubbles: bubbles, hold: hold, navigationFeedback: navigationFeedback)
    }

    public func updateSettings(_ settings: CharSettings) {
        self.settings = settings.normalized()
        if settings.originPolicy == .disabled || (!settings.applicationOrigins && hold?.anchor.accuracy == .application) { endHold() }
        if !self.settings.soundEnabled {
            feedback.mutePending()
            effects = effects.map { effect in
                guard case let .notify(group, notices) = effect else { return effect }
                return .notify(group, notices.map { notice in var muted = notice; muted.audible = false; return muted })
            }
        }
        expireHoldIfNeeded()
    }

    /// Forget a removed adapter, including its pending notification batch.
    public func remove(workEnd: WorkEnd) {
        for key in Array(sessions.keys) where key.workEnd == workEnd {
            sessions.removeValue(forKey: key)
            removeItem(key)
        }
        effects = effects.compactMap { effect in
            let remaining = effect.notices.filter { $0.occurrence.key.workEnd != workEnd }
            guard case let .notify(group, _) = effect, !remaining.isEmpty else { return nil }
            return .notify(group, remaining)
        }
    }

    public func ingest(_ events: [ObservationEvent]) {
        // Stable order for identical timestamps; late duplicate records cannot undo newer state.
        let ordered = events.enumerated().sorted {
            $0.element.timestamp == $1.element.timestamp ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp
        }
        for (_, event) in ordered {
            guard !event.isChild, event.timestamp >= startedAt else { continue }
            let old = sessions[event.key]
            if let old, event.timestamp < old.event.timestamp || event == old.event { continue }
            if event.state == .closed {
                // Keep the closing timestamp so a late poll cannot resurrect an obsolete stop.
                sessions[event.key] = Session(event: event, stoppedAt: nil, acknowledged: true)
                if var item = items[event.key] {
                    item.isPast = true
                    items[event.key] = item
                }
                continue
            }
            var session = old ?? Session(event: event)
            switch event.state {
            case .running:
                session.stoppedAt = nil; session.acknowledged = false; session.hasObservedRunning = true
                if var item = items[event.key] {
                    item.isPast = true; item.target = event.target
                    items[event.key] = item
                }
            case let .stopped(reason):
                if session.stoppedAt == nil {
                    session.stoppedAt = event.timestamp
                    session.acknowledged = false
                }
                if var item = items[event.key] {
                    // An emitted item survives resume, but a fresh stop replaces its current reason and age.
                    if item.isPast {
                        // A new stop must pass the filter again; retain the previous record until then.
                    } else {
                        item.reason = reason; item.target = event.target
                        items[event.key] = item
                    }
                }
                if focus.exactSession == event.key {
                    session.acknowledged = true
                    removeItem(event.key)
                }
            case .closed: break
            }
            session.event = event
            sessions[event.key] = session
        }
    }

    public func advance(to date: Date) {
        guard date >= now else { return }
        if var hold, !focus.isAgent {
            hold.elapsedGraceSeconds += date.timeIntervalSince(now)
            self.hold = hold
        }
        now = date
        expireHoldIfNeeded()
        for key in sessions.keys {
            guard var session = sessions[key], case let .stopped(reason) = session.event.state,
                  !session.acknowledged, (items[key] == nil || items[key]?.isPast == true), let stoppedAt = session.stoppedAt,
                  stoppedAt <= now, now.timeIntervalSince(stoppedAt) >= settings.filterSeconds else { continue }
            if focus.exactSession == key {
                session.acknowledged = true; sessions[key] = session
                continue
            }
            items[key] = AttentionItem(key: key, target: session.event.target, reason: reason, stoppedAt: stoppedAt)
        }
        effects += feedback.advance(items: Array(items.values), at: now, soundEnabled: settings.soundEnabled)
        for key in Array(items.keys) {
            var item = items[key]!; item.firstNotifiedAt = feedback.firstNotifiedAt(for: item); items[key] = item
        }
    }

    public func updateFocus(_ context: FocusContext, at date: Date) {
        // Account for grace under the old app focus, but suppress alerts for the newly verified session.
        focus.exactSession = context.exactSession
        if let key = context.exactSession { removeItem(key) }
        advance(to: date)
        focus = context
        if let key = context.exactSession {
            if var session = sessions[key] { session.acknowledged = true; sessions[key] = session }
            removeItem(key)
        }
        if let hold, context.sourceAnchorID == hold.anchor.id { endHold() }
    }

    public func nextVisit(for workEnd: WorkEnd) -> AttentionItem? {
        snapshot.bubbles.first { $0.workEnd == workEnd }?.head
    }

    /// `sourceAnchor` is captured before activation; only a successful app switch starts Hold.
    /// Application anchors bind the captured foreground app to its still-live PID.
    public func completeVisit(key: SessionKey, outcome: NavigationOutcome, sourceAnchor: ReturnAnchor?, at date: Date) {
        advance(to: date)
        guard items[key] != nil else { return }
        navigationFeedback = outcome
        if outcome == .unavailable { return }
        if settings.originPolicy != .disabled, hold == nil || settings.originPolicy == .latest, let anchor = sourceAnchor,
           anchor.accuracy == .exact || (anchor.accuracy == .application && settings.applicationOrigins) {
            hold = HoldSnapshot(anchor: anchor, elapsedGraceSeconds: 0)
        }
        // The click acknowledges this attention record even when only the owning
        // application can be activated. Precision remains in navigationFeedback.
        if var session = sessions[key] { session.acknowledged = true; sessions[key] = session }
        removeItem(key)
        // The completed visit proves arrival at the owning Agent application, not an exact session.
        focus = FocusContext(exactSession: outcome == .exact ? key : nil, isAgent: true)
    }

    public func ignoreNext(for workEnd: WorkEnd) {
        guard let item = nextVisit(for: workEnd) else { return }
        if var session = sessions[item.key] { session.acknowledged = true; sessions[item.key] = session }
        removeItem(item.key)
    }

    public func completeReturn(outcome: NavigationOutcome) {
        guard let hold else { return }
        navigationFeedback = outcome
        // A still-live exact source remains retryable when activation or exact focus fails.
        if outcome == .exact || (outcome == .fallback &&
            (hold.anchor.accuracy == .application || hold.anchor.bundleIdentifier == "dev.warp.Warp-Stable")) {
            endHold()
        }
    }

    public func invalidateAnchor(id: String) {
        if hold?.anchor.id == id { endHold() }
    }

    public func endHold() { hold = nil }
    public func clearNavigationFeedback() { navigationFeedback = nil }
    public func drainEffects() -> [AttentionEffect] {
        defer { effects.removeAll() }
        return effects.compactMap { effect in
            let valid = effect.notices.filter { notice in
                guard let item = items[notice.occurrence.key] else { return false }
                return !item.isPast && item.occurrence == notice.occurrence && item.reason == notice.reason
            }
            guard case let .notify(group, _) = effect, !valid.isEmpty else { return nil }
            return .notify(group, valid)
        }
    }

    private func removeItem(_ key: SessionKey) {
        items.removeValue(forKey: key)
    }
    private func expireHoldIfNeeded() {
        if let hold, hold.elapsedGraceSeconds >= settings.graceSeconds, !focus.isAgent { endHold() }
    }
    private static func precedes(_ lhs: AttentionItem, _ rhs: AttentionItem) -> Bool {
        if lhs.isPast != rhs.isPast { return !lhs.isPast }
        let left = priority(lhs.reason), right = priority(rhs.reason)
        if left != right { return left < right }
        if lhs.stoppedAt != rhs.stoppedAt { return lhs.stoppedAt < rhs.stoppedAt }
        return lhs.key.nativeID < rhs.key.nativeID
    }
    private static func priority(_ reason: StopReason) -> Int {
        switch reason {
        case .question, .approval: return 0
        case .failure, .rateLimit, .contextExhausted: return 1
        case .unclassified: return 2
        case .turnEnded: return 3
        }
    }
}
