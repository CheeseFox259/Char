import SwiftUI
import CharCore

struct PluginSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @State private var deleteID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("所有前台应用都可记录为回城起点，包括 Agent。插件统一配置提醒和准确返回能力；停用提醒不影响应用级回城。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(runtime.pluginEntries) { entry in
                HStack {
                    Toggle(entry.plugin.name, isOn: Binding(get: { entry.enabled }, set: { runtime.setPlugin(entry.id, enabled: $0) }))
                    Spacer()
                    Text(capabilities(entry.plugin)).font(.caption).foregroundStyle(.secondary)
                    Button { deleteID = entry.id } label: { Image(systemName: "trash") }
                        .accessibilityLabel("删除 \(entry.plugin.name)")
                }
            }
            HStack {
                Button("导入插件…") { runtime.importPlugin() }
                Button("恢复已删除的内置插件") { runtime.restorePlugins() }
            }
            Text("自定义插件可配置现有 Agent 的目标应用、图标及准确返回适配器。未安装插件的应用也支持应用级回城；停用准确返回适配器会结束依赖它的回城。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("删除插件？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("取消", role: .cancel) { deleteID = nil }
            Button("删除", role: .destructive) { if let id = deleteID { runtime.deletePlugin(id) }; deleteID = nil }
        } message: { Text("插件将从 Char 移除。已安装在 Agent 客户端的观察 Hook 保留，可按集成文档卸载。") }
    }
    private func capabilities(_ plugin: IntegrationPlugin) -> String {
        var labels: [String] = []
        if plugin.workEnd != nil { labels.append("提醒") }
        if plugin.returnAdapter == .tabbit || plugin.returnAdapter == .vscode { labels.append("准确回城") }
        else { labels.append("应用级回城") }
        return labels.joined(separator: " · ")
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
            HStack {
                Text("桌宠大小")
                Slider(value: Binding(get: { runtime.petSize }, set: { runtime.setPetSize($0) }), in: 36...88, step: 2)
                    .accessibilityLabel("桌宠大小")
                Text("\(Int(runtime.petSize)) pt").monospacedDigit().frame(width: 46)
                Button("重置") { runtime.setPetSize(48) }
            }
            HStack {
                Text("气泡距离")
                Slider(value: Binding(get: { runtime.bubbleDistance }, set: { runtime.setBubbleDistance($0) }), in: 8...72, step: 2)
                    .accessibilityLabel("气泡与桌宠的距离")
                Text("\(Int(runtime.bubbleDistance)) pt").monospacedDigit().frame(width: 46)
                Button("重置") { runtime.setBubbleDistance(20) }
            }
            Text("当前轨道可容纳 \(runtime.bubbleCapacity) 个气泡，超过后自动折叠。")
                .font(.caption).foregroundStyle(.secondary)
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
            Text("拖动桌宠靠近屏幕边缘可吸附。有折叠气泡时才可用滚轮缓慢循环；末尾气泡最多显示 3 个小气泡。所有屏幕共享放置方式。切换桌面时桌宠轻缩再探出。系统的整屏桌面切换由 macOS 控制。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
