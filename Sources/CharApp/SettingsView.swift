import SwiftUI
import CharCore
import CharPlatform

private struct SettingsDisclosureGroup<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let expandedLabel: String
    let collapsedLabel: String
    let label: Label
    let content: Content
    init(isExpanded: Binding<Bool>, expandedLabel: String, collapsedLabel: String,
         @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self._isExpanded = isExpanded; self.expandedLabel = expandedLabel; self.collapsedLabel = collapsedLabel
        self.label = label(); self.content = content()
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button {
                withAnimation(.easeInOut(duration:0.12)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName:isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width:12).accessibilityHidden(true)
                    label
                    Spacer(minLength:0)
                }
                .frame(maxWidth:.infinity,minHeight:28,alignment:.leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? expandedLabel : collapsedLabel)
            if isExpanded { content }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @State private var permissionsExpanded = false
    private func l(_ zh: String, _ en: String) -> String { runtime.localized(zh, en) }
    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { !runtime.settings.collapsedSettingsSections.contains(id) }, set: { expanded in
            if expanded { runtime.settings.collapsedSettingsSections.remove(id) }
            else { runtime.settings.collapsedSettingsSections.insert(id) }
            runtime.saveSettings()
        })
    }
    @ViewBuilder private func category<Content: View>(_ id: String, _ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Section {
            SettingsDisclosureGroup(isExpanded:expansion(id),expandedLabel:l("已展开","Expanded"),collapsedLabel:l("已折叠","Collapsed")) { VStack(alignment: .leading, spacing: 14, content: content).padding(.top, 8) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if runtime.setupSection == id && !runtime.setupMessage.isEmpty {
                        Text(runtime.setupMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
        }
    }
    private func sample(_ group: AttentionPresentationGroup, past: Bool = false) -> some View {
        let color: NSColor = group == .interaction ? .systemBlue : group == .issue ? .systemOrange : .systemGreen
        return Image(nsImage: AttentionArtwork.sample(group: group, past: past, color: color))
            .accessibilityLabel(past ? l("已恢复", "Resumed") : runtime.localizedTitle(group))
    }
    var body: some View {
        Form {
            category("general", l("通用", "General")) {
                Picker(l("语言", "Language"), selection: Binding(get: { runtime.settings.language }, set: runtime.setLanguage)) {
                    Text("中文").tag(AppLanguage.chinese); Text("English").tag(AppLanguage.english)
                }
                Toggle(l("登录时启动", "Launch at login"), isOn: Binding(get: { runtime.settings.launchAtLogin }, set: runtime.setLogin)).disabled(runtime.demo)
                LabeledContent(l("启动状态", "Login status"), value: runtime.loginStatus)
                if let failure = runtime.loginFailure { Text(failure.message(language: runtime.settings.language)).foregroundStyle(.red).textSelection(.enabled) }
            }
            category("appearance", l("桌宠与交互", "Companion & interaction")) {
                AppearanceSettingsView(runtime: runtime)
                Text(l("贴边时从菜单栏和 Dock 以内的桌面边缘探出；拖动释放保留当前位置。", "Peeks from the usable desktop edge inside the menu bar and Dock. Releasing a drag keeps its position."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            category("attention", l("注意力与声音", "Attention & sound")) {
                HStack {
                    Text(l("停顿过滤（秒）", "Stop filter (seconds)")); Spacer()
                    TextField(l("秒", "Seconds"), value: $runtime.settings.filterSeconds, format: .number).labelsHidden()
                        .accessibilityLabel(l("停顿过滤，秒", "Stop filter, seconds")).frame(width: 80)
                }
                Toggle(l("播放声音", "Play sounds"), isOn: $runtime.settings.soundEnabled)
                    .onChange(of: runtime.settings.soundEnabled) { _ in runtime.saveSettings() }
                ForEach(AttentionPresentationGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            sample(group); Text(runtime.localizedTitle(group)).font(.subheadline.weight(.medium)); Spacer()
                            Button(l("试听", "Preview")) { runtime.previewAttentionSound(group) }.disabled(!runtime.settings.soundEnabled || runtime.demo)
                        }
                        HStack {
                            Text(runtime.settings.attentionAudioPaths[group.rawValue].map { URL(fileURLWithPath: $0).lastPathComponent }
                                 ?? l("使用当前形象音效", "Use appearance sound"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(l("选择…", "Choose…")) { runtime.chooseAudio(group: group) }.disabled(runtime.demo)
                            Button(l("恢复默认", "Reset")) { runtime.settings.attentionAudioPaths.removeValue(forKey: group.rawValue); runtime.saveSettings() }
                        }
                    }
                }
                Text(l("未查看且仍在等待的气泡逐渐放大：5 分钟达到 1.5 倍，并再提醒一次。", "Unviewed waiting bubbles grow to 1.5× over five minutes and remind once more."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack { sample(.interaction, past: true); Text(l("已恢复：保留入口，停止放大和再次提醒。", "Resumed: keeps the entry, stops growth and repeat reminders.")) }
                    .font(.caption).foregroundStyle(.secondary)
                Text(l("点击气泡不发声；桌宠互动音可被下一次点击打断，Agent 提醒优先。", "Bubble clicks are silent. New pet clicks interrupt interaction sounds; Agent reminders take priority."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            category("return", l("回城", "Return")) {
                Picker(l("返回起点", "Return origin"), selection: $runtime.settings.originPolicy) {
                    Text(l("首次起点", "First origin")).tag(CharSettings.OriginPolicy.original)
                    Text(l("最近起点", "Latest origin")).tag(CharSettings.OriginPolicy.latest)
                    Text(l("不记录", "Disabled")).tag(CharSettings.OriginPolicy.disabled)
                }.onChange(of: runtime.settings.originPolicy) { _ in runtime.saveSettings() }
                Toggle(l("允许应用级起点", "Allow application origins"), isOn: $runtime.settings.applicationOrigins)
                    .onChange(of: runtime.settings.applicationOrigins) { _ in runtime.saveSettings() }
                HStack {
                    Text(l("离开 Agent 后的宽限期（秒）", "Grace after leaving Agent (seconds)")); Spacer()
                    TextField(l("秒", "Seconds"), value: $runtime.settings.graceSeconds, format: .number).labelsHidden()
                        .accessibilityLabel(l("回城宽限期，秒", "Return grace, seconds")).frame(width: 80)
                }
                Label(l("准确回城：返回保存的具体界面。", "Exact return: the saved interface."), systemImage: NavigationPresentation.exactSymbol)
                Label(l("应用级回城：返回所属应用。", "Application return: the owning app."), systemImage: NavigationPresentation.applicationSymbol)
                Label(l("目标不可用：保留起点供重试。", "Unavailable: keeps the origin for retry."), systemImage: NavigationPresentation.unavailableSymbol)
                Text(runtime.homeShortcutStatus).font(.caption)
                Button(l("重试 Ctrl+B", "Retry Ctrl+B")) { runtime.retryHomeShortcut() }.disabled(runtime.snapshot.hold == nil)
                SettingsDisclosureGroup(isExpanded:$permissionsExpanded,expandedLabel:l("已展开","Expanded"),collapsedLabel:l("已折叠","Collapsed")) {
                    LabeledContent(l("辅助功能", "Accessibility"), value: runtime.accessibilityStatus)
                    Button(l("授权辅助功能…", "Authorize Accessibility…")) { runtime.requestAccessibility() }.disabled(runtime.demo)
                    LabeledContent(l("Tabbit 自动化", "Tabbit Automation"), value: runtime.automationStatus)
                    Button(l("授权 Tabbit 回城…", "Authorize Tabbit return…")) { runtime.requestAutomation() }.disabled(runtime.demo)
                    Button(l("刷新状态", "Refresh status")) { runtime.refreshStatus() }
                } label: { Text(l("权限与连接", "Permissions & connections")) }
            }
            category("plugins", l("集成插件", "Integrations")) {
                PluginSettingsView(runtime: runtime)
                Label(l("终端角标表示 CLI 工作端。", "A terminal badge identifies a CLI client."), systemImage: "terminal.fill").font(.caption).foregroundStyle(.secondary)
            }
            category("performance", l("性能与诊断", "Performance & diagnostics")) {
                PerformanceSettingsView(runtime: runtime, monitor: runtime.performanceMonitor)
                Toggle(l("记录桌宠通知时间线", "Record companion notification timeline"), isOn: $runtime.presentationTracing)
                Text(l("仅记录可见性、Space 和拖动状态，不含聊天内容。重启后关闭。", "Records visibility, Space and drag state, without conversation content. Resets on restart."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(l("显示记录", "Show trace")) { NSWorkspace.shared.activateFileViewerSelecting([runtime.presentationTraceURL]) }
                    .disabled(runtime.presentationTraceCount == 0)
            }

        }
        .formStyle(.grouped).padding(8).frame(minWidth: 560, minHeight: 590)
        .onChange(of: runtime.settings.filterSeconds) { _ in runtime.saveSettings() }
        .onChange(of: runtime.settings.graceSeconds) { _ in runtime.saveSettings() }
        .onDisappear { runtime.saveSettings() }
    }
}
