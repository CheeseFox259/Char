import Foundation
import CharCore

struct ObservationGenerationChecks {
    func run() throws {
        let now = Date()
        var current = ObservationGeneration(at: now)
        let suspendedBatch = current
        current.configure(enabled: current.enabled.subtracting([.pi]), at: now.addingTimeInterval(1))
        let disabled = current
        current.configure(enabled: current.enabled.union([.pi]), at: now.addingTimeInterval(2))
        try check(!current.accepts(.pi, from: suspendedBatch), "off/on must reject suspended old batch")
        try check(current.accepts(.claudeCode, from: suspendedBatch), "unchanged adapter batch must survive")
        try check(!current.accepts(.pi, from: disabled))
        try check(current.accepts(.pi, from: current), "fresh reloaded stream must be accepted")
        let router = AttentionRouter(startedAt: now, settings: CharSettings(filterSeconds: 0))
        let suspendedEvents = [WorkEnd.pi, .claudeCode].map { end in
            ObservationEvent(key: SessionKey(workEnd: end, nativeID: "suspended-batch"),
                             target: SessionTarget(bundleIdentifier: "fixture"), timestamp: now,
                             state: .stopped(.question))
        }
        router.ingest(suspendedEvents.filter { current.accepts($0.key.workEnd, from: suspendedBatch) })
        router.advance(to: now.addingTimeInterval(2))
        try checkEqual(router.snapshot.bubbles.map(\.workEnd), [.claudeCode])
        try check(!disabled.isNewer(than: current), "late configuration Task must not roll actor back")
        current.configure(enabled: current.enabled, at: now.addingTimeInterval(3))
        try checkEqual(current.activatedAt[.pi], now.addingTimeInterval(2))
        try checkEqual(current.changedAt, now.addingTimeInterval(3))
    }
}
