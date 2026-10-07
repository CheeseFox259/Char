import Foundation
import CharCore

public struct CodexSession: Equatable {
    public let id: String
    public let workEnd: WorkEnd
    public let isLocalRoot: Bool

    public init(id: String, workEnd: WorkEnd, isLocalRoot: Bool) {
        self.id = id
        self.workEnd = workEnd
        self.isLocalRoot = isLocalRoot
    }
}

public enum ObservationClassifier {
    private static let dateFormatter = ISO8601DateFormatter()
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return fractionalFormatter.date(from: value) ?? dateFormatter.date(from: value)
    }

    public static func claude(_ data: Data, sourcePath: String) -> ObservationEvent? {
        guard let record = object(data),
              record["isSidechain"] as? Bool != true,
              !sourcePath.contains("/subagents/"),
              (record["entrypoint"] as? String).map({ $0 == "cli" }) ?? true,
              let id = (record["sessionId"] ?? record["session_id"]) as? String else { return nil }
        let type = record["type"] as? String
        let state: SessionState
        switch type {
        case "user":
            guard record["isMeta"] as? Bool != true else { return nil }
            state = .running
        case "assistant":
            guard let message = record["message"] as? [String: Any],
                  message["stop_reason"] as? String == "end_turn" else { return nil }
            state = .stopped(.turnEnded)
        default: return nil
        }
        guard let timestamp = date(record["timestamp"]) else { return nil }
        return ObservationEvent(key: SessionKey(workEnd: .claudeCode, nativeID: id), target: target(.claudeCode, record, sourcePath), timestamp: timestamp, state: state)
    }

    public static func codexMetadata(in url: URL) -> CodexSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 128_000),
              let first = data.split(separator: 10).first else { return nil }
        return metadata(Data(first))
    }

    private static func metadata(_ data: Data) -> CodexSession? {
        guard let record = object(data), record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any],
              let id = (payload["id"] ?? payload["session_id"]) as? String else { return nil }
        let originator = (payload["originator"] as? String)?.lowercased() ?? ""
        let workEnd: WorkEnd = originator.contains("desktop") ? .codexDesktop : .codexCLI
        let source = payload["source"] as? String
        let remote = source == "remote" || source == "cloud" || (payload["thread_source"] as? String) == "remote"
        let child = payload["parent_thread_id"] != nil || payload["agent_path"] != nil
            || (payload["thread_source"] as? String) == "subagent" || payload["source"] is [String: Any]
        return CodexSession(id: id, workEnd: workEnd, isLocalRoot: !remote && !child)
    }

    public static func codex(_ data: Data, sourcePath: String, session: CodexSession?,
                             pendingQuestionCallIDs: Set<String> = []) -> (session: CodexSession?, event: ObservationEvent?, pendingQuestionCallIDs: Set<String>) {
        guard let record = object(data) else { return (session, nil, pendingQuestionCallIDs) }
        if record["type"] as? String == "session_meta" { return (metadata(data) ?? session, nil, pendingQuestionCallIDs) }
        guard let session, session.isLocalRoot,
              let payload = record["payload"] as? [String: Any] else { return (session, nil, pendingQuestionCallIDs) }
        let state: SessionState
        var pending = pendingQuestionCallIDs
        switch (record["type"] as? String, payload["type"] as? String) {
        case ("event_msg", "task_started"), ("event_msg", "turn_started"): state = .running
        case ("event_msg", "task_complete"), ("event_msg", "turn_complete"): state = .stopped(.turnEnded)
        case ("event_msg", "turn_aborted"): state = .stopped(.unclassified)
        case ("response_item", "function_call"):
            guard let name = payload["name"] as? String,
                  ["request_user_input", "request_user_input_async"].contains(name),
                  let callID = payload["call_id"] as? String else { return (session, nil, pending) }
            pending.insert(callID)
            state = .stopped(.question)
        case ("response_item", "function_call_output"):
            guard let callID = payload["call_id"] as? String,
                  pending.remove(callID) != nil else { return (session, nil, pending) }
            state = .running
        default: return (session, nil, pending)
        }
        guard let timestamp = date(record["timestamp"]) else { return (session, nil, pendingQuestionCallIDs) }
        let event = ObservationEvent(key: SessionKey(workEnd: session.workEnd, nativeID: session.id),
                                     target: target(session.workEnd, payload, sourcePath), timestamp: timestamp, state: state)
        return (session, event, pending)
    }

    public static func claudeHook(_ data: Data, timestamp: Date = Date()) -> ObservationEvent? {
        guard let record = object(data), let id = record["session_id"] as? String,
              let kind = record["hook_event_name"] as? String,
              record["agent_id"] == nil,
              let path = record["transcript_path"] as? String,
              !path.contains("/subagents/") else { return nil }
        let state: SessionState
        switch kind {
        case "UserPromptSubmit", "SessionStart", "PostToolUse", "PostToolUseFailure", "ElicitationResult": state = .running
        case "PreToolUse":
            if record["tool_name"] as? String == "AskUserQuestion" { state = .stopped(.question) }
            else { state = .running }
        case "PermissionRequest": state = .stopped(.approval)
        case "Elicitation": state = .stopped(.question)
        case "Stop": state = .stopped(.turnEnded)
        case "StopFailure":
            switch record["error"] as? String {
            case "rate_limit": state = .stopped(.rateLimit)
            case nil: state = .stopped(.unclassified)
            default: state = .stopped(.failure)
            }
        case "Notification":
            switch record["notification_type"] as? String {
            case "permission_prompt": state = .stopped(.approval)
            case "elicitation_dialog": state = .stopped(.question)
            default: return nil
            }
        case "SessionEnd": state = .closed
        default: return nil
        }
        return ObservationEvent(key: SessionKey(workEnd: .claudeCode, nativeID: id),
                                target: target(.claudeCode, record, path), timestamp: timestamp, state: state)
    }

    /// Codex hooks do not identify CLI versus Desktop, so require a matching local session journal.
    public static func codexHook(_ data: Data, timestamp: Date = Date()) -> ObservationEvent? {
        guard let record = object(data),
              let id = record["session_id"] as? String,
              let path = record["transcript_path"] as? String,
              let kind = record["hook_event_name"] as? String,
              !path.contains("/subagents/"),
              let session = codexMetadata(in: URL(fileURLWithPath: path)),
              session.id == id, session.isLocalRoot else { return nil }
        let state: SessionState
        switch kind {
        case "SessionStart", "UserPromptSubmit", "PostToolUse": state = .running
        case "PreToolUse":
            if ["request_user_input", "request_user_input_async"].contains(record["tool_name"] as? String ?? "") {
                state = .stopped(.question)
            } else { state = .running }
        case "PermissionRequest": state = .stopped(.approval)
        case "Stop": state = .stopped(.turnEnded)
        case "Interrupt": state = .stopped(.unclassified)
        case "SessionEnd": state = .closed
        default: return nil
        }
        return ObservationEvent(key: SessionKey(workEnd: session.workEnd, nativeID: id),
                                target: target(session.workEnd, record, path), timestamp: timestamp, state: state)
    }

    private static func target(_ workEnd: WorkEnd, _ record: [String: Any], _ sourcePath: String) -> SessionTarget {
        let bundle = workEnd == .codexDesktop ? "com.openai.codex" : "dev.warp.Warp-Stable"
        let pane = (record["tmux_pane"] ?? record["tmuxPaneID"]) as? String
        let pid = (record["pid"] as? NSNumber)?.int32Value
        return SessionTarget(bundleIdentifier: bundle, tmuxPaneID: pane, processID: pid, sourcePath: sourcePath)
    }
}
