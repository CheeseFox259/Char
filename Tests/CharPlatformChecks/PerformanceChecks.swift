import Foundation
import CharPlatform

func performanceChecks() {
    func sample(_ time: Double,_ cpu: Double,_ rss: UInt64,_ start: UInt64 = 1) -> ProcessPerformanceSample {
        ProcessPerformanceSample(processID: 20,started: start,timestamp: time,cpuSeconds: cpu,residentBytes: rss)
    }
    var stats = ProcessPerformanceStatistics()
    stats.record(sample(1,2,100))
    assert(stats.cpuPercent == nil && stats.averageCPUPercent == nil && stats.residentBytes == 100)
    stats.record(sample(2,3,200)); assert(stats.cpuPercent == 100)
    stats.record(sample(5,3.3,300))
    assert(abs(stats.cpuPercent! - 10) < 0.00001)
    assert(abs(stats.averageCPUPercent! - 32.5) < 0.00001,"CPU mean must be duration-weighted")
    assert(stats.averageResidentBytes == 200 && stats.peakResidentBytes == 300 && stats.peakCPUPercent == 100)
    stats.record(nil); assert(stats.cpuPercent == nil && stats.residentBytes == nil)
    stats.record(sample(100,10,400)); assert(stats.cpuPercent == nil && stats.measuredSeconds == 4,"missing process must break the interval")
    stats.record(sample(101,20,500,2)); assert(stats.cpuPercent == nil && stats.measuredSeconds == 4,"PID reuse must not combine CPU counters")
    stats.resetBaseline(); stats.record(sample(200,30,600,2)); assert(stats.cpuPercent == nil && stats.measuredSeconds == 4,"paused time excluded")
    assert(ProcessPerformanceSample.read(-1) == nil)
    let native = ProcessPerformanceSample.read(ProcessInfo.processInfo.processIdentifier)
    assert(native != nil && native!.residentBytes > 0 && native!.started > 0 && native!.cpuSeconds >= 0,"read actual own-process native usage")
    print("Performance: weighted averages, gaps, pause, PID identity and native own-process read passed")
}
