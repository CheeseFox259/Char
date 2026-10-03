import Foundation
import CharCore

/// SessionStart identifies the owning native client; only the main Agent's durable wire is read.
public final class KimiObservationPoller {
    private struct Cursor { var offset: UInt64; var inode: NSNumber? }
    private let root: URL
    private let hooks: URL
    private var cursors: [String: Cursor] = [:]
    private var bindings: [String: KimiHookRecord] = [:]
    private var closedAt: [String: Date] = [:]
    private var resolvedApprovals: Set<String> = []
    private var endedTurns: [String: Int] = [:]
    private var pendingQuestions: [String: Set<String>] = [:]

    public init(kimiSessionsRoot: URL, hookEventsFile: URL) {
        root = kimiSessionsRoot
        hooks = hookEventsFile
    }

    public func start() {
        cursors.removeAll()
        bindings.removeAll()
        closedAt.removeAll()
        pendingQuestions.removeAll()
        endedTurns.removeAll()
        resolvedApprovals.removeAll()
        consumeBindings(read(hooks))
        for file in files() {
            let id = sessionID(for: file)
            if bindings[id] != nil {
                for line in read(file) {
                    guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                          record["agentId"] as? String == "main", record["type"] as? String == "turn.ended",
                          let turnID = record["turnId"] as? Int else { continue }
                    endedTurns[id] = max(endedTurns[id] ?? -1, turnID)
                }
            }
            baseline(file)
        }
    }

    public func poll() -> [ObservationEvent] {
        let hookLines = read(hooks)
        consumeBindings(hookLines)
        var result: [ObservationEvent] = hookLines.compactMap {
            guard let record = decodeHook($0), record.phase == "SessionEnd" else { return nil }
            return makeEvent(record, state: .closed)
        }
        for file in files() {
            let id = sessionID(for: file)
            // The hook reader can run just before SessionStart is appended. Leave unbound bytes
            // on disk until their owning client is known; startup cursors still skip old content.
            guard let binding = bindings[id] else { continue }
            let lines = read(file)
            guard binding.phase != "SessionEnd" else { continue }
            for line in lines {
                guard let event = classify(line, binding: binding, sourcePath: file.path) else { continue }
                result.append(event)
            }
        }
        let approvals = hookLines.compactMap(decodeHook).filter { $0.approvalID != nil }
        for record in approvals where record.phase == "PermissionResult" {
            resolvedApprovals.insert("\(record.sessionID):\(record.approvalID!)")
        }
        for record in approvals {
            guard let turnID = record.turnID, let approvalID = record.approvalID,
                  let binding = bindings[record.sessionID], binding.workEnd == record.workEnd,
                  binding.phase != "SessionEnd", record.timestamp >= binding.timestamp,
                  turnID > (endedTurns[record.sessionID] ?? -1) else { continue }
            if record.phase == "PermissionRequest" && resolvedApprovals.contains("\(record.sessionID):\(approvalID)") { continue }
            result.append(makeEvent(record, state: record.phase == "PermissionRequest" ? .stopped(.approval) : .running))
        }
        return result
    }

    private func decodeHook(_ line: Data) -> KimiHookRecord? {
        guard let record = try? JSONDecoder().decode(KimiHookRecord.self, from: line),
              record.schema == "char.kimi-hook.v1", [.kimiCLI, .kimiDesktop].contains(record.workEnd),
              !record.sessionID.isEmpty else { return nil }
        return record
    }

    private func makeEvent(_ record: KimiHookRecord, state: SessionState, timestamp: Date? = nil, sourcePath: String? = nil) -> ObservationEvent {
        ObservationEvent(key: SessionKey(workEnd: record.workEnd, nativeID: record.sessionID),
                         target: SessionTarget(bundleIdentifier: record.workEnd == .kimiDesktop ? "com.kimi.code.desktop" : "dev.warp.Warp-Stable", sourcePath: sourcePath),
                         timestamp: timestamp ?? record.timestamp, state: state)
    }

    private func consumeBindings(_ lines: [Data]) {
        for line in lines {
            guard let record = decodeHook(line), ["SessionStart", "SessionEnd"].contains(record.phase) else { continue }
            if let previous = bindings[record.sessionID], previous.timestamp > record.timestamp { continue }
            if record.timestamp != bindings[record.sessionID]?.timestamp { pendingQuestions[record.sessionID] = [] }
            if record.phase == "SessionEnd" { closedAt[record.sessionID] = record.timestamp }
            bindings[record.sessionID] = record
        }
    }

    private func classify(_ line: Data, binding: KimiHookRecord, sourcePath: String) -> ObservationEvent? {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              record["agentId"] as? String == "main",
              let time = record["time"] as? Double, time.isFinite, time >= 0 else { return nil }
        let timestamp = Date(timeIntervalSince1970: time / 1000)
        // SessionStart is stamped on hook receipt, possibly after this native event. Byte
        // baselines skip startup history; the local poller/router enforce event-time watermarks.
        // A known close also rejects the previous generation when a client switch changes WorkEnd.
        let id = binding.sessionID
        if let end = closedAt[id], timestamp <= end { return nil }
        let state: SessionState
        switch record["type"] as? String {
        case "turn.prompt", "turn.steer": state = .running
        case "turn.ended":
            guard let turnID = record["turnId"] as? Int else { return nil }
            endedTurns[id] = max(endedTurns[id] ?? -1, turnID)
            switch record["reason"] as? String {
            case "completed":
                guard pendingQuestions[id]?.isEmpty != false else { return nil }
                state = .stopped(.turnEnded)
            case "failed":
                let error = record["error"] as? [String: Any]
                switch error?["code"] as? String {
                case "provider.rate_limit": state = .stopped(.rateLimit)
                case "context.overflow": state = .stopped(.contextExhausted)
                default: state = .stopped(.failure)
                }
            case "cancelled", "blocked": state = .stopped(.unclassified)
            default: return nil
            }
        case "context.append_loop_event":
            guard let event = record["event"] as? [String: Any] else { return nil }
            if event["type"] as? String == "step.begin" {
                return makeEvent(binding, state: .running, timestamp: timestamp, sourcePath: sourcePath)
            }
            guard let callID = event["toolCallId"] as? String else { return nil }
            if event["type"] as? String == "tool.call", event["name"] as? String == "AskUserQuestion" {
                let args = event["args"] as? [String: Any]
                guard args?["background"] as? Bool != true else { return nil }
                pendingQuestions[id, default: []].insert(callID)
                state = .stopped(.question)
            } else if event["type"] as? String == "tool.result", pendingQuestions[id]?.remove(callID) != nil {
                state = .running
            } else { return nil }
        default: return nil
        }
        return makeEvent(binding, state: state, timestamp: timestamp, sourcePath: sourcePath)
    }

    private func sessionID(for file: URL) -> String {
        file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    private func files() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent == "wire.jsonl" && $0.deletingLastPathComponent().lastPathComponent == "main"
                && $0.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "agents"
        }.sorted { $0.path < $1.path }
    }

    private func baseline(_ file: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        cursors[file.path] = Cursor(offset: (attributes?[.size] as? NSNumber)?.uint64Value ?? 0,
                                   inode: attributes?[.systemFileNumber] as? NSNumber)
    }

    private func read(_ file: URL) -> [Data] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let inode = attributes[.systemFileNumber] as? NSNumber
        var cursor = cursors[file.path] ?? Cursor(offset: 0, inode: inode)
        if size < cursor.offset || cursor.inode != inode { cursor = Cursor(offset: 0, inode: inode) }
        do {
            try handle.seek(toOffset: cursor.offset)
            let data = try handle.readToEnd() ?? Data()
            guard let newline = data.lastIndex(of: 10) else { return [] }
            let complete = data.prefix(through: newline)
            cursor.offset += UInt64(complete.count)
            cursors[file.path] = cursor
            return complete.split(separator: UInt8(10)).map { Data($0) }
        } catch { return [] }
    }
}
