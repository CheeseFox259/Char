import Foundation
import Darwin
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
    private var enabledWorkEnds = Set(WorkEnd.allCases)
    private var enabledAfter: [WorkEnd: Date] = [:]

    /// Reloading one adapter does not move cursors belonging to still-enabled adapters.
    public func setEnabledWorkEnds(_ enabled: Set<WorkEnd>, at date: Date = Date()) {
        let added = enabled.subtracting(enabledWorkEnds)
        let old = enabledWorkEnds
        enabledWorkEnds = enabled
        for end in added { enabledAfter[end] = date }
        lastEvents = lastEvents.filter { enabled.contains($0.key.workEnd) }
        if !old.contains(.claudeCode), enabled.contains(.claudeCode) { baseline(source: .claude) }
        let codex: Set<WorkEnd> = [.codexCLI, .codexDesktop]
        if old.isDisjoint(with: codex), !enabled.isDisjoint(with: codex) { baseline(source: .codex) }
        let kimi: Set<WorkEnd> = [.kimiCLI, .kimiDesktop]
        if old.isDisjoint(with: kimi), !enabled.isDisjoint(with: kimi) { kimiPoller?.start() }
    }

    private func baseline(source wanted: Source) {
        for (url, source) in files() where source == wanted {
            let metadata = fileMetadata(url)
            cursors[url.path] = Cursor(offset: metadata?.size ?? 0,
                identity: metadata?.identity,
                codexSession: source == .codex ? ObservationClassifier.codexMetadata(in: url) : nil)
        }
    }

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
            let metadata = fileMetadata(url)
            let size = metadata?.size ?? 0
            let identity = metadata?.identity
            let session = source == .codex ? ObservationClassifier.codexMetadata(in: url) : nil
            cursors[url.path] = Cursor(offset: size, identity: identity, codexSession: session)
        }
        if !enabledWorkEnds.isDisjoint(with: [.kimiCLI, .kimiDesktop]) { kimiPoller?.start() }
        started = true
    }

    public func poll() -> [ObservationEvent] {
        if !started { start(); return [] }
        var events: [ObservationEvent] = []
        for (url, source) in files() {
            guard let metadata = fileMetadata(url) else { continue }
            let size = metadata.size
            let identity = metadata.identity
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
        if !enabledWorkEnds.isDisjoint(with: [.kimiCLI, .kimiDesktop]) { events.append(contentsOf: kimiPoller?.poll() ?? []) }
        // A sleep/wake read is one batch. Ordering by recorded time keeps state transitions stable.
        let ordered = events.enumerated().sorted { left, right in
            left.element.timestamp == right.element.timestamp ? left.offset < right.offset : left.element.timestamp < right.element.timestamp
        }.map(\.element)
        return ordered.filter { event in
            guard enabledWorkEnds.contains(event.key.workEnd),
                  event.timestamp >= (enabledAfter[event.key.workEnd] ?? .distantPast) else { return false }
            let previous = lastEvents[event.key]
            if let previous, event.timestamp < previous.timestamp { return false }
            // Even a duplicate state advances the watermark: delayed records must not undo it.
            lastEvents[event.key] = event
            return previous?.state != event.state
        }
    }

    // Only byte length and inode are needed for append/truncate/replace cursors.
    // FileManager's broad attribute dictionary also reads extended attributes.
    private func fileMetadata(_ url: URL) -> (size: UInt64, identity: NSNumber)? {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &value)
        }
        guard result == 0, value.st_size >= 0 else { return nil }
        return (UInt64(value.st_size), NSNumber(value: value.st_ino))
    }

    private enum Source { case claude, codex, hook }

    private func files() -> [(URL, Source)] {
        var result: [(URL, Source)] = []
        for (root, source) in [(claudeProjectsRoot, Source.claude), (codexSessionsRoot, Source.codex)] {
            if source == .claude && !enabledWorkEnds.contains(.claudeCode) { continue }
            if source == .codex && enabledWorkEnds.isDisjoint(with: [.codexCLI, .codexDesktop]) { continue }
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" { result.append((url, source)) }
            }
        }
        if !enabledWorkEnds.isEmpty, let hookEventsFile, FileManager.default.fileExists(atPath: hookEventsFile.path) { result.append((hookEventsFile, .hook)) }
        return result.sorted { $0.0.path < $1.0.path }
    }
}
