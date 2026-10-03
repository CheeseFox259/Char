import Foundation
import CharCore

/// Reads local session journals without replaying events present when `start()` is called.
/// Apply every event returned by one `poll()` before advancing the attention clock.
public final class LocalObservationPoller {
    private struct Cursor {
        var offset: UInt64
        var identity: NSNumber?
        var codexSession: CodexSession?
        var pendingQuestionCallIDs: Set<String> = []
    }

    private let claudeProjectsRoot: URL
    private let codexSessionsRoot: URL
    private let kimiPoller: KimiObservationPoller?
    private let hookEventsFile: URL?
    private var cursors: [String: Cursor] = [:]
    private var lastEvents: [SessionKey: ObservationEvent] = [:]
    private var started = false

    public init(claudeProjectsRoot: URL, codexSessionsRoot: URL, hookEventsFile: URL? = nil, kimiSessionsRoot: URL? = nil) {
        self.claudeProjectsRoot = claudeProjectsRoot
        self.codexSessionsRoot = codexSessionsRoot
        self.hookEventsFile = hookEventsFile
        self.kimiPoller = kimiSessionsRoot.flatMap { root in hookEventsFile.map { KimiObservationPoller(kimiSessionsRoot: root, hookEventsFile: $0) } }
    }

    public func start() {
        cursors.removeAll()
        lastEvents.removeAll()
        for (url, source) in files() {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let identity = attributes?[.systemFileNumber] as? NSNumber
            let session = source == .codex ? ObservationClassifier.codexMetadata(in: url) : nil
            cursors[url.path] = Cursor(offset: size, identity: identity, codexSession: session)
        }
        kimiPoller?.start()
        started = true
    }

    public func poll() -> [ObservationEvent] {
        if !started { start(); return [] }
        var events: [ObservationEvent] = []
        for (url, source) in files() {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value else { continue }
            let identity = attributes[.systemFileNumber] as? NSNumber
            var cursor = cursors[url.path] ?? Cursor(offset: 0, identity: identity, codexSession: nil)
            if size < cursor.offset || (cursor.identity != nil && identity != cursor.identity) {
                cursor = Cursor(offset: 0, identity: identity, codexSession: nil)
            }
            guard size > cursor.offset,
                  let handle = try? FileHandle(forReadingFrom: url) else {
                cursors[url.path] = cursor
                continue
            }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: cursor.offset)
                let data = try handle.readToEnd() ?? Data()
                guard let lastNewline = data.lastIndex(of: 10) else {
                    cursors[url.path] = cursor
                    continue
                }
                let complete = data.prefix(through: lastNewline)
                cursor.offset += UInt64(complete.count)
                for line in complete.split(separator: 10) {
                    let lineData = Data(line)
                    switch source {
                    case .claude:
                        if let event = ObservationClassifier.claude(lineData, sourcePath: url.path) { events.append(event) }
                    case .codex:
                        let result = ObservationClassifier.codex(lineData, sourcePath: url.path,
                                                                 session: cursor.codexSession,
                                                                 pendingQuestionCallIDs: cursor.pendingQuestionCallIDs)
                        cursor.codexSession = result.session
                        cursor.pendingQuestionCallIDs = result.pendingQuestionCallIDs
                        if let event = result.event { events.append(event) }
                    case .hook:
                        if let event = try? JSONDecoder().decode(ObservationEvent.self, from: lineData) { events.append(event) }
                    }
                }
            } catch { /* Retry unread bytes on the next poll. */ }
            cursors[url.path] = cursor
        }
        events.append(contentsOf: kimiPoller?.poll() ?? [])
        // A sleep/wake read is one batch. Ordering by recorded time keeps state transitions stable.
        let ordered = events.enumerated().sorted { left, right in
            left.element.timestamp == right.element.timestamp ? left.offset < right.offset : left.element.timestamp < right.element.timestamp
        }.map(\.element)
        return ordered.filter { event in
            let previous = lastEvents[event.key]
            if let previous, event.timestamp < previous.timestamp { return false }
            // Even a duplicate state advances the watermark: delayed records must not undo it.
            lastEvents[event.key] = event
            return previous?.state != event.state
        }
    }

    private enum Source { case claude, codex, hook }

    private func files() -> [(URL, Source)] {
        var result: [(URL, Source)] = []
        for (root, source) in [(claudeProjectsRoot, Source.claude), (codexSessionsRoot, Source.codex)] {
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" { result.append((url, source)) }
            }
        }
        if let hookEventsFile, FileManager.default.fileExists(atPath: hookEventsFile.path) { result.append((hookEventsFile, .hook)) }
        return result.sorted { $0.0.path < $1.0.path }
    }
}
