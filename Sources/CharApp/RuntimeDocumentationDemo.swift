import AppKit
import CharCore
import CharPlatform
import QuartzCore

extension CompanionRuntime {
    /// Reproducible screenshots using shipped examples and an isolated demo profile.
    func prepareDocumentationDemo() {
        guard demo, CommandLine.arguments.contains("--documentation-demo"),
              let examples = Bundle.main.resourceURL?.appendingPathComponent("Examples") else { return }
        do {
            if CommandLine.arguments.contains("--documentation-feibi"), let skinStore {
                let skin = try skinStore.importPackage(at: examples.appendingPathComponent("feibi.charpet"))
                try skinStore.select(id: skin.id)
            }
            refreshSkins()
        } catch { setupMessage = "Documentation fixture failed: \(error)" }
    }

    func injectDocumentationFixtures() {
        let now = Date()
        let ends: [WorkEnd] = [.claudeCode, .codexDesktop, .pi, .kimiDesktop]
        router.ingest(ends.enumerated().map { index,end in
            ObservationEvent(key: SessionKey(workEnd: end, nativeID: "documentation-\(index)"),
                target: SessionTarget(bundleIdentifier: "fixture-only"), timestamp: now,
                state: .stopped(index == 1 ? .approval : .question))
        })
        router.advance(to: now); publish()
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--documentation-export"), index + 1 < args.count {
            let output = URL(fileURLWithPath: args[index + 1])
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                do { try exportDocumentationImage(to: output) }
                catch { fputs("Documentation export failed: \(error)\n",stderr); exit(1) }
                NSApp.terminate(nil)
            }
        }
    }

    private func exportDocumentationImage(to output: URL) throws {
        let view = panel.surface, size = view.bounds.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: Int(size.width * 4),pixelsHigh: Int(size.height * 4),
                                      bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,
                                      colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        bitmap.size = size
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.cgContext.setFillColor(NSColor(calibratedRed: 0.94,green: 0.96,blue: 0.99,alpha: 1).cgColor)
        context.cgContext.fill(view.bounds)
        view.displayIfNeeded(); CATransaction.flush()
        view.layer?.render(in: context.cgContext)
        try bitmap.representation(using: .png,properties: [:])!.write(to: output,options: .atomic)
        print("Exported native companion: \(output.path), \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
    }
}
