import Foundation
import CharCore
import CharObservations

func testPiHookClassification() throws {
    func piCheck(_ condition: Bool, _ message: String) throws { try check(condition, message) }
    func event(_ name: String, reason: String? = nil, tmux: String? = nil) throws -> ObservationEvent? {
        var value: [String: Any] = ["schema": 1, "session_id": "pi-root", "event": name,
            "timestamp": "2026-10-04T12:00:00.123Z", "process_id": 123,
            "session_file": "/private/pi-session.jsonl", "prompt": "must not persist"]
        if let reason { value["reason"] = reason }
        if let tmux { value["tmux_pane"] = tmux }
        return PiObservationClassifier.hook(try JSONSerialization.data(withJSONObject: value))
    }
    let direct = try event("running")
    try check(direct?.key == SessionKey(workEnd: .pi, nativeID: "pi-root"), "Pi native identity lost")
    try check(direct?.state == .running && direct?.target.tmuxPaneID == nil, "Pi direct Warp requires tmux")
    try piCheck(try event("question", tmux: "%2")?.target.tmuxPaneID == "%2", "Pi optional tmux metadata lost")
    try piCheck(try event("question")?.state == .stopped(.question), "Pi blocking question lost")
    try piCheck(try event("settled", reason: "failure")?.state == .stopped(.failure), "Pi final failure lost")
    try piCheck(try event("settled", reason: "turnEnded")?.state == .stopped(.turnEnded), "Pi settlement lost")
    try piCheck(try event("settled", reason: "unclassified")?.state == .stopped(.unclassified), "Pi final interruption lost")
    try piCheck(try event("closed")?.state == .closed, "Pi closure lost")
    try piCheck(try event("agent_end") == nil && event("settled", reason: "rate_limit") == nil, "Pi invented unsupported stop")
    let encoded = try JSONEncoder().encode(direct!)
    try check(!String(decoding: encoded, as: UTF8.self).contains("must not persist"), "Pi persisted prompt")
    try check(PiObservationClassifier.hook(Data(#"{"schema":1,"session_id":"p","event":"running","timestamp":"bad"}"#.utf8)) == nil,
              "Pi invalid timestamp accepted")
}
