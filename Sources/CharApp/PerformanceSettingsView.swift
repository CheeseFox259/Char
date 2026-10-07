import SwiftUI
import CharPlatform

struct PerformanceSettingsView: View {
    @ObservedObject var runtime: CompanionRuntime
    @ObservedObject var monitor: PerformanceMonitor
    private func l(_ zh: String,_ en: String) -> String { runtime.localized(zh,en) }
    private func cpu(_ value: Double?) -> String { value.map { String(format: "%.1f%%",$0) } ?? "—" }
    private func memory(_ value: Double?) -> String { value.map { String(format: "%.1f MiB",$0/1_048_576) } ?? l("不可用","Unavailable") }
    private func cachedMemory(_ bytes: Int) -> String {
        bytes < 1_048_576 ? String(format:"%.1f KiB",Double(bytes)/1024):memory(Double(bytes))
    }
    private func rssDetails(_ stats: ProcessPerformanceStatistics) -> String {
        let current = memory(stats.residentBytes.map { Double($0) })
        let average = memory(stats.averageResidentBytes)
        let peak = stats.sampleCount > 0 ? memory(Double(stats.peakResidentBytes)):"—"
        return "RSS · \(l("当前","Current")) \(current) · \(l("平均","Average")) \(average) · \(l("采样峰值","Sampled peak")) \(peak)"
    }
    private func kind(_ target: PerformanceTarget) -> String {
        switch target.kind {
        case "host": return l("宿主 · 共享开销","Host · shared costs")
        case "appearance": return target.processID == nil ? l("形象 · 运行于宿主","Appearance · in host") : l("形象 · 脚本进程","Appearance · script process")
        default: return target.processID == nil ? l("集成 · 运行于宿主","Integration · in host") : l("集成 · 适配器进程","Integration · adapter process")
        }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack {
                Toggle(l("实时采集","Live monitoring"),isOn: Binding(get: { monitor.enabled },set: monitor.setEnabled))
                Spacer()
                Button(l("清空统计","Reset statistics")) { monitor.reset() }.disabled(monitor.rows.isEmpty)
            }
            if !monitor.rows.isEmpty {
                Text(monitor.enabled ? l("每秒更新 · CPU 单核 100% · 本次采集","1s updates · CPU 100% per core · this monitoring session") : l("已暂停 · 保留本次统计","Paused · session statistics retained"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(monitor.rows) { row in
                    VStack(alignment: .leading,spacing: 5) {
                        HStack {
                            Text(row.target.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(kind(row.target)).font(.caption).foregroundStyle(.secondary)
                        }
                        if row.target.processID != nil || row.statistics.sampleCount > 0 {
                            Grid(alignment: .leading,horizontalSpacing: 14,verticalSpacing: 4) {
                                GridRow {
                                    Text(""); Text(l("当前","Current")); Text(l("平均","Average")); Text(l("峰值","Peak"))
                                }.foregroundStyle(.secondary)
                                GridRow {
                                    Text("CPU"); Text(cpu(row.statistics.cpuPercent)); Text(cpu(row.statistics.averageCPUPercent))
                                    Text(row.statistics.measuredSeconds > 0 ? cpu(row.statistics.peakCPUPercent) : "—")
                                }
                                GridRow {
                                    Text(l("内存","Memory")); Text(memory(row.statistics.physicalFootprintBytes.map { Double($0) }))
                                    Text(memory(row.statistics.averagePhysicalFootprintBytes))
                                    Text(row.statistics.footprintSampleCount > 0 ? memory(Double(row.statistics.peakPhysicalFootprintBytes)) : "—")
                                }
                            }.font(.caption.monospacedDigit())
                            Text(l("\(row.statistics.sampleCount) 次有效采样 · \(String(format: "%.1f",row.statistics.measuredSeconds)) 秒 CPU 区间","\(row.statistics.sampleCount) successful samples · \(String(format: "%.1f",row.statistics.measuredSeconds))s CPU intervals"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(l("图片缓存（宿主内）","Image cache (in host)")+" · "+cachedMemory(row.target.imageCacheBytes))
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(l("计量详情","Measurement details")) {
                            Text("Physical footprint")
                            if row.target.processID != nil || row.statistics.sampleCount > 0 {
                                Text(rssDetails(row.statistics))
                            }
                            if row.target.imageCacheBytes > 0 {
                                if row.target.sharedImageCacheBytes > 0 {
                                    Text(l("其中共享","Shared portion")+" · "+cachedMemory(row.target.sharedImageCacheBytes))
                                }
                                Text(l("解码像素估算，已计入 Char；不与进程内存相加。","Decoded pixel estimate, included in Char; do not add to process memory."))
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(10).frame(maxWidth: .infinity,alignment: .leading)
                        .background(.primary.opacity(0.035),in: RoundedRectangle(cornerRadius: 8))
                }
                Text(l("内存为 physical footprint；共享渲染与 Hook 计入宿主。适配器子进程不含在内。","Memory is physical footprint. Shared rendering and hooks are in the host; adapter child processes are excluded."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
