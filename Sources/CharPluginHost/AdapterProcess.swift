import Foundation
import CharCore

public enum AdapterFailure: Error, CustomStringConvertible {
    case unavailable(String)
    public var description: String { if case let .unavailable(message) = self { return message }; return "Adapter unavailable" }
}

/// One process and one ordered pipe. All transport state lives on the private queue.
public final class AdapterProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Char.plugin.transport")
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var events: [ObservationEvent] = []
    private var ended = false
    public let plugin: IntegrationPlugin
    public let instanceID = UUID().uuidString

    public init(plugin: IntegrationPlugin, descriptor: AdapterDescriptor, packageURL: URL, environment: [String: String]) throws {
        self.plugin = plugin
        let entry = packageURL.appendingPathComponent(descriptor.entrypoint).standardizedFileURL
        guard entry.path.hasPrefix(packageURL.standardizedFileURL.path + "/") else { throw AdapterFailure.unavailable("Invalid adapter entrypoint") }
        switch descriptor.runtime {
        case .executable: process.executableURL = entry
        case .node, .python3:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [descriptor.runtime.rawValue, entry.path]
        }
        process.currentDirectoryURL = packageURL
        process.environment = environment
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            self?.queue.async { [weak self] in self?.receive(bytes) }
        }
        process.terminationHandler = { [weak self] _ in self?.queue.async { [weak self] in self?.finish("Adapter exited") } }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; throw error }
    }

    public func request(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 3) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !ended else { continuation.resume(throwing: AdapterFailure.unavailable("Adapter is stopped")); return }
                let id = UUID().uuidString
                do {
                    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "id": id, "method": method, "params": params]) + Data([10])
                    pending[id] = continuation
                    try input.fileHandleForWriting.write(contentsOf: data)
                    queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                        self?.pending.removeValue(forKey: id)?.resume(throwing: AdapterFailure.unavailable("Adapter request timed out: \(method)"))
                    }
                } catch { pending.removeValue(forKey: id); continuation.resume(throwing: error) }
            }
        }
    }

    public func drainEvents() -> [ObservationEvent] { queue.sync { let result = events; events.removeAll(keepingCapacity: true); return result } }
    public func stop() { queue.sync { finish("Adapter stopped") }; if process.isRunning { process.terminate() } }
    public var processID: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }
    deinit { output.fileHandleForReading.readabilityHandler = nil; if process.isRunning { process.terminate() } }

    private func finish(_ detail: String) {
        guard !ended else { return }; ended = true
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        let requests = pending.values; pending.removeAll(); events.removeAll()
        for request in requests { request.resume(throwing: AdapterFailure.unavailable(detail)) }
    }
    private func receive(_ data: Data) {
        guard !ended else { return }
        guard !data.isEmpty else { finish("Adapter closed its protocol stream"); return }
        buffer.append(data)
        guard buffer.count <= 1_048_576 else { finish("Adapter frame exceeds limit"); if process.isRunning { process.terminate() }; return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any], record["version"] as? Int == 1 else { finish("Invalid adapter protocol"); if process.isRunning { process.terminate() }; return }
            if let id = record["id"] as? String, let continuation = pending.removeValue(forKey: id) {
                if let result = record["result"] as? [String: Any] { continuation.resume(returning: result) }
                else { continuation.resume(throwing: AdapterFailure.unavailable(record["error"] as? String ?? "Adapter operation failed")) }
            } else if let raw = record["event"] as? [String: Any], let event = decodeEvent(raw) {
                if events.count < 4096 { events.append(event) }
            }
        }
    }
    private func decodeEvent(_ raw: [String: Any]) -> ObservationEvent? {
        guard plugin.adapter?.capabilities.contains(.monitor) == true,
              let end = plugin.workEnd, raw["workEnd"] as? String == end.rawValue,
              let id = raw["nativeID"] as? String, !id.isEmpty, id.count <= 1024,
              let value = raw["timestamp"] as? String else { return nil }
        let clock = ISO8601DateFormatter(); clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let time = clock.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let time else { return nil }
        let state: SessionState
        switch raw["state"] as? String {
        case "running": state = .running
        case "closed": state = .closed
        case "stopped": guard let reason = raw["reason"] as? String, let parsed = StopReason(rawValue: reason) else { return nil }; state = .stopped(parsed)
        default: return nil
        }
        let target = raw["target"] as? [String: Any] ?? [:]
        return ObservationEvent(key: SessionKey(workEnd: end, nativeID: id),
            target: SessionTarget(bundleIdentifier: plugin.bundleIdentifier, tmuxPaneID: target["tmuxPaneID"] as? String,
                                  processID: (target["processID"] as? NSNumber)?.int32Value, sourcePath: target["sourcePath"] as? String),
            timestamp: time, state: state, isChild: raw["isChild"] as? Bool ?? false)
    }
}
