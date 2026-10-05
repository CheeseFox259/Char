import Foundation
import CharCore
import CharObservations

func testIncrementalNestedJournalDiscovery() throws {
    try inTemporaryDirectory { root in
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        let poller = LocalObservationPoller(claudeProjectsRoot: claude, codexSessionsRoot: codex)
        poller.start() // Neither root exists yet.
        func stopped(_ id: String, at seconds: Int) -> String {
            "{\"type\":\"assistant\",\"sessionId\":\"\(id)\",\"timestamp\":\"2026-10-03T12:00:\(String(format: "%02d", seconds)).000Z\",\"message\":{\"stop_reason\":\"end_turn\"}}\n"
        }
        let nested = claude.appendingPathComponent("project/deep/fresh.jsonl")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try append(stopped("fresh", at: 1), to: nested)
        try check(poller.poll().first?.key.nativeID == "fresh", "new root/nested journal missed by next poll")
        try check(poller.poll().isEmpty, "cached directory replayed journal")
        let sibling = nested.deletingLastPathComponent().appendingPathComponent("sibling.jsonl")
        try append(stopped("sibling", at: 2), to: sibling)
        try check(poller.poll().first?.key.nativeID == "sibling", "new journal in cached directory missed")
        let renamed = claude.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: claude.appendingPathComponent("project"), to: renamed)
        try append(stopped("after-rename", at: 3), to: renamed.appendingPathComponent("deep/later.jsonl"))
        try check(poller.poll().contains { $0.key.nativeID == "after-rename" }, "renamed directory's new journal missed")
        try FileManager.default.removeItem(at: claude)
        try check(poller.poll().isEmpty, "deleted root emitted phantom events")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try append(stopped("recreated", at: 4), to: claude.appendingPathComponent("new.jsonl"))
        try check(poller.poll().first?.key.nativeID == "recreated", "recreated root missed")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: claude)
        let throughAlias = LocalObservationPoller(claudeProjectsRoot: alias, codexSessionsRoot: codex)
        throughAlias.start()
        try append(stopped("alias-new", at: 5), to: claude.appendingPathComponent("alias-new.jsonl"))
        try check(throughAlias.poll().first?.key.nativeID == "alias-new", "symlinked root stopped discovering journals")
    }
}
