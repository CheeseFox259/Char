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
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
                HStack {
                    Text("Hold grace (seconds)")
                    Spacer()
                    TextField("Seconds", value: $runtime.settings.graceSeconds, format: .number)
                        .frame(width: 90).onSubmit { runtime.saveSettings() }
                }
                Text("Hold grace accumulates while you are away from Agent apps. Returning to an Agent pauses it.")
                    .font(.caption).foregroundStyle(.secondary)
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
                HStack(spacing: 18) {
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
                Text("The large number is unviewed attention; the small mint number is running sessions. Click a bubble to visit; right-click to ignore its first item. Drag the spark to place it. Its source badge means click to return; right-click for controls.")
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
