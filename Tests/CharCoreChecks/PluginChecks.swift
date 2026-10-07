import Foundation
import CharCore

struct PluginChecks {
    func testPersistenceAndHotReload() throws {
        let root = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try IntegrationPluginStore(directory: root)
        try checkEqual(store.entries.count, 10)
        let mirror = try IntegrationPluginStore(directory: root)
        let id = "builtin.agent.pi"
        try store.setEnabled(false, for: id)
        try mirror.reload()
        try checkEqual(mirror.entries.first { $0.id == id }?.enabled, false)
        try store.remove(id: id)
        let restarted = try IntegrationPluginStore(directory: root)
        try check(!restarted.entries.contains { $0.id == id }, "removed builtin resurrected")
        try restarted.restoreBuiltIns()
        try checkEqual(restarted.entries.count, 10)
        try checkEqual(restarted.entries.first { $0.id == id }?.enabled, true)
    }

    func testImportConflictsAndAtomicFailures() throws {
        let root = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("catalog")
        let package = root.appendingPathComponent("custom.charintegration")
        let store = try IntegrationPluginStore(directory: catalog)
        var plugin = IntegrationPlugin(id: "custom.pi", name: "My pi",
            workEnd: .pi, bundleIdentifier: "dev.warp.Warp-Stable")
        try writePackage(plugin, at: package)
        let before = try Data(contentsOf: catalog.appendingPathComponent("registry.json"))
        try expectFailure { _ = try store.importPackage(at: package) }
        try checkEqual(try Data(contentsOf: catalog.appendingPathComponent("registry.json")), before)
        try store.setEnabled(false, for: "builtin.agent.pi")
        let imported = try store.importPackage(at: package)
        try check(imported.enabled && !imported.isBuiltIn)
        try check(imported.packageURL != package, "package was not copied")
        try expectFailure { _ = try store.importPackage(at: package) }
        try expectFailure { try store.setEnabled(true, for: "builtin.agent.pi") }
        try checkEqual(store.entries.first { $0.id == "builtin.agent.pi" }?.enabled, false)
        try store.remove(id: plugin.id)
        try check(!FileManager.default.fileExists(atPath: imported.packageURL!.path))
        plugin.schemaVersion = 4
        try writePackage(plugin, at: package)
        let installedCount = store.entries.count
        try expectFailure { _ = try store.importPackage(at: package) }
        try checkEqual(store.entries.count, installedCount)
        plugin.schemaVersion = 3; plugin.bundleIdentifier = "invalid"
        try writePackage(plugin, at: package)
        try expectFailure { _ = try store.importPackage(at: package) }
        plugin.bundleIdentifier = "com.example.app"; plugin.workEnd = nil
        try writePackage(plugin, at: package)
        try expectFailure { _ = try store.importPackage(at: package) }
    }

    func testAssetsAndSymlinks() throws {
        let root = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("source.charintegration")
        let store = try IntegrationPluginStore(directory: root.appendingPathComponent("catalog"))
        var plugin = IntegrationPlugin(id: "custom.source", name: "Example",
            bundleIdentifier: "com.example.app", returnAdapter: .application, icon: "icon.png")
        try writePackage(plugin, at: package)
        // A real, lossless one-pixel PNG (decoded by the same loader used by the application).
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4WQAAAAASUVORK5CYII=")!
        try png.write(to: package.appendingPathComponent("icon.png"))
        let entry = try store.importPackage(at: package)
        try checkEqual(try Data(contentsOf: store.iconURL(for: entry.id)!), png)
        try store.remove(id: entry.id)
        plugin.icon = "../outside.png"
        try writePackage(plugin, at: package)
        try expectFailure { _ = try store.importPackage(at: package) }
        plugin.icon = "icon.png"
        try writePackage(plugin, at: package)
        try FileManager.default.removeItem(at: package.appendingPathComponent("icon.png"))
        let external = root.appendingPathComponent("outside.png"); try png.write(to: external)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("icon.png"), withDestinationURL: external)
        try expectFailure { _ = try store.importPackage(at: package) }
        try checkEqual(store.entries.count, 10)
    }

    func testCurrentFormatsAndUnifiedCapabilities() throws {
        let root = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try IntegrationPluginStore(directory: root)
        try store.setEnabled(false, for: "builtin.agent.pi")
        try store.remove(id: "builtin.source.wechat")
        let registryURL = root.appendingPathComponent("registry.json")
        var registry = try JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as! [String: Any]
        registry["schemaVersion"] = 3
        var records = registry["records"] as! [[String: Any]]
        for index in records.indices {
            var manifest = records[index]["plugin"] as! [String: Any]
            manifest["schemaVersion"] = 2
            records[index]["plugin"] = manifest
        }
        registry["records"] = records
        try JSONSerialization.data(withJSONObject: registry).write(to: registryURL)
        let migrated = try IntegrationPluginStore(directory: root)
        try checkEqual(migrated.entries.first { $0.id == "builtin.agent.pi" }?.enabled, false)
        try check(!migrated.entries.contains { $0.id == "builtin.source.wechat" })
        try migrated.setEnabled(true, for: "builtin.agent.pi")
        let upgraded = try JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as! [String: Any]
        try checkEqual(upgraded["schemaVersion"] as? Int, 3)
        try check((upgraded["tombstones"] as! [String]).contains("builtin.source.wechat"))
        for record in upgraded["records"] as! [[String: Any]] {
            try check((record["plugin"] as! [String: Any])["kind"] == nil)
        }
        let packageBefore = try Data(contentsOf: registryURL)
        for oldVersion in [1,2] {
            let unsupported = root.appendingPathComponent("unsupported.charintegration")
            let manifest = IntegrationPlugin(schemaVersion: oldVersion,id: "unsupported.app",name: "Unsupported",
                                             bundleIdentifier: "com.example.unsupported",returnAdapter: .application)
            try writePackage(manifest,at: unsupported)
            try expectFailure { _ = try migrated.importPackage(at: unsupported) }
            try checkEqual(try Data(contentsOf: registryURL),packageBefore)
        }
        try check(migrated.entries.allSatisfy { $0.plugin.schemaVersion == 3 })
        // Independent capabilities coexist on one record; observer conflicts remain enforced.
        try migrated.setEnabled(false, for: "builtin.agent.codexDesktop")
        let package = root.appendingPathComponent("combined.charintegration")
        let combined = IntegrationPlugin(id: "custom.combined", name: "Combined",
            workEnd: .codexDesktop, bundleIdentifier: "com.microsoft.VSCode", returnAdapter: .vscode)
        try writePackage(combined, at: package)
        try expectFailure { _ = try migrated.importPackage(at: package) }
        try migrated.setEnabled(false, for: "builtin.source.vscode")
        _ = try migrated.importPackage(at: package)
        try migrated.remove(id: "builtin.source.vscode")
        try migrated.restoreBuiltIns()
        try checkEqual(migrated.entries.first { $0.id == "builtin.source.vscode" }?.enabled, false)
        // Built-in CLI observers all share Warp without owning its generic return path.
        try checkEqual(migrated.entries.filter { $0.enabled && $0.plugin.bundleIdentifier == "dev.warp.Warp-Stable" }.count, 4)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("char-plugin-check-" + UUID().uuidString)
    }
    private func writePackage(_ plugin: IntegrationPlugin, at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONEncoder().encode(plugin).write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
    }
    private func expectFailure(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        try check(false, "invalid mutation succeeded")
    }
}
