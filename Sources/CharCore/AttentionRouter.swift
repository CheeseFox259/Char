import Foundation

public struct AttentionItem: Equatable, Sendable {
    public var key: SessionKey
    public var target: SessionTarget
    public var reason: StopReason
    public var stoppedAt: Date
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
    public var count: Int { items.count }
    public var head: AttentionItem? { items.first }
    public init(workEnd: WorkEnd, items: [AttentionItem], runningCount: Int) {
        self.workEnd = workEnd; self.items = items; self.runningCount = runningCount
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

public enum AttentionEffect: Equatable, Sendable { case playSound }

/// Deterministic, local-only state. Callers ingest a complete observation batch before advancing time.
/// All calls belong on the same executor (the app's main thread); this type owns no timers or effects.
public final class AttentionRouter {
    private struct Session {
        var event: ObservationEvent
        var stoppedAt: Date?
        var acknowledged = false
    }
    private let startedAt: Date
    private var now: Date
    private var settings: CharSettings
    private var sessions: [SessionKey: Session] = [:]
    private var items: [SessionKey: AttentionItem] = [:]
    private var focus = FocusContext()
    private var hold: HoldSnapshot?
    private var navigationFeedback: NavigationOutcome?
    private var pendingSound: Set<SessionKey> = []
    private var soundDue: Date?
    private var effects: [AttentionEffect] = []
    private let soundDebounce: TimeInterval = 0.25

    public init(startedAt: Date = Date(), settings: CharSettings = CharSettings()) {
        self.startedAt = startedAt; self.now = startedAt; self.settings = settings.normalized()
    }

    public var snapshot: AttentionSnapshot {
        let bubbles = WorkEnd.allCases.compactMap { end -> AttentionBubble? in
            let queue = items.values.filter { $0.key.workEnd == end }.sorted(by: Self.precedes)
            let running = sessions.values.filter { $0.event.key.workEnd == end && $0.event.state == .running }.count
            return queue.isEmpty && running == 0 ? nil : AttentionBubble(workEnd: end, items: queue, runningCount: running)
        }
        return AttentionSnapshot(bubbles: bubbles, hold: hold, navigationFeedback: navigationFeedback)
    }

    public func updateSettings(_ settings: CharSettings) {
        self.settings = settings.normalized()
        if !self.settings.soundEnabled { pendingSound.removeAll(); soundDue = nil }
        expireHoldIfNeeded()
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
                session.stoppedAt = nil; session.acknowledged = false
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
                    item.reason = reason; item.target = event.target; item.isPast = false
                    item.stoppedAt = session.stoppedAt ?? event.timestamp
                    items[event.key] = item
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
                  !session.acknowledged, items[key] == nil, let stoppedAt = session.stoppedAt,
                  stoppedAt <= now, now.timeIntervalSince(stoppedAt) >= settings.filterSeconds else { continue }
            if focus.exactSession == key {
                session.acknowledged = true; sessions[key] = session
                continue
            }
            items[key] = AttentionItem(key: key, target: session.event.target, reason: reason, stoppedAt: stoppedAt)
            if settings.soundEnabled {
                pendingSound.insert(key)
                if soundDue == nil { soundDue = now.addingTimeInterval(soundDebounce) }
            }
        }
        if let due = soundDue, now >= due {
            if settings.soundEnabled && pendingSound.contains(where: { items[$0] != nil }) { effects.append(.playSound) }
            pendingSound.removeAll(); soundDue = nil
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
    /// Application accuracy is supported for a verified live WeChat instance only.
    public func completeVisit(key: SessionKey, outcome: NavigationOutcome, sourceAnchor: ReturnAnchor?, at date: Date) {
        advance(to: date)
        guard items[key] != nil else { return }
        navigationFeedback = outcome
        if outcome == .unavailable { return }
        if hold == nil, let anchor = sourceAnchor,
           anchor.accuracy == .exact || (anchor.accuracy == .application && anchor.bundleIdentifier == "com.tencent.xinWeChat") {
            hold = HoldSnapshot(anchor: anchor, elapsedGraceSeconds: 0)
        }
        if outcome == .exact {
            if var session = sessions[key] { session.acknowledged = true; sessions[key] = session }
            removeItem(key)
        } else {
            items[key]?.navigationOutcome = .fallback
        }
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
        return effects
    }

    private func removeItem(_ key: SessionKey) {
        items.removeValue(forKey: key); pendingSound.remove(key)
        if pendingSound.isEmpty { soundDue = nil }
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
