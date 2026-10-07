import Foundation
import Darwin

public struct ProcessPerformanceSample: Sendable {
    public let processID: Int32
    public let started: UInt64
    public let timestamp: TimeInterval
    public let cpuSeconds: Double
    public let residentBytes: UInt64
    public let physicalFootprintBytes: UInt64?
    public init(processID: Int32, started: UInt64, timestamp: TimeInterval, cpuSeconds: Double, residentBytes: UInt64, physicalFootprintBytes: UInt64? = nil) {
        self.processID = processID; self.started = started; self.timestamp = timestamp
        self.cpuSeconds = cpuSeconds; self.residentBytes = residentBytes; self.physicalFootprintBytes = physicalFootprintBytes
    }
    public static func read(_ pid: Int32) -> Self? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Optional<rusage_info_t>.self,capacity: 1) { proc_pid_rusage(pid,RUSAGE_INFO_V2,$0) }
        }
        guard status == 0 else { return nil }
        return Self(processID: pid,started: info.ri_proc_start_abstime,timestamp: ProcessInfo.processInfo.systemUptime,
                    cpuSeconds: (Double(info.ri_user_time)+Double(info.ri_system_time))/1_000_000_000,residentBytes: info.ri_resident_size,physicalFootprintBytes:info.ri_phys_footprint)
    }
}

/// CPU: time-weighted valid intervals. Memory: mean of each metric’s successful samples.
public struct ProcessPerformanceStatistics: Sendable {
    public private(set) var cpuPercent: Double?
    public private(set) var physicalFootprintBytes: UInt64?
    public private(set) var peakPhysicalFootprintBytes: UInt64 = 0
    public private(set) var footprintSampleCount = 0
    private var footprintTotal: Double = 0
    public var averagePhysicalFootprintBytes: Double? { footprintSampleCount > 0 ? footprintTotal/Double(footprintSampleCount):nil }
    public private(set) var residentBytes: UInt64?
    public private(set) var peakCPUPercent: Double = 0
    public private(set) var peakResidentBytes: UInt64 = 0
    public private(set) var sampleCount = 0
    public private(set) var measuredSeconds: Double = 0
    private var measuredCPUSeconds: Double = 0
    private var residentTotal: Double = 0
    private var previous: ProcessPerformanceSample?
    public init() {}
    public var averageCPUPercent: Double? { measuredSeconds > 0 ? measuredCPUSeconds/measuredSeconds*100 : nil }
    public var averageResidentBytes: Double? { sampleCount > 0 ? residentTotal/Double(sampleCount) : nil }
    public mutating func resetBaseline() { previous = nil; cpuPercent = nil }
    public mutating func record(_ sample: ProcessPerformanceSample?) {
        cpuPercent = nil; residentBytes = sample?.residentBytes; physicalFootprintBytes = sample?.physicalFootprintBytes
        guard let sample else { previous = nil; return }
        if let bytes = sample.physicalFootprintBytes {
            footprintSampleCount += 1; footprintTotal += Double(bytes); peakPhysicalFootprintBytes = max(peakPhysicalFootprintBytes,bytes)
        }
        sampleCount += 1; residentTotal += Double(sample.residentBytes)
        peakResidentBytes = max(peakResidentBytes,sample.residentBytes)
        if let old = previous, old.processID == sample.processID, old.started == sample.started {
            let elapsed = sample.timestamp-old.timestamp, cpu = sample.cpuSeconds-old.cpuSeconds
            if elapsed > 0, cpu >= 0 {
                let percent = cpu/elapsed*100
                cpuPercent = percent; peakCPUPercent = max(peakCPUPercent,percent)
                measuredCPUSeconds += cpu; measuredSeconds += elapsed
            }
        }
        previous = sample
    }
}
