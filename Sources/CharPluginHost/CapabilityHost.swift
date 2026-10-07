import Foundation
import CharCore

public enum PluginReadiness: String, Codable, Sendable { case ready, notInstalled, reloadRequired, unavailable }
public struct PluginHealth: Equatable, Sendable {
    public var status: PluginReadiness
    public var detail: String
    public init(status: PluginReadiness, detail: String = "") { self.status = status; self.detail = detail }
}

/// Persistent monitoring/origin processes; lifecycle-only adapters run on demand.
@MainActor public final class CapabilityHost {
    public private(set) var health: [String: PluginHealth] = [:]
    private var processes: [String: AdapterProcess] = [:]
    private var transient: [String: AdapterProcess] = [:]
    private var connecting: [String: Task<AdapterProcess, Error>] = [:]
    private var entries: [String: IntegrationPluginEntry] = [:]
    private let environment: [String: String]
    private var generation = 0
    public init(environment: [String: String]) { self.environment = environment }
    public func configure(_ candidates: [IntegrationPluginEntry]) async {
        generation += 1; let revision = generation
        let enabled = Dictionary(uniqueKeysWithValues: candidates.filter { $0.enabled && $0.plugin.adapter != nil }.map { ($0.id, $0) })
        for id in Set(entries.keys).union(processes.keys) where enabled[id]?.plugin != entries[id]?.plugin || enabled[id]?.packageURL != entries[id]?.packageURL {
            connecting.removeValue(forKey: id)?.cancel(); processes.removeValue(forKey: id)?.stop(); health.removeValue(forKey: id)
        }
        entries = enabled
        for entry in enabled.values where processes[entry.id] == nil {
            do {
                let inspected = try await inspect(entry.id)
                guard revision == generation else { return }
                if entry.plugin.adapter?.capabilities.contains(.monitor) == true, inspected.status == .ready {
                    _ = try await request(entry.id, method: "start")
                }
            } catch { if revision == generation { health[entry.id] = PluginHealth(status: .unavailable, detail: String(describing: error)) } }
        }
    }

    private func connect(_ id: String) async throws -> AdapterProcess {
        if let task = connecting[id] { return try await task.value }
        if let process = processes[id] {
            if process.isRunning { return process }
            processes.removeValue(forKey: id)?.stop()
        }
        guard let entry = entries[id], let descriptor = entry.plugin.adapter, let directory = entry.packageURL else { throw AdapterFailure.unavailable("Plugin is disabled or removed") }
        var env = environment
        env["CHAR_PLUGIN_ID"] = id; env["CHAR_PLUGIN_VERSION"] = entry.plugin.version ?? "1"
        env["CHAR_WORK_END"] = entry.plugin.workEnd?.rawValue ?? ""
        env["CHAR_PLUGIN_DIRECTORY"] = directory.path
        env["CHAR_PLUGIN_CONFIG"] = String(data: try JSONSerialization.data(withJSONObject: descriptor.configuration ?? [:]), encoding: .utf8)
        let process = try AdapterProcess(plugin: entry.plugin, descriptor: descriptor, packageURL: directory, environment: env)
        processes[id] = process
        let task = Task { @MainActor [weak self] () throws -> AdapterProcess in
            do {
                let hello = try await process.request("hello")
                guard hello["protocolVersion"] as? Int == 1 else { throw AdapterFailure.unavailable("Adapter protocol version mismatch") }
                let result = try await process.request("inspect")
                guard let raw = result["status"] as? String, let status = PluginReadiness(rawValue: raw) else { throw AdapterFailure.unavailable("Invalid inspect response") }
                guard self?.processes[id]?.instanceID == process.instanceID, !Task.isCancelled else { throw AdapterFailure.unavailable("Plugin configuration changed") }
                self?.health[id] = PluginHealth(status: status, detail: result["detail"] as? String ?? "")
                return process
            } catch { process.stop(); if self?.processes[id]?.instanceID == process.instanceID { self?.processes.removeValue(forKey: id) }; throw error }
        }
        connecting[id] = task
        do { let result = try await task.value; if processes[id]?.instanceID == process.instanceID { connecting.removeValue(forKey: id) }; return result }
        catch { if processes[id] == nil || processes[id]?.instanceID == process.instanceID { connecting.removeValue(forKey: id) }; throw error }
    }
    public func request(_ id: String, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        let required: PluginCapability?
        switch method {
        case "hello", "inspect": required = nil
        case "start", "stop": required = .monitor
        case "visit": required = .visit
        case "capture", "check", "focus", "release": required = .origin
        case "install", "update", "uninstall": required = .lifecycle
        default: throw AdapterFailure.unavailable("Unknown plugin method")
        }
        guard let entry = entries[id], required == nil || entry.plugin.adapter?.capabilities.contains(required!) == true else { throw AdapterFailure.unavailable("Plugin capability is unavailable") }
        let process = try await connect(id)
        let persistent = entry.plugin.adapter?.capabilities.contains(.monitor) == true || entry.plugin.adapter?.capabilities.contains(.origin) == true
        defer { if !persistent, processes[id]?.instanceID == process.instanceID { processes.removeValue(forKey: id)?.stop() } }
        let result = try await process.request(method, params: params, timeout: required == .lifecycle ? 15 : 3)
        guard processes[id]?.instanceID == process.instanceID, entries[id]?.plugin == entry.plugin,
              entries[id]?.packageURL == entry.packageURL else { throw AdapterFailure.unavailable("Plugin changed during request") }
        return result
    }
    @discardableResult public func inspect(_ id: String) async throws -> PluginHealth {
        let result = try await request(id, method: "inspect")
        guard let raw = result["status"] as? String, let status = PluginReadiness(rawValue: raw) else { throw AdapterFailure.unavailable("Invalid inspect response") }
        let value = PluginHealth(status: status, detail: result["detail"] as? String ?? "")
        health[id] = value; return value
    }
    public func drainEvents() -> [ObservationEvent] {
        for (id, process) in processes where !process.isRunning { health[id] = PluginHealth(status: .unavailable, detail: "Adapter exited") }
        return processes.values.flatMap { $0.drainEvents() }
    }
    public func recordHealth(_ id: String, value: PluginHealth) { health[id] = value }
    public func instanceID(_ id: String) -> String? { processes[id]?.instanceID }
    public func lifecycle(_ entry: IntegrationPluginEntry, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard ["install", "update", "uninstall", "inspect"].contains(method), let descriptor = entry.plugin.adapter,
              descriptor.capabilities.contains(.lifecycle), let directory = entry.packageURL else { throw AdapterFailure.unavailable("Lifecycle capability is unavailable") }
        if entries[entry.id] != nil { return try await request(entry.id, method: method, params: params) }
        var env = environment
        env["CHAR_PLUGIN_ID"] = entry.id; env["CHAR_PLUGIN_VERSION"] = entry.plugin.version ?? "1"; env["CHAR_PLUGIN_DIRECTORY"] = directory.path
        env["CHAR_WORK_END"] = entry.plugin.workEnd?.rawValue ?? ""
        env["CHAR_PLUGIN_CONFIG"] = String(data: try JSONSerialization.data(withJSONObject: descriptor.configuration ?? [:]), encoding: .utf8)
        let process = try AdapterProcess(plugin: entry.plugin, descriptor: descriptor, packageURL: directory, environment: env)
        transient[process.instanceID] = process
        defer { transient.removeValue(forKey: process.instanceID); process.stop() }
        let hello = try await process.request("hello")
        guard hello["protocolVersion"] as? Int == 1 else { throw AdapterFailure.unavailable("Adapter protocol version mismatch") }
        return try await process.request(method, params: params, timeout: 15)
    }
    public var runningProcessIDs: [Int32] { (Array(processes.values) + Array(transient.values)).filter(\.isRunning).map(\.processID) }
    public var runningPluginProcesses: [String: Int32] { processes.filter { $0.value.isRunning }.mapValues(\.processID) }
    public func stopAll() {
        generation += 1; connecting.values.forEach { $0.cancel() }; connecting.removeAll()
        processes.values.forEach { $0.stop() }; processes.removeAll(); entries.removeAll()
        transient.values.forEach { $0.stop() }; transient.removeAll()
    }
}
