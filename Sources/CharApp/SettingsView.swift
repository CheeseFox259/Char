import SwiftUI
import CharCore

struct SettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    var body: some View {
        Form {
            Section("桌宠与动效") { AppearanceSettingsView(runtime: runtime) }
            Section("插件") { PluginSettingsView(runtime: runtime) }
            Section("Timing") {
                HStack {
                    Text("Filter threshold (seconds)")
                    Spacer()
                    TextField("Seconds", value: $runtime.settings.filterSeconds, format: .number)
                        .labelsHidden().accessibilityLabel("过滤阈值，秒")
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
                HStack {
                    Text("Hold grace (seconds)")
                    Spacer()
                    TextField("Seconds", value: $runtime.settings.graceSeconds, format: .number)
                        .labelsHidden().accessibilityLabel("回城宽限期，秒")
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
                Text("Hold grace accumulates while you are away from Agent apps. Returning to an Agent pauses it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("回城") {
                Text(runtime.homeShortcutStatus)
                Text("Hold 中按 Ctrl+B 或点击桌宠，返回首次离开前的来源。没有 Hold 时不注册快捷键。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重试 Ctrl+B 注册") { runtime.retryHomeShortcut() }
                    .disabled(runtime.snapshot.hold == nil)
            }
            Section("Sound") {
                Toggle("Play one sound for a batch of new attention", isOn: $runtime.settings.soundEnabled)
                    .onChange(of: runtime.settings.soundEnabled) { _ in runtime.saveSettings() }
                HStack {
                    Text(runtime.settings.audioFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "System Ping")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose Audio…") { runtime.chooseAudio() }.disabled(runtime.demo)
                    Button("Reset") { runtime.settings.audioFilePath = nil; runtime.saveSettings() }
                }
            }
            Section("Startup & integrations") {
                Text("pi、Kimi CLI/App 与 DeepSeek Desktop 需显式安装本地观察集成。步骤见项目 README；未启用时这些工作端不会产生原生提醒。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: Binding(get: { runtime.settings.launchAtLogin }, set: { runtime.setLogin($0) }))
                    .disabled(runtime.demo)
                LabeledContent("Actual login status", value: runtime.loginStatus)
                LabeledContent("Accessibility", value: runtime.accessibilityStatus)
                Button("Authorize focused display tracking…") { runtime.requestAccessibility() }.disabled(runtime.demo)
                LabeledContent("Tabbit Automation", value: runtime.automationStatus)
                Button("Authorize Tabbit return…") { runtime.requestAutomation() }.disabled(runtime.demo)
                Text("VS Code exact return requires the optional local Char Return Anchor extension. Warp sources have no Hold. WeChat returns to the application with a fallback mark.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh Status") { runtime.refreshStatus() }
            }
            Section("Graphical legend") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 9) {
                    ForEach(WorkEnd.allCases, id: \.self) { end in
                        Label(end.title, systemImage: end.symbol).font(.caption)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 9) {
                    ForEach(AttentionPresentationGroup.allCases, id: \.self) { group in
                        Label(group.title, systemImage: group.symbol)
                    }
                    Label("CLI 工作端", systemImage: "terminal.fill")
                    Label("已恢复：状态胶囊变淡", systemImage: "circle.lefthalf.filled")
                }.font(.caption)
                VStack(alignment: .leading, spacing: 9) {
                    Text("导航反馈（独立于 Agent 停顿状态）").font(.caption.weight(.semibold))
                    Label("应用级降级：可返回应用，无法精确定位原窗口或标签", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    Label("目标不可用：无法找到或激活来源或 Agent 目标", systemImage: "exclamationmark.circle.fill")
                }.font(.caption)
                Text("气泡只显示一个状态胶囊和未查看数量：需关注、发生问题、轮次结束。淡色胶囊表示该停顿已恢复；精确原因和运行数量可通过无障碍说明查看。CLI 带小终端标识。点击气泡访问，右键忽略首项；状态栏提供设置与回城入口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !runtime.setupMessage.isEmpty {
                Section("Setup") { Text(runtime.setupMessage).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 500, minHeight: 590)
        .onChange(of: runtime.settings.filterSeconds) { _ in runtime.saveSettings() }
        .onChange(of: runtime.settings.graceSeconds) { _ in runtime.saveSettings() }
        .onDisappear { runtime.saveSettings() }
    }
}
