import SwiftUI
import CharCore

struct PluginSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @State private var deleteID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(runtime.pluginEntries) { entry in
                HStack {
                    Toggle(entry.plugin.name, isOn: Binding(get: { entry.enabled }, set: { runtime.setPlugin(entry.id, enabled: $0) }))
                    Spacer()
                    capabilityIcons(entry.plugin)
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
            Button(runtime.localized("删除", "Delete"), role: .destructive) { if let id = deleteID { runtime.deletePlugin(id) }; deleteID = nil }
        } message: { Text(runtime.localized("客户端 Hook 会保留。", "Client hooks remain installed.")) }
    }
    private func capabilityIcons(_ plugin: IntegrationPlugin) -> some View {
        HStack(spacing: 8) {
            if plugin.workEnd != nil {
                capabilityIcon("bell.fill", label: runtime.localized("提醒", "Notifications"))
            }
            if plugin.returnAdapter == .tabbit || plugin.returnAdapter == .vscode {
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
    let elapsed: TimeInterval
    func makeNSView(context: Context) -> GraphicButton {
        let view = GraphicButton(kind: .pet, runtime: runtime)
        view.isEnabled = false
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(runtime.localized("当前桌宠形象预览", "Selected pet preview"))
        return view
    }
    func updateNSView(_ view: GraphicButton, context: Context) {
        view.setAccessibilityLabel(runtime.localized("当前桌宠形象预览", "Selected pet preview"))
        view.elapsed = elapsed; view.clipElapsed = elapsed; view.needsDisplay = true
    }
}
struct AppearanceSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewStarted = Date()
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
                Slider(value: Binding(get: { runtime.bubbleDistance }, set: { runtime.setBubbleDistance($0) }), in: 8...72, step: 2)
                    .accessibilityLabel(runtime.localized("气泡与桌宠的距离", "Distance between pet and bubbles"))
                Text("\(Int(runtime.bubbleDistance)) pt").monospacedDigit().frame(width: 46)
                Button(runtime.localized("重置", "Reset")) { runtime.setBubbleDistance(20) }
            }
            LabeledContent(runtime.localized("可见气泡", "Visible bubbles"), value: "\(runtime.bubbleCapacity)")
            Picker(runtime.localized("桌宠形象", "Pet appearance"), selection: Binding(get: { runtime.selectedSkinID }, set: { runtime.selectSkin($0) })) {
                ForEach(runtime.skins, id: \.id) { skin in Text(skin.name).tag(skin.id) }
            }
            HStack(spacing: 20) {
                TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { timeline in
                    SelectedPetPreview(runtime: runtime, elapsed: reduceMotion ? 0 : timeline.date.timeIntervalSince(previewStarted))
                        .frame(width: 76, height: 76)
                }
                VStack(spacing: 4) {
                    Image(nsImage: runtime.softwareIcon).resizable().interpolation(.high).frame(width: 64, height: 64)
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
