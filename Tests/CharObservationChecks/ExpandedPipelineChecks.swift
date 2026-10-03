import Foundation
import CharCore
import CharObservations

func testExpandedSharedStreamPipeline() throws {
    try inTemporaryDirectory { root in
        let hooks = root.appendingPathComponent("hooks.jsonl")
        let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
            codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: hooks)
        let began = Date()
        func write(_ events: [ObservationEvent]) throws {
            for event in events {
                try append(String(decoding: JSONEncoder().encode(event), as: UTF8.self) + "\n", to: hooks)
            }
        }
        let stops = WorkEnd.allCases.map { end in
            ObservationEvent(key: SessionKey(workEnd: end, nativeID: "stream-\(end.rawValue)"),
                target: SessionTarget(bundleIdentifier: "fixture"), timestamp: began, state: .stopped(.question))
        }
        try write(stops)
        poller.start()
        try check(poller.poll().isEmpty, "expanded stream replayed historical waits")
        let router = AttentionRouter(startedAt: began, settings: CharSettings(filterSeconds: 0))
        let fresh = stops.map { original -> ObservationEvent in
            var event = original
            event.timestamp = began.addingTimeInterval(1)
            return event
        }
        try write(fresh)
        var piResume = fresh.first { $0.key.workEnd == .pi }!
        piResume.timestamp = began.addingTimeInterval(2)
        piResume.state = .running
        try write([piResume])
        router.ingest(poller.poll())
        router.advance(to: began.addingTimeInterval(3))
        let snapshot = router.snapshot
        try check(snapshot.bubbles.filter { $0.count == 1 }.count == WorkEnd.allCases.count - 1,
                  "expanded pipeline lost work-end attention or presented an already-resumed stop")
        let pi = snapshot.bubbles.first { $0.workEnd == .pi }
        try check(pi?.count == 0 && pi?.runningCount == 1, "whole wake batch did not apply Pi continuation before clock")
        try check(fresh.allSatisfy { $0.target.tmuxPaneID == nil }, "direct Warp pipeline requires tmux")
    }
}
