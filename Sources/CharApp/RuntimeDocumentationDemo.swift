import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    /// Reproducible screenshots using shipped examples and an isolated demo profile.
    func prepareDocumentationDemo() {
        guard demo, CommandLine.arguments.contains("--documentation-demo"),
              let examples = Bundle.main.resourceURL?.appendingPathComponent("Examples") else { return }
        do {
            for name in ["minimax-code-cli.charintegration", "minimax-code-desktop.charintegration"] {
                _ = try pluginStore?.importPackage(at: examples.appendingPathComponent(name))
            }
            pluginEntries = pluginStore?.entries ?? pluginEntries
            if CommandLine.arguments.contains("--documentation-feibi"), let skinStore {
                let skin = try skinStore.importPackage(at: examples.appendingPathComponent("feibi.charpet"))
                try skinStore.select(id: skin.id)
            }
            refreshSkins()
        } catch { setupMessage = "Documentation fixture failed: \(error)" }
    }

    func injectDocumentationFixtures() {
        let now = Date()
        let ends: [WorkEnd] = [.codexCLI, .pi, WorkEnd(rawValue: "minimaxcode.cli")!, WorkEnd(rawValue: "minimaxcode.desktop")!]
        router.ingest(ends.enumerated().map { index,end in
            ObservationEvent(key: SessionKey(workEnd: end, nativeID: "documentation-\(index)"),
                target: SessionTarget(bundleIdentifier: "fixture-only"), timestamp: now,
                state: .stopped(index == 1 ? .approval : .question))
        })
        router.advance(to: now); publish()
    }
}
