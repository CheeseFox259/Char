import Foundation
import CharCore

/// Minimal event envelope emitted by the opt-in Pi extension, never a transcript.
public enum PiObservationClassifier {
    public static func hook(_ data: Data) -> ObservationEvent? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["schema"] as? Int == 1,
              let id = value["session_id"] as? String, !id.isEmpty,
              let name = value["event"] as? String,
              let timestamp = value["timestamp"] as? String,
              let date = ISO8601DateFormatter().date(from: timestamp) ?? fractionalDate(timestamp) else { return nil }
        let state: SessionState
        switch name {
        case "running": state = .running
        case "question": state = .stopped(.question)
        case "settled":
            switch value["reason"] as? String {
            case "turnEnded": state = .stopped(.turnEnded)
            case "failure": state = .stopped(.failure)
            case "unclassified": state = .stopped(.unclassified)
            default: return nil
            }
        case "closed": state = .closed
        default: return nil
        }
        return ObservationEvent(key: SessionKey(workEnd: .pi, nativeID: id),
            target: SessionTarget(bundleIdentifier: "dev.warp.Warp-Stable",
                tmuxPaneID: value["tmux_pane"] as? String,
                processID: (value["process_id"] as? NSNumber)?.int32Value,
                sourcePath: value["session_file"] as? String),
            timestamp: date, state: state)
    }

    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
