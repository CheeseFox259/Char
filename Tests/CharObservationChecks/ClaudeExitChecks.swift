import Foundation
import CharCore
import CharObservations

/// Redacted native local-command envelope, through the production poller and router.
func testClaudeExitCannotLeaveRunningBubble() throws {
    let quit = #"{"type":"user","sessionId":"quit","timestamp":"2026-10-08T06:00:01Z","message":{"content":"<command-name>/quit</command-name><command-message>quit</command-message>"}}"#
    try check(ObservationClassifier.claude(Data(quit.utf8),sourcePath:"/fixture.jsonl")?.state == .closed,"quit alias did not close")
    let skill = quit.replacingOccurrences(of:"/quit",with:"/my-skill")
    try check(ObservationClassifier.claude(Data(skill.utf8),sourcePath:"/fixture.jsonl")?.state == .running,"custom slash prompt was suppressed")
    try inTemporaryDirectory { root in
        let projects = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at:projects,withIntermediateDirectories:true)
        let file = projects.appendingPathComponent("session.jsonl")
        let poller = LocalObservationPoller(claudeProjectsRoot:projects,codexSessionsRoot:root.appendingPathComponent("missing"))
        let router = AttentionRouter(startedAt:Date(timeIntervalSince1970:0),settings:CharSettings(filterSeconds:0))
        poller.start()
        try append(#"{"type":"assistant","sessionId":"fixture-exit","timestamp":"2026-10-08T06:00:00Z","message":{"stop_reason":"end_turn"}}"# + "\n",to:file)
        router.ingest(poller.poll()); router.advance(to:Date(timeIntervalSince1970:2_000_000_000))
        try check(router.nextVisit(for:.claudeCode)?.reason == .turnEnded,"fixture must first complete a turn")
        try append(#"{"type":"user","sessionId":"fixture-exit","timestamp":"2026-10-08T06:00:01Z","message":{"role":"user","content":"<command-name>/exit</command-name>\n<command-message>exit</command-message>\n<command-args></command-args>"}}"# + "\n",to:file)
        try append(#"{"type":"user","sessionId":"fixture-exit","timestamp":"2026-10-08T06:00:01Z","message":{"role":"user","content":"<local-command-stdout>Goodbye!</local-command-stdout>"}}"# + "\n",to:file)
        router.ingest(poller.poll())
        try check(router.snapshot.bubbles.first?.runningCount == 0,"Claude /exit and its stdout left a stale running bubble")
        router.ignoreNext(for:.claudeCode)
        try check(router.snapshot.bubbles.isEmpty,"acknowledged closed Claude bubble could not disappear")
    }
}
