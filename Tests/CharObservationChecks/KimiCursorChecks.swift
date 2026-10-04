import Foundation
import CharCore
import CharObservations

func testKimiCursorPartialTruncationAndReplacement() throws {
    try inTemporaryDirectory { root in
        let hooks = root.appendingPathComponent("hooks.jsonl")
        let sessions = root.appendingPathComponent("sessions")
        let wire = sessions.appendingPathComponent("project/cursor/agents/main/wire.jsonl")
        try FileManager.default.createDirectory(at: wire.deletingLastPathComponent(), withIntermediateDirectories: true)
        let binding = NewAgentHooks.kimi(Data(#"{"session_id":"cursor","hook_event_name":"SessionStart","client_type":"kimi_code_cli"}"#.utf8),
                                        timestamp: Date(timeIntervalSince1970: 100))!
        try append(String(decoding: JSONEncoder().encode(binding), as: UTF8.self) + "\n", to: hooks)
        func line(_ type: String, at seconds: Double, padding: String = "") -> String {
            "{\"type\":\"\(type)\",\"agentId\":\"main\",\"time\":\(seconds * 1000),\"turnId\":1,\"reason\":\"completed\",\"padding\":\"\(padding)\"}"
        }
        try append(line("turn.ended", at: 100) + "\n", to: wire)
        let poller = KimiObservationPoller(kimiSessionsRoot: sessions, hookEventsFile: hooks)
        poller.start()
        try check(poller.poll().isEmpty, "Kimi cursor replayed baseline")
        try append(line("turn.prompt", at: 101), to: wire)
        try check(poller.poll().isEmpty, "Kimi partial line emitted before newline")
        try append("\n", to: wire)
        try check(poller.poll().map(\.state) == [.running], "Kimi partial completion lost")
        try check(poller.poll().isEmpty, "Kimi unchanged cursor replayed bytes")
        let handle = try FileHandle(forWritingTo: wire)
        try handle.truncate(atOffset: 0); try handle.close()
        try check(poller.poll().isEmpty, "Kimi empty truncation emitted event")
        try append(line("turn.ended", at: 102) + "\n", to: wire)
        try check(poller.poll().map(\.state) == [.stopped(.turnEnded)], "Kimi truncated cursor failed to resume at zero")
        let replacement = root.appendingPathComponent("replacement.jsonl")
        try append(line("turn.prompt", at: 103, padding: String(repeating: "x", count: 400)) + "\n", to: replacement)
        try FileManager.default.removeItem(at: wire)
        try FileManager.default.moveItem(at: replacement, to: wire)
        try check(poller.poll().map(\.state) == [.running], "Kimi larger replacement inode did not reset cursor")
        try check(poller.poll().isEmpty, "Kimi replacement replayed")
    }
}
