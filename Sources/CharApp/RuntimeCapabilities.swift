import AppKit
import CharCore
import CharPluginHost
import CharPlatform

struct CapabilityOrigin {
    let pluginID: String
    let instanceID: String
    let processID: Int32
    let token: String
}

extension CompanionRuntime {
    func effectiveCapabilityEntry(_ entry: IntegrationPluginEntry) -> IntegrationPluginEntry {
        guard entry.plugin.adapter == nil, let root = nativeRuntimeURL,
              let end = entry.plugin.workEnd, [.pi, .kimiCLI, .kimiDesktop, .deepseekDesktop].contains(end) else { return entry }
        var plugin = entry.plugin
        plugin.schemaVersion = 3; plugin.version = "1"
        plugin.adapter = AdapterDescriptor(runtime: .node, entrypoint: "native/adapter.mjs", capabilities: [.lifecycle])
        return IntegrationPluginEntry(plugin: plugin, enabled: entry.enabled, packageURL: root, isBuiltIn: entry.isBuiltIn)
    }
    func initializeCapabilityHost() {
        do {
            let support = store.fileURL.deletingLastPathComponent()
            var environment = try StableNativeDeployment.prepare(bundle: Bundle.main.bundleURL, support: support)
            if demo {
                let home = support.appendingPathComponent("fixture-home")
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                environment["HOME"] = home.path; environment.removeValue(forKey: "KIMI_CODE_HOME")
                environment["CHAR_HOOK_EVENTS"] = support.appendingPathComponent("harness-hooks.jsonl").resolvingSymlinksInPath().path
            }
            nativeRuntimeURL = environment["CHAR_NATIVE_ROOT"].map { URL(fileURLWithPath: $0) }
            capabilityHost = CapabilityHost(environment: environment)
            configureCapabilityHost()
        } catch { setupSection = "plugins"; setupMessage = localized("插件宿主无法初始化：\(error)", "Could not initialize plugin host: \(error)") }
    }
    func configureCapabilityHost() {
        capabilityRevision += 1; let revision = capabilityRevision
        let entries = pluginEntries.map(effectiveCapabilityEntry)
        Task { [weak self] in
            guard let self, revision == self.capabilityRevision else { return }
            await self.capabilityHost?.configure(entries)
            guard revision == self.capabilityRevision else { return }
            self.refreshCapabilityHealth()
            if let anchor = self.router.snapshot.hold?.anchor, let origin = self.capabilityOrigins[anchor.id],
               self.capabilityHost?.instanceID(origin.pluginID) != origin.instanceID { self.router.invalidateAnchor(id: anchor.id); self.publish() }
        }
    }
    func refreshCapabilityHealth() {
        let next = capabilityHost?.health ?? [:]
        if next != pluginHealth { pluginHealth = next }
    }
    func pluginAction(_ id: String, method: String) {
        guard !busy, let entry = pluginEntries.first(where: { $0.id == id }), let host = capabilityHost else { return }
        busy = true
        Task {
            do {
                let effective = effectiveCapabilityEntry(entry)
                if method == "inspect", effective.plugin.adapter?.capabilities.contains(.lifecycle) != true {
                    _ = try await host.inspect(id)
                } else {
                    let shared = [.kimiCLI, .kimiDesktop].contains(effective.plugin.workEnd) && pluginEntries.contains {
                        $0.id != id && $0.enabled && [.kimiCLI, .kimiDesktop].contains($0.plugin.workEnd)
                    }
                    let result = try await host.lifecycle(effective, method: method, params: ["retainSharedIntegration": shared])
                    if let raw = result["status"] as? String, let status = PluginReadiness(rawValue: raw) {
                        host.recordHealth(id, value: PluginHealth(status: status, detail: result["detail"] as? String ?? "")); refreshCapabilityHealth()
                    }
                }
                if effective.plugin.adapter?.capabilities.contains(.monitor) == true {
                    if method == "install" || method == "update" {
                        let receipt = host.health[id]
                        let inspected = try await host.inspect(id)
                        if inspected.status == .ready { _ = try await host.request(id, method: "start") }
                        if let receipt { host.recordHealth(id, value: receipt) }
                    } else if method == "inspect", host.health[id]?.status == .ready { _ = try await host.request(id, method: "start") }
                    else if method == "uninstall" { _ = try await host.request(id, method: "stop") }
                }
                refreshCapabilityHealth()
            } catch { host.recordHealth(id, value: PluginHealth(status: .unavailable, detail: String(describing: error))); refreshCapabilityHealth() }
            busy = false
        }
    }
    func captureOrigin() async -> ReturnAnchor? {
        guard effectiveOriginPolicy != .disabled else { return nil }
        if let source = WorkspaceRuntime().foregroundApplication(), let anchor = await captureCapabilityOrigin(from: source) { return anchor }
        let anchor = platform?.captureSource()
        return anchor?.accuracy == .application && !settings.applicationOrigins ? nil : anchor
    }
    func captureCapabilityOrigin(from source: ForegroundSnapshot) async -> ReturnAnchor? {
        guard source.bundleIdentifier != Bundle.main.bundleIdentifier,
              let entry = pluginEntries.first(where: { $0.enabled && $0.plugin.bundleIdentifier == source.bundleIdentifier && $0.plugin.adapter?.capabilities.contains(.origin) == true }),
              let host = capabilityHost else { return nil }
        do {
            let result = try await host.request(entry.id, method: "capture", params: ["processID": Int(source.processID), "bundleIdentifier": source.bundleIdentifier])
            guard let token = result["token"] as? String, !token.isEmpty, token.count <= 4096,
                  (result["processID"] as? NSNumber)?.int32Value == source.processID,
                  let instance = host.instanceID(entry.id) else { return nil }
            let id = UUID().uuidString
            capabilityOrigins[id] = CapabilityOrigin(pluginID: entry.id, instanceID: instance, processID: source.processID, token: token)
            return ReturnAnchor(id: id, bundleIdentifier: source.bundleIdentifier, token: id, accuracy: .exact)
        } catch { return nil }
    }
    func originState(_ anchor: ReturnAnchor) async -> (valid: Bool?, active: Bool) {
        guard let origin = capabilityOrigins[anchor.id] else {
            return (platform?.isAnchorValid(anchor), platform?.focusContext(for: anchor).sourceAnchorID == anchor.id)
        }
        guard let host = capabilityHost, host.instanceID(origin.pluginID) == origin.instanceID,
              demo || WorkspaceRuntime().isRunning(bundleID: anchor.bundleIdentifier, processID: origin.processID) else { return (false, false) }
        do {
            let result = try await host.request(origin.pluginID, method: "check", params: ["token": origin.token, "processID": Int(origin.processID)])
            let foreground = WorkspaceRuntime().foregroundApplication()
            return (result["valid"] as? Bool, result["active"] as? Bool == true && (demo || foreground?.processID == origin.processID))
        } catch { return (nil, false) }
    }
    func visitCapability(_ end: WorkEnd, target: SessionTarget) async -> NavigationOutcome {
        guard let entry = pluginEntries.first(where: { $0.enabled && $0.plugin.workEnd == end && $0.plugin.adapter?.capabilities.contains(.visit) == true }),
              let host = capabilityHost else { return await platform?.activate(workEnd: end, target: target) ?? .fallback }
        do {
            var params: [String: Any] = ["nativeID": router.nextVisit(for: end)?.key.nativeID ?? "", "bundleIdentifier": entry.plugin.bundleIdentifier]
            if let pid = target.processID { params["processID"] = Int(pid) }
            if let pane = target.tmuxPaneID { params["tmuxPaneID"] = pane }
            if let path = target.sourcePath { params["sourcePath"] = path }
            let result = try await host.request(entry.id, method: "visit", params: params)
            guard let raw = result["outcome"] as? String, let outcome = NavigationOutcome(rawValue: raw),
                  outcome != .exact || result["verified"] as? Bool == true else { return .unavailable }
            if !demo, outcome != .unavailable, WorkspaceRuntime().foregroundApplication()?.bundleIdentifier != entry.plugin.bundleIdentifier { return .unavailable }
            return outcome
        } catch { return .unavailable }
    }
    func returnToOrigin(_ anchor: ReturnAnchor) async -> NavigationOutcome {
        guard let origin = capabilityOrigins[anchor.id], let host = capabilityHost else { return await platform?.returnToSource(anchor) ?? (anchor.accuracy == .application ? .fallback : .exact) }
        guard (await originState(anchor)).valid == true else { return .unavailable }
        if !demo, !(await WorkspaceRuntime().activate(bundleID: anchor.bundleIdentifier, preferredProcessID: origin.processID)) { return .unavailable }
        do {
            let result = try await host.request(origin.pluginID, method: "focus", params: ["token": origin.token, "processID": Int(origin.processID)])
            guard let raw = result["outcome"] as? String, let outcome = NavigationOutcome(rawValue: raw) else { return .unavailable }
            if outcome == .exact { return (await originState(anchor)).active ? .exact : .unavailable }
            return outcome
        } catch { return .unavailable }
    }
    func releaseOrigin(_ anchor: ReturnAnchor) {
        if let origin = capabilityOrigins.removeValue(forKey: anchor.id) {
            Task {
                guard capabilityHost?.instanceID(origin.pluginID) == origin.instanceID else { return }
                _ = try? await capabilityHost?.request(origin.pluginID, method: "release", params: ["token": origin.token])
            }
        } else { platform?.release(anchor) }
    }
}
