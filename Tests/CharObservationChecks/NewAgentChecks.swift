import Foundation
import CharCore
import CharObservations

func testNewAgentHooksAndKimiWire() throws {
    try inTemporaryDirectory { root in
        let hooks = root.appendingPathComponent("hooks.jsonl")
        let sessions = root.appendingPathComponent("sessions")
        let wire = sessions.appendingPathComponent("work/session-a/agents/main/wire.jsonl")
        try FileManager.default.createDirectory(at: wire.deletingLastPathComponent(), withIntermediateDirectories: true)
        let epoch: Double = 1_800_000_000_000
        func line(_ type: String, _ extra: String = "", agent: String = "main", time: Double = epoch) -> String {
            "{\"type\":\"\(type)\",\"agentId\":\"\(agent)\",\"time\":\(time),\"turnId\":1\(extra)}\n"
        }
        let binding = NewAgentHooks.kimi(Data(#"{"session_id":"session-a","hook_event_name":"SessionStart","client_type":"kimi_code_desktop"}"#.utf8), timestamp: Date(timeIntervalSince1970: epoch / 1000))!
        try append(String(data: try JSONEncoder().encode(binding), encoding: .utf8)! + "\n", to: hooks)
        try append(line("turn.ended", #", "reason":"completed""#), to: wire)
        let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
                                           codexSessionsRoot: root.appendingPathComponent("codex"),
                                           hookEventsFile: hooks, kimiSessionsRoot: sessions)
        poller.start()
        try check(poller.poll().isEmpty, "Kimi startup replayed old waiting events")
        try append(line("turn.prompt", time: epoch + 100), to: wire)
        try append(line("context.append_loop_event", #", "event":{"type":"tool.call","toolCallId":"q","name":"AskUserQuestion","args":{}}"#, time: epoch + 200), to: wire)
        try append(line("turn.ended", #", "reason":"completed""#, agent: "agent-0", time: epoch + 300), to: wire)
        let events = poller.poll()
        try check(events.map(\.state) == [.running, .stopped(.question)], "Kimi root question or child suppression failed")
        try check(events.allSatisfy { $0.key.workEnd == .kimiDesktop && $0.target.bundleIdentifier == "com.kimi.code.desktop" }, "Kimi Desktop ownership lost")
        try append(line("context.append_loop_event", #", "event":{"type":"tool.result","toolCallId":"wrong"}"#, time: epoch + 400), to: wire)
        try check(poller.poll().isEmpty, "Kimi mismatched result resumed pending question")
        try append(line("context.append_loop_event", #", "event":{"type":"tool.result","toolCallId":"q"}"#, time: epoch + 500), to: wire)
        try append(line("turn.ended", #", "reason":"failed", "error":{"code":"provider.rate_limit","message":"private"}"#, time: epoch + 600), to: wire)
        try check(poller.poll().map(\.state) == [.running, .stopped(.rateLimit)], "Kimi structured rate limit failed")
        try append(line("turn.ended", #", "reason":"failed", "error":{"code":"context.overflow"}"#, time: epoch + 700), to: wire)
        try check(poller.poll().first?.state == .stopped(.contextExhausted), "Kimi structured context overflow failed")
        func writeHook(_ kind: String, turn: Int, approvalID: String, time: Double) throws {
            let payload: [String: Any] = ["session_id": "session-a", "hook_event_name": kind,
                "client_type": "kimi_code_desktop", "agent_id": "main", "turn_id": turn, "id": approvalID]
            let record = NewAgentHooks.kimi(try JSONSerialization.data(withJSONObject: payload),
                                           timestamp: Date(timeIntervalSince1970: time / 1000))!
            try append(String(data: try JSONEncoder().encode(record), encoding: .utf8)! + "\n", to: hooks)
        }
        try writeHook("PermissionRequest", turn: 1, approvalID: "completed", time: epoch + 800)
        try check(poller.poll().isEmpty, "late Kimi approval replaced a completed turn")
        try writeHook("PermissionResult", turn: 2, approvalID: "resolved", time: epoch + 900)
        try check(poller.poll().first?.state == .running, "Kimi root approval result did not resume")
        try writeHook("PermissionRequest", turn: 2, approvalID: "resolved", time: epoch + 1000)
        try check(poller.poll().isEmpty, "late Kimi approval request after result created a stop")
        try writeHook("PermissionRequest", turn: 3, approvalID: "current", time: epoch + 1100)
        try check(poller.poll().first?.state == .stopped(.approval), "Kimi active root approval missing")
        let cli = NewAgentHooks.kimi(Data(#"{"session_id":"cli","hook_event_name":"SessionStart","client_type":"kimi_code_cli"}"#.utf8))
        try check(cli?.workEnd == .kimiCLI, "Kimi direct Warp requires tmux or wrong work end")
        for record in [#"{"session_id":"x","hook_event_name":"Stop","client_type":"kimi_code_cli"}"#,
                       #"{"session_id":"x","hook_event_name":"PermissionRequest","client_type":"kimi_code_cli","agent_id":"child"}"#,
                       #"{"session_id":"x","hook_event_name":"SessionStart","client_type":"remote"}"#] {
            try check(NewAgentHooks.kimi(Data(record.utf8)) == nil, "Kimi unknown client or rootless child hook admitted")
        }
        let approval = NewAgentHooks.kimi(Data(#"{"session_id":"x","hook_event_name":"PermissionRequest","client_type":"kimi_code_cli","agent_id":"main","turn_id":2,"id":"approve-a"}"#.utf8))
        try check(approval?.phase == "PermissionRequest", "Kimi native root approval missing")
        let deepseek = NewAgentHooks.deepseek(Data(#"{"session_id":"root","client_type":"deepseek_desktop","root_session":true,"time":1800000000000,"kind":"rateLimit"}"#.utf8))
        try check(deepseek?.state == .stopped(.rateLimit) && deepseek?.timestamp.timeIntervalSince1970 == epoch / 1000, "DeepSeek structured bridge/date conversion failed")
    }
}
