import Foundation
import CharCore

public struct KimiHookRecord: Codable {
    public let schema: String
    public let sessionID: String
    public let workEnd: WorkEnd
    public let timestamp: Date
    public let phase: String
    public let turnID: Int?
    public let approvalID: String?
}

public enum NewAgentHooks {
    public static func kimi(_ data: Data, timestamp: Date = Date()) -> KimiHookRecord? {
        guard let record = object(data), let id = record["session_id"] as? String, !id.isEmpty,
              let kind = record["hook_event_name"] as? String else { return nil }
        let workEnd: WorkEnd
        switch record["client_type"] as? String {
        case "kimi_code_cli": workEnd = .kimiCLI
        case "kimi_code_desktop": workEnd = .kimiDesktop
        default: return nil
        }
        var turnID: Int?
        var approvalID: String?
        switch kind {
        case "SessionStart", "SessionEnd": break
        case "PermissionRequest", "PermissionResult":
            guard record["agent_id"] as? String == "main",
                  let turn = record["turn_id"] as? Int, turn >= 0,
                  let approval = record["id"] as? String, !approval.isEmpty else { return nil }
            turnID = turn
            approvalID = approval
        default: return nil
        }
        return KimiHookRecord(schema: "char.kimi-hook.v1", sessionID: id, workEnd: workEnd,
                              timestamp: timestamp, phase: kind, turnID: turnID, approvalID: approvalID)
    }

    public static func deepseek(_ data: Data) -> ObservationEvent? {
        guard let record = object(data), record["client_type"] as? String == "deepseek_desktop",
              record["root_session"] as? Bool == true,
              let id = record["session_id"] as? String, !id.isEmpty,
              let milliseconds = record["time"] as? Double, milliseconds.isFinite, milliseconds >= 0,
              let kind = record["kind"] as? String else { return nil }
        let state: SessionState
        switch kind {
        case "running": state = .running
        case "question": state = .stopped(.question)
        case "approval": state = .stopped(.approval)
        case "turnEnded": state = .stopped(.turnEnded)
        case "failure": state = .stopped(.failure)
        case "rateLimit": state = .stopped(.rateLimit)
        case "contextExhausted": state = .stopped(.contextExhausted)
        case "unclassified": state = .stopped(.unclassified)
        case "closed": state = .closed
        default: return nil
        }
        return ObservationEvent(key: SessionKey(workEnd: .deepseekDesktop, nativeID: id),
                                target: SessionTarget(bundleIdentifier: "com.deepseek.dsh"),
                                timestamp: Date(timeIntervalSince1970: milliseconds / 1000), state: state)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
