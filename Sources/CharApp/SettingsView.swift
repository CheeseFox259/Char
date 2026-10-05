import SwiftUI
import CharCore

struct SettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    private func l(_ zh: String, _ en: String) -> String { runtime.localized(zh, en) }
    var body: some View {
        Form {
            Section {
                Picker(l("语言", "Language"), selection: Binding(get: { runtime.settings.language }, set: { runtime.setLanguage($0) })) {
                    Text("中文").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
            }
            Section(l("桌宠与动效", "Appearance")) { AppearanceSettingsView(runtime: runtime) }
            Section(l("插件", "Plugins")) { PluginSettingsView(runtime: runtime) }
            Section(l("时间", "Timing")) {
                HStack {
                    Text(l("过滤阈值（秒）", "Filter threshold (seconds)")); Spacer()
                    TextField(l("秒", "Seconds"), value: $runtime.settings.filterSeconds, format: .number)
                        .labelsHidden().accessibilityLabel(l("过滤阈值，秒", "Filter threshold, seconds"))
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
                HStack {
                    Text(l("回城宽限期（秒）", "Return grace (seconds)")); Spacer()
                    TextField(l("秒", "Seconds"), value: $runtime.settings.graceSeconds, format: .number)
                        .labelsHidden().accessibilityLabel(l("回城宽限期，秒", "Return grace, seconds"))
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
            }
            Section(l("回城", "Return")) {
                Text(runtime.homeShortcutStatus)
                Button(l("重试 Ctrl+B", "Retry Ctrl+B")) { runtime.retryHomeShortcut() }
                    .disabled(runtime.snapshot.hold == nil)
            }
            Section(l("声音", "Sound")) {
                Toggle(l("提醒音效", "Attention sound"), isOn: $runtime.settings.soundEnabled)
                    .onChange(of: runtime.settings.soundEnabled) { _ in runtime.saveSettings() }
                HStack {
                    Text(runtime.settings.audioFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? l("系统提示音", "System Ping"))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(l("选择音频…", "Choose audio…")) { runtime.chooseAudio() }.disabled(runtime.demo)
                    Button(l("重置", "Reset")) { runtime.settings.audioFilePath = nil; runtime.saveSettings() }
                }
            }
            Section(l("启动与权限", "Startup & permissions")) {
                Toggle(l("登录时启动", "Launch at login"), isOn: Binding(get: { runtime.settings.launchAtLogin }, set: { runtime.setLogin($0) })).disabled(runtime.demo)
                LabeledContent(l("启动状态", "Login status"), value: runtime.loginStatus)
                LabeledContent(l("辅助功能", "Accessibility"), value: runtime.accessibilityStatus)
                Button(l("授权辅助功能…", "Authorize Accessibility…")) { runtime.requestAccessibility() }.disabled(runtime.demo)
                LabeledContent(l("Tabbit 自动化", "Tabbit Automation"), value: runtime.automationStatus)
                Button(l("授权 Tabbit 回城…", "Authorize Tabbit return…")) { runtime.requestAutomation() }.disabled(runtime.demo)
                Button(l("刷新状态", "Refresh status")) { runtime.refreshStatus() }
            }
            Section(l("图例", "Legend")) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 9) {
                    ForEach(AttentionPresentationGroup.allCases, id: \.self) { group in Label(runtime.localizedTitle(group), systemImage: group.symbol) }
                    Label(l("CLI 工作端", "CLI client"), systemImage: "terminal.fill")
                    Label(l("已恢复", "Resumed"), systemImage: "circle.lefthalf.filled")
                    Label(l("提醒", "Notifications"), systemImage: "bell.fill")
                    Label(l("准确回城", "Exact return"), systemImage: NavigationPresentation.exactSymbol)
                    Label(l("应用级回城", "Application return"), systemImage: NavigationPresentation.applicationSymbol)
                    Label(l("目标不可用", "Target unavailable"), systemImage: NavigationPresentation.unavailableSymbol)
                }.font(.caption)
            }
            if !runtime.setupMessage.isEmpty {
                Section(l("错误", "Error")) { Text(runtime.setupMessage).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped).padding(8).frame(minWidth: 500, minHeight: 590)
        .onChange(of: runtime.settings.filterSeconds) { _ in runtime.saveSettings() }
        .onChange(of: runtime.settings.graceSeconds) { _ in runtime.saveSettings() }
        .onDisappear { runtime.saveSettings() }
    }
}
