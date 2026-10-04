import Foundation
import CharCore
import CharObservations

func pluginObservationChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Char-hotplug-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let hooks = root.appendingPathComponent("hooks.jsonl")
    try Data().write(to: hooks)
    let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
        codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: hooks)
    poller.start()
    let now = Date()
    func append(_ end: WorkEnd, _ id: String, _ timestamp: Date) throws {
        let event = ObservationEvent(key: SessionKey(workEnd: end, nativeID: id), target: SessionTarget(bundleIdentifier: "com.test.app"), timestamp: timestamp, state: .stopped(.turnEnded))
        var data = try JSONEncoder().encode(event); data.append(10)
        let handle = try FileHandle(forWritingTo: hooks); try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close()
    }
    try append(.pi, "before", now)
    assert(poller.poll().count == 1)
    poller.setEnabledWorkEnds([.deepseekDesktop], at: now.addingTimeInterval(1))
    try append(.pi, "disabled", now.addingTimeInterval(2))
    try append(.deepseekDesktop, "retained", now.addingTimeInterval(2))
    assert(poller.poll().map(\.key.nativeID) == ["retained"])
    // Unread disabled history must also be excluded on re-enable.
    try append(.pi, "late-disabled", now.addingTimeInterval(3))
    poller.setEnabledWorkEnds([.pi, .deepseekDesktop], at: now.addingTimeInterval(4))
    try append(.pi, "new", now.addingTimeInterval(5))
    assert(poller.poll().map(\.key.nativeID) == ["new"])
    let router = AttentionRouter(startedAt: now.addingTimeInterval(-1), settings: CharSettings(filterSeconds: 0))
    router.ingest([ObservationEvent(key: SessionKey(workEnd: .pi, nativeID: "shown"), target: SessionTarget(bundleIdentifier: "com.test.app"), timestamp: now, state: .stopped(.turnEnded))])
    router.advance(to: now)
    assert(router.snapshot.bubbles.count == 1)
    router.remove(workEnd: .pi)
    router.advance(to: now.addingTimeInterval(10))
    assert(router.snapshot.bubbles.isEmpty && router.drainEffects().isEmpty)
    print("CharObservations: hot unplug, retained adapters and re-enable baselines passed")
}
