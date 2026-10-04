import SwiftUI
import CharCore

struct PluginSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @State private var deleteID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("启停即时生效。停用 Agent 会清除其提醒；停用当前来源会结束回城。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach([IntegrationPlugin.Kind.agent, .source], id: \.self) { kind in
                Text(kind == .agent ? "Agent" : "回城来源").font(.headline)
                ForEach(runtime.pluginEntries.filter { $0.plugin.kind == kind }) { entry in
                    HStack {
                        Toggle(entry.plugin.name, isOn: Binding(get: { entry.enabled }, set: { runtime.setPlugin(entry.id, enabled: $0) }))
                        Spacer()
                        if entry.plugin.sourceAdapter == .application { Text("应用级").font(.caption).foregroundStyle(.secondary) }
                        Button { deleteID = entry.id } label: { Image(systemName: "trash") }
                            .accessibilityLabel("删除 \(entry.plugin.name)")
                    }
                }
            }
            HStack {
                Button("导入插件…") { runtime.importPlugin() }
                Button("恢复已删除的内置插件") { runtime.restorePlugins() }
            }
            Text("自定义插件可配置现有 Agent 的目标应用、图标，或添加应用级来源。精确返回取决于来源的集成能力。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("删除插件？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("取消", role: .cancel) { deleteID = nil }
            Button("删除", role: .destructive) { if let id = deleteID { runtime.deletePlugin(id) }; deleteID = nil }
        } message: { Text("插件将从 Char 移除。已安装在 Agent 客户端的观察 Hook 保留，可按集成文档卸载。") }
    }
}
private struct SelectedPetPreview: NSViewRepresentable {
    let runtime: CompanionRuntime
    let elapsed: TimeInterval
    func makeNSView(context: Context) -> GraphicButton {
        let view = GraphicButton(kind: .pet, runtime: runtime)
        view.isEnabled = false
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("当前桌宠形象预览")
        return view
    }
    func updateNSView(_ view: GraphicButton, context: Context) {
        view.elapsed = elapsed; view.clipElapsed = elapsed; view.needsDisplay = true
    }
}
struct AppearanceSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewStarted = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("放置方式", selection: Binding(get: { runtime.petPlacement }, set: { runtime.setPlacement($0) })) {
                Text("桌面").tag(PetPlacement.desktop)
                Text("左边缘").tag(PetPlacement.left)
                Text("右边缘").tag(PetPlacement.right)
                Text("上边缘").tag(PetPlacement.top)
                Text("下边缘").tag(PetPlacement.bottom)
            }
            Picker("桌宠形象", selection: Binding(get: { runtime.selectedSkinID }, set: { runtime.selectSkin($0) })) {
                ForEach(runtime.skins, id: \.id) { skin in Text(skin.name).tag(skin.id) }
            }
            TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { timeline in
                SelectedPetPreview(runtime: runtime, elapsed: reduceMotion ? 0 : timeline.date.timeIntervalSince(previewStarted))
                    .frame(width: 76, height: 76)
            }
            HStack {
                Button("导入形象…") { runtime.importSkin() }
                Button("删除当前形象") { runtime.deleteSkin(runtime.selectedSkinID) }.disabled(runtime.selectedSkinID == "char.default")
            }
            Text("拖动桌宠靠近屏幕边缘可吸附。滚轮循环切换气泡；末尾气泡最多显示 3 个小气泡。切换桌面时桌宠持续存在。系统的整屏桌面切换由 macOS 控制。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
