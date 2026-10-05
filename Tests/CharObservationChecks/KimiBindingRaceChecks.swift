import Foundation
import CharCore
import CharObservations

func testKimiWireWaitsForLateClientBinding() throws {
    for existingFile in [false, true] {
        try inTemporaryDirectory { root in
            let began = Date()
            let sessions = root.appendingPathComponent("sessions")
            let wire = sessions.appendingPathComponent("project/late-client/agents/main/wire.jsonl")
            let hooks = root.appendingPathComponent("hooks.jsonl")
            func wireLine(at date: Date, agent: String = "main") -> String {
                let payload: [String: Any] = ["type": "turn.ended", "agentId": agent,
                    "turnId": 1, "reason": "completed", "time": date.timeIntervalSince1970 * 1000]
                return String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self) + "\n"
            }
            if existingFile {
                try FileManager.default.createDirectory(at: wire.deletingLastPathComponent(), withIntermediateDirectories: true)
                try append(wireLine(at: began.addingTimeInterval(-3600)), to: wire)
            }
            let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
                codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: hooks, kimiSessionsRoot: sessions)
            poller.start()
            let router = AttentionRouter(startedAt: began, settings: CharSettings(filterSeconds: 0))
            try check(poller.poll().isEmpty, "startup baseline exposed an unbound old wait")
            try FileManager.default.createDirectory(at: wire.deletingLastPathComponent(), withIntermediateDirectories: true)
            let nativeTime = Date(timeIntervalSince1970: floor(began.timeIntervalSince1970) + 10)
            try append(wireLine(at: nativeTime), to: wire)
            // The hook read sees no binding while a new wire record is already discoverable.
            try check(poller.poll().isEmpty, "unbound client emitted a guessed work end")
            let binding = NewAgentHooks.kimi(Data(#"{"session_id":"late-client","hook_event_name":"SessionStart","client_type":"kimi_code_desktop"}"#.utf8),
                timestamp: nativeTime.addingTimeInterval(0.5))!
            try append(String(decoding: JSONEncoder().encode(binding), as: UTF8.self) + "\n", to: hooks)
            let events = poller.poll()
            try check(events.count == 1 && events.first?.timestamp == nativeTime,
                "fresh Kimi wire stop was lost before late binding (existing file: \(existingFile))")
            router.ingest(events)
            router.advance(to: nativeTime.addingTimeInterval(1))
            let bubble = router.snapshot.bubbles.first { $0.workEnd == .kimiDesktop }
            try check(bubble?.count == 1 && bubble?.head?.key.nativeID == "late-client",
                "late-bound fresh wire did not produce attention")
            let source = events.first?.target.sourcePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            try check(source == wire.resolvingSymlinksInPath(), "late binding lost native source location")
            // Old timestamps appended later and child-agent records must not replace the root stop.
            try append(wireLine(at: began.addingTimeInterval(-30)), to: wire)
            try append(wireLine(at: nativeTime.addingTimeInterval(2), agent: "child"), to: wire)
            try check(poller.poll().isEmpty, "stale or child wire record admitted after binding")
            try check(poller.poll().isEmpty, "late binding replayed fresh event twice")
            let end = NewAgentHooks.kimi(Data(#"{"session_id":"late-client","hook_event_name":"SessionEnd","client_type":"kimi_code_desktop"}"#.utf8),
                timestamp: nativeTime.addingTimeInterval(3))!
            try append(String(decoding: JSONEncoder().encode(end), as: UTF8.self) + "\n", to: hooks)
            router.ingest(poller.poll())
            router.ignoreNext(for: .kimiDesktop)
            // A stale old-client wait must not return when the same session is attached again.
            try append(wireLine(at: nativeTime.addingTimeInterval(2)), to: wire)
            let restarted = NewAgentHooks.kimi(Data(#"{"session_id":"late-client","hook_event_name":"SessionStart","client_type":"kimi_code_cli"}"#.utf8),
                timestamp: nativeTime.addingTimeInterval(5))!
            try append(String(decoding: JSONEncoder().encode(restarted), as: UTF8.self) + "\n", to: hooks)
            try append(wireLine(at: nativeTime.addingTimeInterval(4)), to: wire)
            let restartedEvents = poller.poll()
            try check(restartedEvents.count == 1 && restartedEvents.first?.timestamp == nativeTime.addingTimeInterval(4),
                "rebound session replayed closed-client history or lost fresh pre-receipt stop")
            router.ingest(restartedEvents)
            router.advance(to: nativeTime.addingTimeInterval(6))
            try check(router.snapshot.bubbles.first(where: { $0.workEnd == .kimiCLI })?.count == 1,
                "rebound session lost fresh attention")
        }
    }
    try inTemporaryDirectory { root in
        let began = Date()
        let sessions = root.appendingPathComponent("sessions")
        let wire = sessions.appendingPathComponent("project/copied/agents/main/wire.jsonl")
        let hooks = root.appendingPathComponent("hooks.jsonl")
        let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
            codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: hooks, kimiSessionsRoot: sessions)
        poller.start()
        try FileManager.default.createDirectory(at: wire.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oldRecord: [String: Any] = ["type": "turn.ended", "agentId": "main", "turnId": 1,
            "reason": "completed", "time": began.addingTimeInterval(-3600).timeIntervalSince1970 * 1000]
        try append(String(decoding: JSONSerialization.data(withJSONObject: oldRecord), as: UTF8.self) + "\n", to: wire)
        let binding = NewAgentHooks.kimi(Data(#"{"session_id":"copied","hook_event_name":"SessionStart","client_type":"kimi_code_cli"}"#.utf8),
            timestamp: began.addingTimeInterval(1))!
        try append(String(decoding: JSONEncoder().encode(binding), as: UTF8.self) + "\n", to: hooks)
        let router = AttentionRouter(startedAt: began, settings: CharSettings(filterSeconds: 0))
        router.ingest(poller.poll())
        router.advance(to: began.addingTimeInterval(2))
        try check(router.snapshot.bubbles.isEmpty, "historical file copied after startup created attention")
    }

}
