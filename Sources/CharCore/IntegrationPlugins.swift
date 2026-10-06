import Foundation
import ImageIO

/// Legacy configuration or a versioned process adapter with declared capabilities.
public struct IntegrationPlugin: Codable, Identifiable, Equatable, Sendable {
    public enum ReturnAdapter: String, Codable, Sendable { case tabbit, vscode, application }
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var workEnd: WorkEnd?
    public var bundleIdentifier: String
    public var returnAdapter: ReturnAdapter?
    public var icon: String?
    public var version: String?
    public var clientInterface: ClientInterface?
    public var adapter: AdapterDescriptor?

    public init(schemaVersion: Int = 2, id: String, name: String,
                workEnd: WorkEnd? = nil, bundleIdentifier: String,
                returnAdapter: ReturnAdapter? = nil, icon: String? = nil,
                version: String? = nil, clientInterface: ClientInterface? = nil, adapter: AdapterDescriptor? = nil) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.workEnd = workEnd; self.bundleIdentifier = bundleIdentifier
        self.returnAdapter = returnAdapter; self.icon = icon
        self.version = version; self.clientInterface = clientInterface; self.adapter = adapter
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, workEnd, bundleIdentifier, returnAdapter, icon, version, clientInterface, adapter
        case kind, sourceAdapter // Version 1 compatibility only; never encoded.
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...3).contains(version) else {
            throw IntegrationPluginError.invalid("manifest version")
        }
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        workEnd = try c.decodeIfPresent(WorkEnd.self, forKey: .workEnd)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        if version == 1 {
            let kind = try c.decode(String.self, forKey: .kind)
            returnAdapter = try c.decodeIfPresent(ReturnAdapter.self, forKey: .sourceAdapter)
            guard (kind == "agent" && workEnd != nil && returnAdapter == nil) ||
                    (kind == "source" && workEnd == nil && returnAdapter != nil) else {
                throw IntegrationPluginError.invalid("legacy adapter fields")
            }
        } else {
            returnAdapter = try c.decodeIfPresent(ReturnAdapter.self, forKey: .returnAdapter)
        }
        self.version = try c.decodeIfPresent(String.self, forKey: .version)
        clientInterface = try c.decodeIfPresent(ClientInterface.self, forKey: .clientInterface)
        adapter = try c.decodeIfPresent(AdapterDescriptor.self, forKey: .adapter)
        guard version == 3 || adapter == nil else { throw IntegrationPluginError.invalid("adapter requires manifest v3") }
        schemaVersion = version == 3 ? 3 : 2
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encodeIfPresent(workEnd, forKey: .workEnd)
        try c.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try c.encodeIfPresent(returnAdapter, forKey: .returnAdapter)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(clientInterface, forKey: .clientInterface)
        try c.encodeIfPresent(adapter, forKey: .adapter)
    }

}

public struct IntegrationPluginEntry: Identifiable, Equatable, Sendable {
    public var id: String { plugin.id }
    public let plugin: IntegrationPlugin
    public let enabled: Bool
    public let packageURL: URL?
    public let isBuiltIn: Bool
    public init(plugin: IntegrationPlugin, enabled: Bool, packageURL: URL?, isBuiltIn: Bool) {
        self.plugin = plugin; self.enabled = enabled; self.packageURL = packageURL; self.isBuiltIn = isBuiltIn
    }
}

public enum IntegrationPluginError: Error, Equatable, CustomStringConvertible {
    case invalid(String), duplicateID(String), duplicateWorkEnd(WorkEnd), notFound(String)
    public var description: String {
        switch self {
        case .invalid(let detail): return "Invalid integration plugin: \(detail)"
        case .duplicateID(let id): return "Plugin ID already installed: \(id)"
        case .duplicateWorkEnd(let end): return "An enabled plugin already uses \(end.rawValue)"
        case .notFound(let id): return "Plugin not installed: \(id)"
        }
    }
}

/// Reload on a directory change (or polling tick). Every mutation replaces one atomic registry.
/// Package directories are validated and copied before the registry becomes visible.
public final class IntegrationPluginStore {
    public let directory: URL
    public private(set) var entries: [IntegrationPluginEntry] = []
    private struct Record: Codable {
        var plugin: IntegrationPlugin
        var enabled: Bool
        var packageName: String?
        var isBuiltIn: Bool
    }
    private struct Registry: Codable {
        var schemaVersion = 2
        var records: [Record]
        var tombstones: Set<String> = []
    }
    private var registry = Registry(records: [])
    private let fm = FileManager.default
    private var registryURL: URL { directory.appendingPathComponent("registry.json") }
    private var packagesURL: URL { directory.appendingPathComponent("packages", isDirectory: true) }

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        try fm.createDirectory(at: packagesURL, withIntermediateDirectories: true)
        if fm.fileExists(atPath: registryURL.path) { try reload() }
        else {
            try commit(Registry(records: Self.builtIns.map { Record(plugin: $0, enabled: true, isBuiltIn: true) }))
        }
    }

    public func reload() throws {
        let candidate = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: registryURL))
        guard (1...3).contains(candidate.schemaVersion) else { throw IntegrationPluginError.invalid("registry version") }
        try validate(candidate)
        registry = candidate
        publish()
    }

    @discardableResult public func importPackage(at url: URL, replacingExisting: Bool = false) throws -> IntegrationPluginEntry {
        try reload()
        let plugin = try loadPackage(url)
        let old = registry.records.first { $0.plugin.id == plugin.id }
        guard replacingExisting || old == nil else {
            throw IntegrationPluginError.duplicateID(plugin.id)
        }
        var candidate = registry
        candidate.records.removeAll { $0.plugin.id == plugin.id }
        let packageName = UUID().uuidString + ".charintegration"
        candidate.records.append(Record(plugin: plugin, enabled: old?.enabled ?? true, packageName: packageName, isBuiltIn: false))
        candidate.tombstones.remove(plugin.id)
        // Check conflicts before copying anything into the installed catalog.
        try validateRecords(candidate)
        let destination = packagesURL.appendingPathComponent(packageName, isDirectory: true)
        do {
            try fm.copyItem(at: url, to: destination)
            _ = try loadPackage(destination)
            try commit(candidate)
            if let previous = old?.packageName { try? fm.removeItem(at: packagesURL.appendingPathComponent(previous)) }
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        return entries.first { $0.id == plugin.id }!
    }

    public func setEnabled(_ enabled: Bool, for id: String) throws {
        try reload()
        var candidate = registry
        guard let index = candidate.records.firstIndex(where: { $0.plugin.id == id }) else {
            throw IntegrationPluginError.notFound(id)
        }
        candidate.records[index].enabled = enabled
        try commit(candidate)
    }

    public func remove(id: String) throws {
        try reload()
        var candidate = registry
        guard let index = candidate.records.firstIndex(where: { $0.plugin.id == id }) else {
            throw IntegrationPluginError.notFound(id)
        }
        let removed = candidate.records.remove(at: index)
        if removed.isBuiltIn { candidate.tombstones.insert(id) }
        try commit(candidate)
        if let package = removed.packageName { try? fm.removeItem(at: packagesURL.appendingPathComponent(package)) }
    }

    public func restoreBuiltIns() throws {
        try reload()
        var candidate = registry
        for plugin in Self.builtIns where !candidate.records.contains(where: { $0.plugin.id == plugin.id }) {
            // Restore without overriding a user's replacement for the same adapter.
            let enabled = !candidate.records.contains {
                $0.enabled && (plugin.workEnd != nil && $0.plugin.workEnd == plugin.workEnd ||
                    plugin.returnAdapter != nil && plugin.returnAdapter != .application &&
                    ($0.plugin.returnAdapter != nil && $0.plugin.returnAdapter != .application || $0.plugin.adapter?.capabilities.contains(.origin) == true) &&
                    $0.plugin.bundleIdentifier == plugin.bundleIdentifier)
            }
            candidate.records.append(Record(plugin: plugin, enabled: enabled, isBuiltIn: true))
            candidate.tombstones.remove(plugin.id)
        }
        try commit(candidate)
    }

    public func iconURL(for id: String) -> URL? {
        guard let entry = entries.first(where: { $0.id == id }), let package = entry.packageURL,
              let icon = entry.plugin.icon else { return nil }
        return package.appendingPathComponent(icon)
    }

    private func publish() {
        entries = registry.records.map {
            IntegrationPluginEntry(plugin: $0.plugin, enabled: $0.enabled,
                packageURL: $0.packageName.map { packagesURL.appendingPathComponent($0, isDirectory: true) },
                isBuiltIn: $0.isBuiltIn)
        }
    }

    private func commit(_ candidate: Registry) throws {
        try validate(candidate)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var migrated = candidate; migrated.schemaVersion = 3
        try encoder.encode(migrated).write(to: registryURL, options: .atomic)
        registry = migrated
        publish()
    }

    private func validateRecords(_ candidate: Registry) throws {
        var ids = Set<String>(); var enabledEnds = Set<WorkEnd>(); var enabledPreciseBundles = Set<String>()
        for record in candidate.records {
            try validateManifest(record.plugin)
            guard ids.insert(record.plugin.id).inserted else { throw IntegrationPluginError.duplicateID(record.plugin.id) }
            if record.enabled, (record.plugin.returnAdapter != nil && record.plugin.returnAdapter != .application) || record.plugin.adapter?.capabilities.contains(.origin) == true {
                guard enabledPreciseBundles.insert(record.plugin.bundleIdentifier).inserted else {
                    throw IntegrationPluginError.invalid("an enabled precise return adapter already owns this application")
                }
            }
            if record.enabled, let end = record.plugin.workEnd {
                guard enabledEnds.insert(end).inserted else { throw IntegrationPluginError.duplicateWorkEnd(end) }
            }
        }
    }

    private func validate(_ candidate: Registry) throws {
        try validateRecords(candidate)
        for record in candidate.records {
            if let package = record.packageName {
                guard package == URL(fileURLWithPath: package).lastPathComponent,
                      !package.hasPrefix("."), !record.isBuiltIn else { throw IntegrationPluginError.invalid("package path") }
                let actual = try loadPackage(packagesURL.appendingPathComponent(package))
                guard actual == record.plugin else { throw IntegrationPluginError.invalid("manifest changed; reimport package") }
            } else if !record.isBuiltIn || !Self.builtIns.contains(record.plugin) {
                throw IntegrationPluginError.invalid("unpackaged plugin")
            }
        }
    }

    private func validateManifest(_ plugin: IntegrationPlugin) throws {
        let idPattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
        let bundlePattern = "^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$"
        guard [2, 3].contains(plugin.schemaVersion),
              plugin.id.range(of: idPattern, options: .regularExpression) != nil,
              !plugin.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plugin.name.count <= 100,
              plugin.bundleIdentifier.range(of: bundlePattern, options: .regularExpression) != nil else {
            throw IntegrationPluginError.invalid("version, ID, name or bundle identifier")
        }
        if plugin.returnAdapter == .tabbit && plugin.bundleIdentifier != "com.tabbit-ai.Tabbit" {
            throw IntegrationPluginError.invalid("Tabbit adapter requires Tabbit bundle identifier")
        }
        if plugin.returnAdapter == .vscode && plugin.bundleIdentifier != "com.microsoft.VSCode" {
            throw IntegrationPluginError.invalid("VS Code adapter requires VS Code bundle identifier")
        }
        guard plugin.workEnd != nil || plugin.returnAdapter != nil || plugin.adapter != nil else {
            throw IntegrationPluginError.invalid("at least one integration capability is required")
        }
        if let end = plugin.workEnd, !WorkEnd.allCases.contains(end), plugin.adapter?.capabilities.contains(.monitor) != true {
            throw IntegrationPluginError.invalid("custom workEnd requires a v3 monitoring adapter")
        }
        if let adapter = plugin.adapter {
            guard plugin.schemaVersion == 3, adapter.protocolVersion == 1, !adapter.capabilities.isEmpty,
                  !adapter.entrypoint.isEmpty, !adapter.entrypoint.hasPrefix("/"),
                  adapter.entrypoint.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
                  !adapter.capabilities.contains(.monitor) || plugin.workEnd != nil else {
                throw IntegrationPluginError.invalid("adapter protocol, entrypoint or monitor identity")
            }
        }
        if let icon = plugin.icon {
            guard !icon.isEmpty, !icon.hasPrefix("/"), icon.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
                  icon.lowercased().hasSuffix(".png") else { throw IntegrationPluginError.invalid("relative PNG icon path") }
        }
    }

    private func loadPackage(_ url: URL) throws -> IntegrationPlugin {
        let root = url.standardizedFileURL
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw IntegrationPluginError.invalid("package directory") }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw IntegrationPluginError.invalid("unreadable package")
        }
        var bytes = 0
        for case let item as URL in enumerator {
            let metadata = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard metadata.isSymbolicLink != true else { throw IntegrationPluginError.invalid("symlinks are not allowed") }
            bytes += metadata.fileSize ?? 0
            guard bytes <= 8 * 1024 * 1024 else { throw IntegrationPluginError.invalid("package exceeds 8 MiB") }
        }
        let manifest = root.appendingPathComponent("manifest.json")
        let plugin = try JSONDecoder().decode(IntegrationPlugin.self, from: Data(contentsOf: manifest))
        try validateManifest(plugin)
        if let adapter = plugin.adapter {
            let executable = root.appendingPathComponent(adapter.entrypoint)
            guard (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  adapter.runtime != .executable || fm.isExecutableFile(atPath: executable.path) else {
                throw IntegrationPluginError.invalid("adapter entrypoint must be a regular readable file (executable for native runtime)")
            }
        }
        if let icon = plugin.icon {
            let asset = root.appendingPathComponent(icon).standardizedFileURL
            guard asset.path.hasPrefix(root.path + "/"),
                  let source = CGImageSourceCreateWithURL(asset as CFURL, nil),
                  CGImageSourceGetType(source) as String? == "public.png",
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width > 0, image.height > 0, image.width <= 2048, image.height <= 2048 else {
                throw IntegrationPluginError.invalid("icon must decode as a PNG at most 2048 × 2048")
            }
        }
        return plugin
    }

    public static let builtIns: [IntegrationPlugin] = [
        (.claudeCode, "Claude Code", "dev.warp.Warp-Stable"),
        (.codexCLI, "Codex CLI", "dev.warp.Warp-Stable"),
        (.codexDesktop, "Codex", "com.openai.codex"),
        (.deepseekDesktop, "DeepSeek Harness", "com.deepseek.dsh"),
        (.kimiCLI, "Kimi CLI", "dev.warp.Warp-Stable"),
        (.kimiDesktop, "Kimi Code", "com.kimi.code.desktop"),
        (.pi, "pi", "dev.warp.Warp-Stable")
    ].map { end, name, bundle in
        IntegrationPlugin(id: "builtin.agent.\(end.rawValue)", name: name, workEnd: end, bundleIdentifier: bundle)
    } + [
        IntegrationPlugin(id: "builtin.source.tabbit", name: "Tabbit", bundleIdentifier: "com.tabbit-ai.Tabbit", returnAdapter: .tabbit),
        IntegrationPlugin(id: "builtin.source.vscode", name: "VS Code", bundleIdentifier: "com.microsoft.VSCode", returnAdapter: .vscode),
        IntegrationPlugin(id: "builtin.source.wechat", name: "WeChat", bundleIdentifier: "com.tencent.xinWeChat", returnAdapter: .application)
    ]
}
