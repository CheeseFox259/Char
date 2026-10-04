import Foundation
import CharCore
import CharObservations

func testFileCursorPartialTruncationAndRotation() throws {
    try inTemporaryDirectory { root in
        let file = root.appendingPathComponent("hooks.jsonl")
        try Data().write(to: file)
        let poller = LocalObservationPoller(claudeProjectsRoot: root.appendingPathComponent("claude"),
            codexSessionsRoot: root.appendingPathComponent("codex"), hookEventsFile: file)
        poller.start()
        func record(_ state: SessionState, _ time: Double, padding: String = "") throws -> String {
            let event = ObservationEvent(key: SessionKey(workEnd: .claudeCode, nativeID: "cursor"),
                target: SessionTarget(bundleIdentifier: "fixture", sourcePath: padding),
                timestamp: Date(timeIntervalSince1970: time), state: state)
            return String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        }
        try append(try record(.stopped(.question), 1000) + "\n", to: file)
        try check(poller.poll().first?.state == .stopped(.question), "initial cursor append lost")
        try append(try record(.running, 1001), to: file)
        try check(poller.poll().isEmpty, "partial record emitted")
        try append("\n", to: file)
        try check(poller.poll().first?.state == .running, "partial record completion lost")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0); try handle.close()
        try append(try record(.stopped(.question), 1002) + "\n", to: file)
        try check(poller.poll().first?.state == .stopped(.question), "same-inode truncation missed")
        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("archive.log"))
        try append(try record(.running, 1003, padding: String(repeating: "x", count: 300)) + "\n", to: file)
        try check(poller.poll().first?.state == .running, "larger replacement inode did not reset cursor")
        try check(poller.poll().isEmpty, "replacement reread twice")
    }
}
