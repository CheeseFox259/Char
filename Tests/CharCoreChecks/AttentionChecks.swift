import Foundation
import CharCore

struct AttentionChecks {
    private let epoch = Date(timeIntervalSince1970: 1_000)
    private func time(_ seconds: Double) -> Date { epoch.addingTimeInterval(seconds) }
    private func key(_ id: String, _ end: WorkEnd = .claudeCode) -> SessionKey { SessionKey(workEnd: end, nativeID: id) }
    private func event(_ id: String, _ seconds: Double, _ state: SessionState,
                       end: WorkEnd = .claudeCode, child: Bool = false) -> ObservationEvent {
        ObservationEvent(key: key(id, end), target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable", tmuxPaneID: "%1"),
                         timestamp: time(seconds), state: state, isChild: child)
    }
    private func router(filter: Double = 10, grace: Double = 300, sound: Bool = true) -> AttentionRouter {
        AttentionRouter(startedAt: epoch, settings: CharSettings(filterSeconds: filter, graceSeconds: grace, soundEnabled: sound))
    }
    private func anchor(_ id: String = "tab-a", accuracy: AnchorAccuracy = .exact,
                        bundle: String = "com.tabbit.browser") -> ReturnAnchor {
        ReturnAnchor(id: id, bundleIdentifier: bundle, token: "live-object", accuracy: accuracy)
    }
    private func waiting(_ router: AttentionRouter) {
        router.ingest([event("a", 0, .stopped(.question)), event("b", 0, .stopped(.approval), end: .codexDesktop)])
        router.advance(to: time(10))
    }

    func testThresholdAndTransientWait() throws {
        let r = router()
        r.ingest([event("a", 0, .stopped(.question))])
        r.advance(to: time(9.99))
        try check(r.snapshot.bubbles.isEmpty)
        r.advance(to: time(10))
        try checkEqual(r.nextVisit(for: .claudeCode)?.reason, .question)
        let transient = router()
        transient.ingest([event("a", 0, .stopped(.question)), event("a", 9, .running)])
        transient.advance(to: time(30))
        try checkEqual(transient.snapshot.bubbles.first?.count, 0)
        try checkEqual(transient.snapshot.bubbles.first?.runningCount, 1)
        try check(transient.drainEffects().isEmpty)
    }

    func testExactFocusAndApplicationFocus() throws {
        let r = router()
        r.updateFocus(FocusContext(exactSession: key("a"), isAgent: true), at: time(0))
        r.ingest([event("a", 0, .stopped(.question)), event("other-pane", 0, .stopped(.question))])
        r.advance(to: time(10))
        try checkEqual(r.nextVisit(for: .claudeCode)?.key, key("other-pane"))
        r.updateFocus(FocusContext(isAgent: false), at: time(11))
        r.advance(to: time(20))
        try checkEqual(r.snapshot.bubbles.first?.count, 1)
        let appOnly = router()
        appOnly.updateFocus(FocusContext(isAgent: true), at: time(0))
        appOnly.ingest([event("a", 0, .stopped(.approval))])
        appOnly.advance(to: time(10))
        try checkEqual(appOnly.snapshot.bubbles.first?.count, 1)
        appOnly.updateFocus(FocusContext(exactSession: key("a"), isAgent: true), at: time(10))
        try check(appOnly.snapshot.bubbles.isEmpty)
    }

    func testStartupChildrenAndWorkEndIdentity() throws {
        let r = router()
        r.ingest([event("old", -1, .stopped(.question)), event("child", 0, .stopped(.question), child: true),
                  event("same", 0, .stopped(.question)), event("same", 0, .stopped(.approval), end: .codexCLI),
                  event("same", 0, .stopped(.failure), end: .codexDesktop)])
        r.advance(to: time(10))
        try checkEqual(r.snapshot.bubbles.count, 3)
        try check(r.snapshot.bubbles.allSatisfy { $0.count == 1 })
        r.ingest([event("old", 11, .stopped(.question))])
        r.advance(to: time(21))
        try checkEqual(r.snapshot.bubbles.first?.count, 2)
    }

    func testReasonReplacementAndPastResume() throws {
        let r = router()
        r.ingest([event("a", 0, .stopped(.unclassified)), event("a", 5, .stopped(.approval))])
        r.advance(to: time(10))
        try checkEqual(r.nextVisit(for: .claudeCode)?.reason, .approval)
        try checkEqual(r.nextVisit(for: .claudeCode)?.stoppedAt, time(0))
        r.ingest([event("a", 11, .running)])
        r.advance(to: time(11))
        try checkEqual(r.nextVisit(for: .claudeCode)?.isPast, true)
        try checkEqual(r.snapshot.bubbles.first?.runningCount, 1)
        r.ingest([event("a", 12, .stopped(.failure)), event("a", 12, .stopped(.failure))])
        r.advance(to: time(12))
        try checkEqual(r.snapshot.bubbles.first?.count, 1)
        try checkEqual(r.nextVisit(for: .claudeCode)?.reason, .failure)
        try checkEqual(r.nextVisit(for: .claudeCode)?.isPast, false)
        try checkEqual(r.nextVisit(for: .claudeCode)?.stoppedAt, time(12))
    }

    func testOrderingAndIgnoreOnlyHead() throws {
        let r = router()
        r.ingest([event("past", 0, .stopped(.question)), event("end", 0, .stopped(.turnEnded)),
                  event("unknown", 0, .stopped(.unclassified)), event("failure", 1, .stopped(.failure)),
                  event("approval", 2, .stopped(.approval)), event("question", 3, .stopped(.question))])
        r.advance(to: time(13))
        r.ingest([event("past", 14, .running)])
        let ids = r.snapshot.bubbles.first!.items.map { $0.key.nativeID }
        try checkEqual(ids, ["approval", "question", "failure", "unknown", "end", "past"])
        r.ignoreNext(for: .claudeCode)
        try checkEqual(r.nextVisit(for: .claudeCode)?.key.nativeID, "question")
        r.advance(to: time(30))
        try checkEqual(r.snapshot.bubbles.first?.count, 5)
        // Newer state wins over late records from another polling source.
        r.ingest([event("past", 1, .stopped(.failure))])
        try checkEqual(r.snapshot.bubbles.first?.items.last?.isPast, true)
    }

    func testSoundDebounceMuteAndRemovedItems() throws {
        let r = router()
        waiting(r)
        try check(r.drainEffects().isEmpty)
        r.advance(to: time(10.25))
        try checkEqual(r.drainEffects(), [.playSound])
        r.advance(to: time(20))
        try check(r.drainEffects().isEmpty)
        let muted = router(sound: false)
        waiting(muted)
        muted.advance(to: time(20))
        try check(muted.drainEffects().isEmpty)
        let removed = router()
        waiting(removed)
        removed.ignoreNext(for: .claudeCode); removed.ignoreNext(for: .codexDesktop)
        removed.advance(to: time(11))
        try check(removed.drainEffects().isEmpty)
        let focused = router()
        focused.ingest([event("a", 0, .stopped(.question))])
        focused.advance(to: time(10))
        focused.updateFocus(FocusContext(exactSession: key("a"), isAgent: true), at: time(11))
        try check(focused.drainEffects().isEmpty)
        let changed = router()
        waiting(changed)
        changed.updateSettings(CharSettings(soundEnabled: false))
        changed.advance(to: time(11))
        try check(changed.drainEffects().isEmpty)
    }

    func testSleepCompleteBatchUsesFinalState() throws {
        let r = router()
        r.ingest([event("resumed", 1, .stopped(.question)), event("resumed", 50, .running),
                  event("still", 2, .stopped(.approval))])
        r.advance(to: time(100))
        try checkEqual(r.nextVisit(for: .claudeCode)?.key, key("still"))
        try checkEqual(r.snapshot.bubbles.first?.count, 1)
        r.advance(to: time(100.25))
        try checkEqual(r.drainEffects(), [.playSound])
    }

    func testFallbackKeepsUnviewedAndFirstAnchor() throws {
        let r = router()
        waiting(r)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: anchor(), at: time(10))
        try checkEqual(r.nextVisit(for: .claudeCode)?.navigationOutcome, .fallback)
        try checkEqual(r.snapshot.hold?.anchor.id, "tab-a")
        r.completeVisit(key: key("b", .codexDesktop), outcome: .fallback, sourceAnchor: anchor("tab-b"), at: time(11))
        try checkEqual(r.snapshot.hold?.anchor.id, "tab-a")
        try checkEqual(r.snapshot.bubbles.reduce(0) { $0 + $1.count }, 2)
        r.completeReturn(outcome: .exact)
        try check(r.snapshot.hold == nil)
        try checkEqual(r.snapshot.navigationFeedback, .exact)
    }

    func testExactVisitAndUnavailableVisit() throws {
        let r = router()
        waiting(r)
        r.completeVisit(key: key("a"), outcome: .unavailable, sourceAnchor: anchor(), at: time(10))
        try check(r.snapshot.hold == nil)
        try checkEqual(r.nextVisit(for: .claudeCode)?.key, key("a"))
        r.completeVisit(key: key("a"), outcome: .exact, sourceAnchor: anchor(), at: time(10))
        try check(r.nextVisit(for: .claudeCode) == nil)
        try check(r.snapshot.hold != nil)
        r.advance(to: time(30))
        try check(r.nextVisit(for: .claudeCode) == nil)
    }

    func testUnsupportedApplicationSourcesAndNoSource() throws {
        for source in [nil, anchor(accuracy: .application, bundle: "dev.warp.Warp-Stable"),
                       anchor(accuracy: .application, bundle: "com.unknown.app")] {
            let r = router()
            waiting(r)
            r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: source, at: time(10))
            try check(r.snapshot.hold == nil)
            try check(r.nextVisit(for: .claudeCode) != nil)
        }
    }

    func testGraceAccumulatesPausesAndExpiresSilently() throws {
        let r = router(grace: 300)
        waiting(r)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: anchor(), at: time(10))
        r.advance(to: time(100))
        try checkEqual(r.snapshot.hold?.elapsedGraceSeconds, 0)
        r.updateFocus(FocusContext(), at: time(100))
        r.advance(to: time(220))
        try checkEqual(r.snapshot.hold?.elapsedGraceSeconds, 120)
        r.updateFocus(FocusContext(isAgent: true), at: time(220))
        r.advance(to: time(500))
        try checkEqual(r.snapshot.hold?.elapsedGraceSeconds, 120)
        r.updateFocus(FocusContext(), at: time(500))
        _ = r.drainEffects()
        r.advance(to: time(679))
        try check(r.snapshot.hold != nil)
        r.advance(to: time(680))
        try check(r.snapshot.hold == nil)
        try check(r.drainEffects().isEmpty)
    }

    func testManualReturnInvalidSourceEndAndRestart() throws {
        let r = router()
        waiting(r)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: anchor(), at: time(10))
        r.updateFocus(FocusContext(sourceAnchorID: "other-tab"), at: time(11))
        try check(r.snapshot.hold != nil)
        r.updateFocus(FocusContext(sourceAnchorID: "tab-a"), at: time(12))
        try check(r.snapshot.hold == nil)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: anchor(), at: time(13))
        r.invalidateAnchor(id: "other-tab")
        try check(r.snapshot.hold != nil)
        r.invalidateAnchor(id: "tab-a")
        try check(r.snapshot.hold == nil)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: anchor(), at: time(14))
        r.endHold()
        try check(r.snapshot.hold == nil)
        try check(router().snapshot.hold == nil)
    }

    func testDegradedWeChatHoldAndReturn() throws {
        let r = router()
        waiting(r)
        let source = anchor("wechat-instance", accuracy: .application, bundle: "com.tencent.xinWeChat")
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: source, at: time(10))
        try checkEqual(r.snapshot.hold?.anchor.accuracy, .application)
        r.completeReturn(outcome: .fallback)
        try check(r.snapshot.hold == nil)
        try checkEqual(r.snapshot.navigationFeedback, .fallback)
        r.completeVisit(key: key("a"), outcome: .fallback, sourceAnchor: source, at: time(11))
        r.updateFocus(FocusContext(sourceAnchorID: "wechat-instance"), at: time(12))
        try check(r.snapshot.hold == nil)
    }

    func testSettingsChangesAndClosedSession() throws {
        let r = router()
        r.ingest([event("a", 0, .stopped(.rateLimit))])
        r.advance(to: time(4))
        r.updateSettings(CharSettings(filterSeconds: 3))
        r.advance(to: time(4))
        try checkEqual(r.nextVisit(for: .claudeCode)?.reason, .rateLimit)
        r.ingest([event("a", 5, .closed)])
        r.advance(to: time(5))
        try check(r.snapshot.bubbles.isEmpty)
        try check(r.drainEffects().isEmpty)
        r.ingest([event("a", 4, .stopped(.rateLimit))])
        r.advance(to: time(20))
        try check(r.snapshot.bubbles.isEmpty)
    }
}
