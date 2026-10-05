import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    var enabledWorkEnds: Set<WorkEnd> {
        Set(pluginEntries.filter(\.enabled).compactMap { $0.plugin.workEnd })
    }
    var customPetAnchor: NSPoint {
        let anchor = skinStore?.selectedSkin.anchor
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
        case .claudeCode, .pi: bundle = nil
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
    func customPetClipDuration(clip: String) -> TimeInterval? {
        guard let animation = skinStore?.selectedSkin.clips[clip] else { return nil }
        return Double(animation.frames.count) / animation.fps
    }
    func customPetImage(clip: String, elapsed: TimeInterval) -> NSImage? {
        guard let clip = PetSkinClip(rawValue: clip), let skinStore else { return nil }
        return skinStore.image(for: skinStore.selectedSkin.id, clip: clip, elapsed: elapsed)
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
            pluginEntries = next
            agentIconCache.removeAll()
            for end in old.subtracting(enabledWorkEnds) { router.remove(workEnd: end) }
            platform?.configure(plugins: next.filter(\.enabled).map(\.plugin))
            if let anchor = router.snapshot.hold?.anchor,
               anchor.accuracy == .exact && platform?.isAnchorValid(anchor) == false {
                router.endHold()
            }
            observationGeneration.configure(enabled: enabledWorkEnds, at: Date())
            let configuration = observationGeneration
            Task { await worker?.configure(configuration) }
            publish()
        } catch { setupMessage = localized("插件未重新加载：\(error)", "Could not reload plugins: \(error)") }
    }
    func setPlugin(_ id: String, enabled: Bool) {
        do { try pluginStore?.setEnabled(enabled, for: id); reloadPlugins() }
        catch { setupMessage = localized("无法修改插件：\(error)", "Could not update plugin: \(error)") }
    }
    func deletePlugin(_ id: String) {
        do { try pluginStore?.remove(id: id); reloadPlugins() }
        catch { setupMessage = localized("无法删除插件：\(error)", "Could not delete plugin: \(error)") }
    }
    func restorePlugins() {
        do { try pluginStore?.restoreBuiltIns(); reloadPlugins() }
        catch { setupMessage = localized("无法恢复插件：\(error)", "Could not restore plugins: \(error)") }
    }
    func importPlugin() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.title = localized("导入 .charintegration 插件目录", "Import .charintegration package")
        if picker.runModal() == .OK, let url = picker.url {
            do { try pluginStore?.importPackage(at: url); reloadPlugins() }
            catch { setupMessage = localized("导入失败：\(error)", "Import failed: \(error)") }
        }
    }
    func importSkin() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.title = localized("导入 .charpet 形象目录", "Import .charpet package")
        if picker.runModal() == .OK, let url = picker.url {
            do {
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
        panel?.surface.refresh()
    }
}
