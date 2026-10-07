import AppKit
import CharPlatform

struct PerformanceTarget: Identifiable, Sendable {
    let id: String
    let title: String
    let kind: String
    let processID: Int32?
}
struct PerformanceRow: Identifiable {
    let target: PerformanceTarget
    let statistics: ProcessPerformanceStatistics
    var id: String { target.id }
}

@MainActor final class PerformanceMonitor: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var rows: [PerformanceRow] = []
    var targets: (() -> [PerformanceTarget])?
    private var statistics: [String: ProcessPerformanceStatistics] = [:]
    private var timer: Timer?
    private var sampling = false
    private var generation = 0
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; generation += 1
        timer?.invalidate(); timer = nil
        for id in statistics.keys { statistics[id]?.resetBaseline() }
        guard value else { return }
        tick()
        let timer = Timer(timeInterval: 1,repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer,forMode: .common); self.timer = timer
    }
    func reset() {
        generation += 1; statistics.removeAll(); rows = []
        if enabled { tick() }
    }
    private func tick() {
        guard enabled, !sampling, let targets else { return }
        let current = targets(), revision = generation
        sampling = true
        Task { [weak self] in
            let samples = await Task.detached(priority: .utility) {
                current.map { $0.processID.flatMap(ProcessPerformanceSample.read) }
            }.value
            guard let self else { return }
            self.sampling = false
            guard self.enabled, revision == self.generation else { return }
            let ids = Set(current.map(\.id))
            self.statistics = self.statistics.filter { ids.contains($0.key) }
            self.rows = zip(current,samples).map { target,sample in
                var value = self.statistics[target.id] ?? ProcessPerformanceStatistics()
                value.record(sample); self.statistics[target.id] = value
                return PerformanceRow(target: target,statistics: value)
            }
        }
    }
    deinit { timer?.invalidate() }
}

extension CompanionRuntime {
    func performanceTargets() -> [PerformanceTarget] {
        var targets = [PerformanceTarget(id: "host",title: "Char",kind: "host",processID: ProcessInfo.processInfo.processIdentifier)]
        targets.append(PerformanceTarget(id: "skin/"+selectedSkinID,title: skinStore?.selectedSkin.name ?? "Char",kind: "appearance",processID: appearanceScript?.processID))
        let processes = capabilityHost?.runningPluginProcesses ?? [:]
        for entry in pluginEntries.filter(\.enabled).sorted(by: { $0.plugin.name < $1.plugin.name }) {
            targets.append(PerformanceTarget(id: "plugin/"+entry.id,title: entry.plugin.name,kind: "adapter",processID: processes[entry.id]))
        }
        return targets
    }
}
