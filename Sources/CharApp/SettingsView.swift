import SwiftUI
import CharCore

struct SettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    var body: some View {
        Form {
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
                    ForEach(StopReason.allCases, id: \.self) { reason in
                        Label(reason.title, systemImage: reason.symbol)
                    }
                    Label("Past stop", systemImage: "clock.arrow.circlepath")
                    Label("Application fallback", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    Label("Unavailable", systemImage: "exclamationmark.circle.fill")
                }.font(.caption)
                Text("The large number is unviewed attention; the small mint number is running sessions. Click a bubble to visit; right-click to ignore its first item. Drag the spark to place it. Its source badge means click or Ctrl+B to 回城; right-click for controls.")
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
