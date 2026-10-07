import SwiftUI
import CharCore
import CharPluginHost

struct PluginSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @State private var deleteID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(runtime.pluginEntries) { entry in
                HStack {
                    Toggle(entry.plugin.name, isOn: Binding(get: { entry.enabled }, set: { runtime.setPlugin(entry.id, enabled: $0) }))
                    Spacer()
                    capabilityIcons(runtime.effectiveCapabilityEntry(entry).plugin)
                    if let health = runtime.pluginHealth[entry.id] {
                        Image(systemName: healthSymbol(health.status))
                            .foregroundStyle(health.status == .ready ? Color.green : Color.orange)
                            .help(healthLabel(health.status) + (health.detail.isEmpty ? "" : " · " + health.detail))
                            .accessibilityLabel(healthLabel(health.status))
                    }
                    if runtime.effectiveCapabilityEntry(entry).plugin.adapter != nil {
                        Menu {
                            Button(runtime.localized("自检", "Inspect")) { runtime.pluginAction(entry.id, method: "inspect") }
                            if runtime.effectiveCapabilityEntry(entry).plugin.adapter?.capabilities.contains(.lifecycle) == true {
                                Button(runtime.localized("安装", "Install")) { runtime.pluginAction(entry.id, method: "install") }
                                Button(runtime.localized("更新集成", "Update integration")) { runtime.pluginAction(entry.id, method: "update") }
                                Button(runtime.localized("移除客户端集成", "Remove client integration")) { runtime.pluginAction(entry.id, method: "uninstall") }
                            }
                        } label: { Image(systemName: "wrench.and.screwdriver") }.menuStyle(.borderlessButton).frame(width: 25)
                    }
                    Button { deleteID = entry.id } label: { Image(systemName: "trash") }
                        .accessibilityLabel(runtime.localized("删除 \(entry.plugin.name)", "Delete \(entry.plugin.name)"))
                }
            }
            HStack {
                Button(runtime.localized("导入插件…", "Import plugin…")) { runtime.importPlugin() }
                Button(runtime.localized("恢复已删除的内置插件", "Restore built-in plugins")) { runtime.restorePlugins() }
            }
        }
        .alert(runtime.localized("删除插件？", "Delete plugin?"), isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button(runtime.localized("取消", "Cancel"), role: .cancel) { deleteID = nil }
            if let id = deleteID, let entry = runtime.pluginEntries.first(where: { $0.id == id }),
               runtime.effectiveCapabilityEntry(entry).plugin.adapter?.capabilities.contains(.lifecycle) == true {
                Button(runtime.localized("卸载集成并删除", "Uninstall and delete"), role: .destructive) { runtime.deletePlugin(id, cleanIntegration: true); deleteID = nil }
            }
            Button(runtime.localized("仅删除插件", "Delete plugin only"), role: .destructive) { if let id = deleteID { runtime.deletePlugin(id) }; deleteID = nil }
        }
        .disabled(runtime.busy)
    }
    private func healthSymbol(_ status: PluginReadiness) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .notInstalled: return "arrow.down.circle"
        case .reloadRequired: return "arrow.clockwise.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }
    private func healthLabel(_ status: PluginReadiness) -> String {
        switch status {
        case .ready: return runtime.localized("配置可用", "Configuration ready")
        case .notInstalled: return runtime.localized("未安装或需要更新", "Not installed or update needed")
        case .reloadRequired: return runtime.localized("需要重载客户端", "Reload client")
        case .unavailable: return runtime.localized("不可用", "Unavailable")
        }
    }
    private func capabilityIcons(_ plugin: IntegrationPlugin) -> some View {
        HStack(spacing: 8) {
            if plugin.workEnd != nil {
                capabilityIcon("bell.fill", label: runtime.localized("提醒", "Notifications"))
            }
            if plugin.returnAdapter == .tabbit || plugin.returnAdapter == .vscode || plugin.adapter?.capabilities.contains(.origin) == true {
                capabilityIcon(NavigationPresentation.exactSymbol, label: runtime.localized("准确回城能力，需要可用集成及授权", "Exact return (requires integration and permission)"))
            } else {
                capabilityIcon(NavigationPresentation.applicationSymbol, label: runtime.localized("应用级回城", "Application return"))
            }
        }
        .frame(width: 48, alignment: .trailing)
        .foregroundStyle(.secondary)
    }
    private func capabilityIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 18, height: 22)
            .accessibilityLabel(label)
            .help(label)
    }

}
private struct SelectedPetPreview: NSViewRepresentable {
    let runtime: CompanionRuntime
    let reduceMotion: Bool
    func makeNSView(context: Context) -> PetPreviewView {
        PetPreviewView(runtime: runtime)
    }
    func updateNSView(_ view: PetPreviewView, context: Context) {
        view.configure(reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: PetPreviewView, coordinator: ()) {
        view.stopAnimation()
    }
}

/// Keep the preview clock in AppKit: a frame must not invalidate the SwiftUI Form.
@MainActor final class PetPreviewView: NSView {
    private let pet: GraphicButton
    private let started = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var reduceMotion = false
    var isAnimating: Bool { timer != nil }
    var animationElapsed: TimeInterval { pet.elapsed }
    var artworkPixelData: Data? { pet.artworkPixelData }

    init(runtime: CompanionRuntime) {
        pet = GraphicButton(kind: .pet, runtime: runtime)
        super.init(frame: .zero)
        pet.isEnabled = false
        pet.setAccessibilityRole(.image)
        addSubview(pet)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        pet.frame = bounds
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }
    func configure(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        pet.reducedMotion = reduceMotion
        pet.setAccessibilityLabel(pet.runtime.localized("当前桌宠形象预览", "Selected pet preview"))
        renderFrame()
        updateAnimation()
    }
    func stopAnimation() {
        timer?.invalidate(); timer = nil
    }
    private func updateAnimation() {
        guard window != nil, !reduceMotion else { stopAnimation(); return }
        guard timer == nil else { return }
        let clock = Timer(timeInterval: 1 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.occlusionState.contains(.visible) == true,
                      !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
                self.renderFrame()
            }
        }
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }
    private func renderFrame() {
        let elapsed = reduceMotion ? 0 : ProcessInfo.processInfo.systemUptime - started
        pet.elapsed = elapsed; pet.clipElapsed = elapsed
        pet.refreshPetArtwork()
    }
}
struct AppearanceSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(runtime.localized("放置方式", "Placement"), selection: Binding(get: { runtime.petPlacement }, set: { runtime.setPlacement($0) })) {
                Text(runtime.localized("桌面", "Desktop")).tag(PetPlacement.desktop)
                Text(runtime.localized("左边缘", "Left edge")).tag(PetPlacement.left)
                Text(runtime.localized("右边缘", "Right edge")).tag(PetPlacement.right)
                Text(runtime.localized("上边缘", "Top edge")).tag(PetPlacement.top)
                Text(runtime.localized("下边缘", "Bottom edge")).tag(PetPlacement.bottom)
            }
            HStack {
                Text(runtime.localized("桌宠大小", "Pet size"))
                Slider(value: Binding(get: { runtime.petSize }, set: { runtime.setPetSize($0) }), in: 36...88, step: 2)
                    .accessibilityLabel(runtime.localized("桌宠大小", "Pet size"))
                Text("\(Int(runtime.petSize)) pt").monospacedDigit().frame(width: 46)
                Button(runtime.localized("重置", "Reset")) { runtime.setPetSize(48) }
            }
            HStack {
                Text(runtime.localized("气泡距离", "Bubble distance"))
                Slider(value: Binding(get: { runtime.effectiveBubbleDistance }, set: { runtime.setBubbleDistance($0) }), in: 8...72, step: 2)
                    .accessibilityLabel(runtime.localized("气泡与桌宠的距离", "Distance between pet and bubbles"))
                    .disabled(runtime.appearanceBehavior?.bubbleDistance != nil)
                Text("\(Int(runtime.effectiveBubbleDistance)) pt").monospacedDigit().frame(width: 46)
                Button(runtime.localized("重置", "Reset")) { runtime.setBubbleDistance(20) }.disabled(runtime.appearanceBehavior?.bubbleDistance != nil)
            }
            LabeledContent(runtime.localized("可见气泡", "Visible bubbles"), value: "\(runtime.bubbleCapacity)")
            Picker(runtime.localized("桌宠形象", "Pet appearance"), selection: Binding(get: { runtime.selectedSkinID }, set: { runtime.selectSkin($0) })) {
                ForEach(runtime.skins, id: \.id) { skin in Text(skin.name).tag(skin.id) }
            }
            if let themes = runtime.appearanceFeatures?.themes, !themes.isEmpty {
                Picker(runtime.localized("主题", "Theme"),selection: Binding(get: { runtime.selectedThemeID },set: { runtime.setAppearanceTheme($0) })) {
                    Text(runtime.localized("基础", "Base")).tag("")
                    ForEach(themes.keys.sorted(),id: \.self) { id in Text(themes[id]!.name).tag(id) }
                }
            }
            if runtime.appearanceFeatures?.behavior != nil {
                Toggle(runtime.localized("使用形象行为偏好", "Use appearance behavior preferences"),isOn: Binding(get: { runtime.useAppearanceBehavior },set: { runtime.setAppearanceBehavior($0) }))
            }
            if !runtime.installedIconStatus.isEmpty { Text(runtime.installedIconStatus).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 20) {
                SelectedPetPreview(runtime: runtime, reduceMotion: reduceMotion)
                    .frame(width: 76, height: 76)
                VStack(spacing: 4) {
                    Image(nsImage: runtime.softwareIcon(maxPixels:128)).resizable().interpolation(.high).frame(width: 64, height: 64)
                        .accessibilityLabel(runtime.localized("当前软件图标", "Selected application icon"))
                    Text(runtime.localized("软件图标", "App icon")).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(runtime.localized("导入形象…", "Import appearance…")) { runtime.importSkin() }
                Button(runtime.localized("删除当前形象", "Delete appearance")) { runtime.deleteSkin(runtime.selectedSkinID) }.disabled(runtime.selectedSkinID == "char.default")
            }
        }
    }
}
