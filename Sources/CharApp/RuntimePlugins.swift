import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    private static let defaultSoftwareIcon = Bundle.main.resourceURL
        .flatMap { NSImage(contentsOf: $0.appendingPathComponent("Icons/Char.png")) } ?? PetIconArtwork.rightEdgeIcon()
    var softwareIcon: NSImage { skinStore?.icon(for: selectedSkinID) ?? Self.defaultSoftwareIcon }
    var enabledWorkEnds: Set<WorkEnd> {
        Set(pluginEntries.filter(\.enabled).compactMap { $0.plugin.workEnd })
    }
    var customPetAnchor: NSPoint { customPetAnchor(for: petPlacement) }
    func customPetAnchor(for placement: PetPlacement) -> NSPoint {
        let anchor = appearancePose(for: placement)?.anchor
        return NSPoint(x: anchor?.x ?? 0.5, y: 1 - (anchor?.y ?? 0.5))
    }
    var customPetSize: NSSize {
        guard let size = skinStore?.selectedSkin.canvasSize else { return NSSize(width: petSize, height: petSize) }
        let scale = petSize / Double(max(size.width, size.height))
        return NSSize(width: Double(size.width)*scale, height: Double(size.height)*scale)
    }
    func agentIcon(for end: WorkEnd) -> NSImage? {
        if let image = agentIconCache[end] { return image }
        let image = loadAgentIcon(for: end)
        agentIconCache[end] = image
        return image
    }
    private func loadAgentIcon(for end: WorkEnd) -> NSImage? {
        guard let entry = pluginEntries.first(where: { $0.enabled && $0.plugin.workEnd == end }) else { return nil }
        if let url = pluginStore?.iconURL(for: entry.id), let image = NSImage(contentsOf: url) { return image }
        if end == .pi, let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/pi.png"),
           let image = NSImage(contentsOf: url) { return image }
        // CLI clients retain their own identity, regardless of which terminal hosts them.
        let bundle: String?
        switch end {
        case .codexCLI, .codexDesktop: bundle = MacOSPlatform.codexBundleID
        case .kimiCLI, .kimiDesktop: bundle = MacOSPlatform.kimiBundleID
        case .deepseekDesktop: bundle = MacOSPlatform.deepseekBundleID
        default: bundle = entry.plugin.bundleIdentifier
        }
        if let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.white.setFill()
            if end == .claudeCode {
                let center = NSPoint(x: 32, y: 32)
                for i in 0..<12 {
                    let angle = CGFloat(i) * .pi / 6
                    let line = NSBezierPath(); line.lineWidth = 5; line.lineCapStyle = .round
                    line.move(to: NSPoint(x: center.x + cos(angle)*10, y: center.y + sin(angle)*10))
                    line.line(to: NSPoint(x: center.x + cos(angle)*23, y: center.y + sin(angle)*23))
                    NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setStroke(); line.stroke()
                }
            } else {
                let label = end == .pi ? "π" : end == .deepseekDesktop ? "D" : end == .kimiCLI || end == .kimiDesktop ? "K" : "C"
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 43, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1)]
                let size = label.size(withAttributes: attrs)
                label.draw(at: NSPoint(x: (rect.width-size.width)/2,y: (rect.height-size.height)/2), withAttributes: attrs)
            }
            return true
        }
    }
    func customPetClipDuration(clip: String, placement: PetPlacement? = nil) -> TimeInterval? {
        guard let animation = appearancePose(for: placement ?? petPlacement)?.clips[clip] else { return nil }
        return Double(animation.frames.count) / animation.fps
    }
    func customPetImage(clip: String, elapsed: TimeInterval, placement: PetPlacement? = nil) -> NSImage? {
        guard let skinStore else { return nil }
        return skinStore.image(clip: clip,elapsed: elapsed,placement: (placement ?? petPlacement).rawValue)
    }
    func reloadPlugins() {
        do {
            guard let pluginStore else { return }
            let registry = pluginStore.directory.appendingPathComponent("registry.json")
            let revision = try registry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard revision != pluginRegistryRevision else { return }
            try pluginStore.reload()
            pluginRegistryRevision = revision
            let next = pluginStore.entries
            guard next != pluginEntries else { return }
            let old = enabledWorkEnds
            let replaced = Set(next.compactMap { entry -> WorkEnd? in
                guard entry.enabled, let previous = pluginEntries.first(where: { $0.id == entry.id }),
                      previous.plugin != entry.plugin || previous.packageURL != entry.packageURL else { return nil }
                return entry.plugin.workEnd
            })
            pluginEntries = next
            agentIconCache.removeAll()
            for end in old.subtracting(enabledWorkEnds).union(replaced) { router.remove(workEnd: end) }
            platform?.configure(plugins: next.filter(\.enabled).map(\.plugin))
            if let anchor = router.snapshot.hold?.anchor,
               anchor.accuracy == .exact && capabilityOrigins[anchor.id] == nil && platform?.isAnchorValid(anchor) == false {
                router.endHold()
            }
            if !replaced.isEmpty { observationGeneration.configure(enabled: enabledWorkEnds.subtracting(replaced), at: Date()) }
            observationGeneration.configure(enabled: enabledWorkEnds, at: Date())
            let configuration = observationGeneration
            Task { await worker?.configure(configuration) }
            configureCapabilityHost()
            publish(forceRefresh: true)
        } catch { setupMessage = localized("插件未重新加载：\(error)", "Could not reload plugins: \(error)") }
    }
    func setPlugin(_ id: String, enabled: Bool) {
        do { try pluginStore?.setEnabled(enabled, for: id); reloadPlugins() }
        catch { setupMessage = localized("无法修改插件：\(error)", "Could not update plugin: \(error)") }
    }
    func deletePlugin(_ id: String, cleanIntegration: Bool = false) {
        if cleanIntegration {
            guard !busy, let entry = pluginEntries.first(where: { $0.id == id }), let host = capabilityHost else { return }
            busy = true
            Task {
                do {
                    let shared = [.kimiCLI, .kimiDesktop].contains(entry.plugin.workEnd) && pluginEntries.contains {
                        $0.id != id && $0.enabled && [.kimiCLI, .kimiDesktop].contains($0.plugin.workEnd)
                    }
                    _ = try await host.lifecycle(effectiveCapabilityEntry(entry), method: "uninstall", params: ["retainSharedIntegration": shared])
                    try pluginStore?.remove(id: id); reloadPlugins()
                } catch { setupMessage = localized("无法卸载插件：\(error)", "Could not uninstall plugin: \(error)") }
                busy = false
            }
        } else {
            do { try pluginStore?.remove(id: id); reloadPlugins() }
            catch { setupMessage = localized("无法删除插件：\(error)", "Could not delete plugin: \(error)") }
        }
    }
    func restorePlugins() {
        do { try pluginStore?.restoreBuiltIns(); reloadPlugins() }
        catch { setupMessage = localized("无法恢复插件：\(error)", "Could not restore plugins: \(error)") }
    }
    func importPlugin() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.title = localized("导入 .charintegration 插件目录", "Import .charintegration package")
        picker.prompt = localized("导入", "Import")
        if picker.runModal() == .OK, let url = picker.url {
            do {
                let manifest = try JSONDecoder().decode(IntegrationPlugin.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
                if manifest.adapter != nil {
                    let alert = NSAlert()
                    alert.messageText = localized("运行能力插件？", "Run capability plugin?")
                    alert.informativeText = localized("\(manifest.name) 会以当前用户权限运行进程。请只导入可信代码。", "\(manifest.name) runs a process with your user permissions. Import trusted code only.")
                    alert.addButton(withTitle: localized("导入", "Import")); alert.addButton(withTitle: localized("取消", "Cancel"))
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                try pluginStore?.importPackage(at: url, replacingExisting: true); reloadPlugins()
            }
            catch { setupMessage = localized("导入失败：\(error)", "Import failed: \(error)") }
        }
    }
    func importSkin() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.title = localized("导入 .charpet 形象目录", "Import .charpet package")
        picker.prompt = localized("导入", "Import")
        if picker.runModal() == .OK, let url = picker.url {
            do {
                let manifest = try PetSkinStore.validatePackage(at: url)
                if manifest.features?.script != nil {
                    let alert = NSAlert(); alert.messageText = localized("启用形象脚本？", "Enable appearance script?")
                    alert.informativeText = localized("脚本仅能调用 Char 的事件与动作接口。", "Scripts can use only Char events and actions.")
                    alert.addButton(withTitle: localized("导入", "Import")); alert.addButton(withTitle: localized("取消", "Cancel"))
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                if let skin = try skinStore?.importPackage(at: url) { try skinStore?.select(id: skin.id) }
                refreshSkins()
            } catch { setupMessage = localized("形象导入失败：\(error)", "Appearance import failed: \(error)") }
        }
    }
    func selectSkin(_ id: String) {
        do { try skinStore?.select(id: id); refreshSkins() }
        catch { setupMessage = localized("无法选择形象：\(error)", "Could not select appearance: \(error)") }
    }
    func deleteSkin(_ id: String) {
        do { try skinStore?.delete(id: id); refreshSkins() }
        catch { setupMessage = localized("无法删除形象：\(error)", "Could not delete appearance: \(error)") }
    }
    func refreshSkins() {
        skins = skinStore?.skins ?? []
        selectedSkinID = skinStore?.selectedSkin.id ?? "char.default"
        selectedThemeID = skinStore?.selectedTheme ?? ""
        if panel != nil && loadedAppearanceID != selectedSkinID {
            loadedAppearanceID = selectedSkinID; prepareAppearance()
        } else if panel != nil { scheduleInstalledIcon() }
        NSApp.applicationIconImage = softwareIcon
        panel?.surface.refresh()
        refreshAppearanceStatusBar()
    }
}
