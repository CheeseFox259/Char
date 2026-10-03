import Foundation
import CharCore
import CharObservations

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case let .failed(value) = self { return value }; return "check failed" }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

func append(_ text: String, to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

func inTemporaryDirectory(_ action: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try action(root)
}

func testStartupAndAppends() throws {
    try inTemporaryDirectory { root in
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let existing = claude.appendingPathComponent("existing.jsonl")
        try append(#"{"type":"assistant","sessionId":"c1","timestamp":"2026-10-03T12:00:00.000Z","message":{"stop_reason":"end_turn"}}"# + "\n", to: existing)
        let poller = LocalObservationPoller(claudeProjectsRoot: claude, codexSessionsRoot: codex)
        poller.start()
        try check(poller.poll().isEmpty, "startup replayed an old stop")
        try append(#"{"type":"user","sessionId":"c1","timestamp":"2026-10-03T12:00:01.000Z"}"# + "\n", to: existing)
        let resumed = poller.poll()
        try check(resumed.count == 1 && resumed[0].state == .running, "existing session append was missed")
        let fresh = claude.appendingPathComponent("new.jsonl")
        try append(#"{"type":"assistant","sessionId":"c2","timestamp":"2026-10-03T12:00:02.000Z","message":{"stop_reason":"end_turn"}}"#, to: fresh)
        try check(poller.poll().isEmpty, "incomplete line was emitted")
        try append("\n", to: fresh)
        let completed = poller.poll()
        try check(completed.count == 1 && completed[0].key.nativeID == "c2", "new complete line was lost")
        try check(poller.poll().isEmpty, "already-read line replayed")
    }
}

func testCodexIdentityAndBatch() throws {
    try inTemporaryDirectory { root in
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let journal = codex.appendingPathComponent("rollout.jsonl")
        try append(#"{"type":"session_meta","payload":{"id":"desktop-1","originator":"Codex Desktop","source":"vscode","thread_source":"user"}}"# + "\n", to: journal)
        let poller = LocalObservationPoller(claudeProjectsRoot: claude, codexSessionsRoot: codex)
        poller.start()
        try append(#"{"type":"event_msg","timestamp":"2026-10-03T12:00:02.000Z","payload":{"type":"task_complete"}}"# + "\n", to: journal)
        try append(#"{"type":"event_msg","timestamp":"2026-10-03T12:00:03.000Z","payload":{"type":"task_started"}}"# + "\n", to: journal)
        let batch = poller.poll()
        try check(batch.count == 2, "sleep batch lost events")
        try check(batch[0].state == .stopped(.turnEnded) && batch[1].state == .running, "batch order/final state incorrect")
        try check(batch.allSatisfy { $0.key.workEnd == .codexDesktop && $0.key.nativeID == "desktop-1" }, "work-end identity incorrect")
        let newJournal = codex.appendingPathComponent("new-rollout.jsonl")
        try append(#"{"type":"session_meta","payload":{"id":"cli-2","originator":"codex_cli","source":"cli","thread_source":"user"}}"# + "\n", to: newJournal)
        try append(#"{"type":"event_msg","timestamp":"2026-10-03T12:00:04.000Z","payload":{"type":"turn_complete"}}"# + "\n", to: newJournal)
        let newBatch = poller.poll()
        try check(newBatch.count == 1 && newBatch[0].key.workEnd == .codexCLI && newBatch[0].key.nativeID == "cli-2", "new Codex journal not classified")
    }
}

func testCodexQuestionResumesOnMatchingOutput() throws {
    let session = CodexSession(id: "desktop-q", workEnd: .codexDesktop, isLocalRoot: true)
    let question = ObservationClassifier.codex(Data(#"{"type":"response_item","timestamp":"2026-10-03T12:00:00Z","payload":{"type":"function_call","name":"request_user_input_async","call_id":"call-1","arguments":"{}"}}"#.utf8), sourcePath: "/tmp/q.jsonl", session: session)
    try check(question.event?.state == .stopped(.question), "Codex question call not mapped")
    let unrelated = ObservationClassifier.codex(Data(#"{"type":"response_item","timestamp":"2026-10-03T12:00:01Z","payload":{"type":"function_call_output","call_id":"other","output":"{}"}}"#.utf8), sourcePath: "/tmp/q.jsonl", session: session, pendingQuestionCallIDs: question.pendingQuestionCallIDs)
    try check(unrelated.event == nil, "unrelated tool output resumed question")
    let answer = ObservationClassifier.codex(Data(#"{"type":"response_item","timestamp":"2026-10-03T12:00:02Z","payload":{"type":"function_call_output","call_id":"call-1","output":"{}"}}"#.utf8), sourcePath: "/tmp/q.jsonl", session: session, pendingQuestionCallIDs: unrelated.pendingQuestionCallIDs)
    try check(answer.event?.state == .running && answer.pendingQuestionCallIDs.isEmpty, "matching question output did not resume")
}

func testHookBaselineAndDuplicateStop() throws {
    try inTemporaryDirectory { root in
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        let hookFile = root.appendingPathComponent("hooks.jsonl")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let stopped = ObservationEvent(key: SessionKey(workEnd: .claudeCode, nativeID: "shared"),
                                       target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable"),
                                       timestamp: Date(timeIntervalSince1970: 100), state: .stopped(.turnEnded))
        let line = String(decoding: try JSONEncoder().encode(stopped), as: UTF8.self) + "\n"
        try append(line, to: hookFile)
        let poller = LocalObservationPoller(claudeProjectsRoot: claude, codexSessionsRoot: codex, hookEventsFile: hookFile)
        poller.start()
        try check(poller.poll().isEmpty, "old hook event replayed")
        try append(line, to: hookFile)
        try append(line, to: hookFile)
        try check(poller.poll().count == 1, "duplicate stop was emitted twice")
        let running = ObservationEvent(key: stopped.key, target: stopped.target,
                                       timestamp: Date(timeIntervalSince1970: 101), state: .running)
        try append(String(decoding: try JSONEncoder().encode(running), as: UTF8.self) + "\n", to: hookFile)
        try check(poller.poll().last?.state == .running, "resumption after stop was lost")
    }
}

func testDelayedStopDoesNotSuppressNewAttention() throws {
    try inTemporaryDirectory { root in
        let hookFile = root.appendingPathComponent("hooks.jsonl")
        let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
            codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: hookFile)
        let router = AttentionRouter(startedAt: Date(timeIntervalSince1970: 0), settings: CharSettings(filterSeconds: 0))
        let key = SessionKey(workEnd: .claudeCode, nativeID: "delayed-stream")
        poller.start()
        func ingest(_ state: SessionState, at seconds: TimeInterval) throws {
            let event = ObservationEvent(key: key, target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable"),
                timestamp: Date(timeIntervalSince1970: seconds), state: state)
            try append(String(decoding: JSONEncoder().encode(event), as: UTF8.self) + "\n", to: hookFile)
            router.ingest(poller.poll())
            router.advance(to: Date(timeIntervalSince1970: seconds))
        }
        try ingest(.running, at: 10)
        try ingest(.stopped(.turnEnded), at: 5) // Delayed data from another stream.
        try check(router.nextVisit(for: .claudeCode) == nil, "a stale stop produced attention")
        try ingest(.stopped(.turnEnded), at: 15)
        try check(router.nextVisit(for: .claudeCode)?.stoppedAt == Date(timeIntervalSince1970: 15),
            "a delayed old stop suppressed the new attention item")
        router.ignoreNext(for: .claudeCode)
        try ingest(.running, at: 20)
        try ingest(.running, at: 30) // Duplicate state must still advance the observer's timestamp.
        try ingest(.stopped(.turnEnded), at: 25)
        try check(router.nextVisit(for: .claudeCode) == nil, "a stale stop after duplicate running produced attention")
        try ingest(.stopped(.turnEnded), at: 35)
        try check(router.nextVisit(for: .claudeCode)?.stoppedAt == Date(timeIntervalSince1970: 35),
            "the new stop after duplicate running was lost")
    }
}

func testCodexHooksPreserveWorkEnd() throws {
    try inTemporaryDirectory { root in
        for (origin, expected) in [("Codex Desktop", WorkEnd.codexDesktop), ("codex_cli", WorkEnd.codexCLI)] {
            let id = expected.rawValue
            let transcript = root.appendingPathComponent("\(id).jsonl")
            try append("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"originator\":\"\(origin)\",\"thread_source\":\"user\"}}\n", to: transcript)
            let input = "{\"session_id\":\"\(id)\",\"transcript_path\":\"\(transcript.path)\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\"}"
            let event = ObservationClassifier.codexHook(Data(input.utf8))
            try check(event?.key.workEnd == expected && event?.state == .stopped(.approval), "Codex hook lost work-end identity")
            let resumed = input.replacingOccurrences(of: "PermissionRequest", with: "PostToolUse")
            try check(ObservationClassifier.codexHook(Data(resumed.utf8))?.state == .running, "Codex approval did not resume")
        }
        let missing = Data(#"{"session_id":"unknown","transcript_path":"/tmp/missing.jsonl","hook_event_name":"PermissionRequest"}"#.utf8)
        try check(ObservationClassifier.codexHook(missing) == nil, "unknown work-end emitted")
    }
}

func testStructuredClassificationAndSuppression() throws {
    func classify(_ text: String, path: String = "/sessions/a.jsonl") -> ObservationEvent? {
        ObservationClassifier.claude(Data(text.utf8), sourcePath: path)
    }
    try check(classify(#"{"type":"assistant","sessionId":"a","timestamp":"2026-10-03T12:00:00Z","message":{"stop_reason":"tool_use"}}"#) == nil, "tool use inferred as stop")
    try check(classify(#"{"type":"assistant","sessionId":"a","timestamp":"2026-10-03T12:00:00Z","isSidechain":true,"message":{"stop_reason":"end_turn"}}"#) == nil, "child stop emitted")
    try check(classify(#"{"type":"assistant","sessionId":"a","timestamp":"2026-10-03T12:00:00Z","entrypoint":"remote","message":{"stop_reason":"end_turn"}}"#) == nil, "remote Claude stop emitted")
    let hook = ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/a.jsonl","hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"private body"}"#.utf8))
    try check(hook?.state == .stopped(.rateLimit), "structured rate limit not mapped")
    try check(hook?.target.sourcePath == "/sessions/a.jsonl", "hook target path lost")
    try check(ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/subagents/b.jsonl","hook_event_name":"Stop"}"#.utf8)) == nil, "child hook emitted")
    let approval = ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/a.jsonl","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8))
    let continued = ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/a.jsonl","hook_event_name":"PostToolUse","tool_name":"Bash"}"#.utf8))
    try check(approval?.state == .stopped(.approval) && continued?.state == .running, "approval did not resume after tool result")
    let question = ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/a.jsonl","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#.utf8))
    let answered = ObservationClassifier.claudeHook(Data(#"{"session_id":"a","transcript_path":"/sessions/a.jsonl","hook_event_name":"PostToolUse","tool_name":"AskUserQuestion"}"#.utf8))
    try check(question?.state == .stopped(.question) && answered?.state == .running, "question did not resume after answer")
    let meta = Data(#"{"type":"session_meta","payload":{"id":"child","originator":"Codex Desktop","source":{"subagent":{}},"thread_source":"subagent"}}"#.utf8)
    let child = ObservationClassifier.codex(meta, sourcePath: "/tmp/child.jsonl", session: nil).session
    try check(child?.isLocalRoot == false, "Codex child not suppressed")
    let remoteMeta = Data(#"{"type":"session_meta","payload":{"id":"remote","originator":"codex_cli","source":"remote"}}"#.utf8)
    let remote = ObservationClassifier.codex(remoteMeta, sourcePath: "/tmp/remote.jsonl", session: nil).session
    try check(remote?.isLocalRoot == false, "Codex remote not suppressed")
}

try testStartupAndAppends()
try testCodexIdentityAndBatch()
try testCodexQuestionResumesOnMatchingOutput()
try testHookBaselineAndDuplicateStop()
try testDelayedStopDoesNotSuppressNewAttention()
try testCodexHooksPreserveWorkEnd()
try testStructuredClassificationAndSuppression()
try testPiHookClassification()
try testExpandedSharedStreamPipeline()
try testNewAgentHooksAndKimiWire()
print("CharObservations: 10 contract checks passed")
