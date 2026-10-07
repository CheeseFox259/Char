import AppKit
import Darwin
import CharPlatform

extension CompanionRuntime {
    /// Repeatable isolated workload; no real clients, permissions or installed icon writes.
    func runMemoryCheck() async throws {
        guard demo, let skinStore,
              let source = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_PACKAGE"],
              let destination = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_OUTPUT"] else {
            throw PetSkinError.invalid("memory check requires an isolated demo and output directory")
        }
        defer { appearanceScript?.stop(); try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let skin = try skinStore.importPackage(at: URL(fileURLWithPath: source))
        selectSkin(skin.id); setPetSize(48); setPlacement(.desktop)
        let start = memoryReading(ProcessInfo.processInfo.processIdentifier)
        var phases: [[String:Any]] = []
        for phase in ["idle", "settings", "actions"] {
            if phase == "settings" { showSettings() }
            if phase == "actions" { settingsWindow?.close() }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var samples: [[String:Double]] = []
            for index in 0..<8 {
                if phase == "actions" {
                    panel.surface.appearanceFeedback(["press","return","curious","celebrate"][index % 4])
                }
                var sample = memoryReading(ProcessInfo.processInfo.processIdentifier)
                if let pid = appearanceScript?.processID {
                    let helper = memoryReading(pid)
                    sample["script_footprint_mib"] = helper["footprint_mib"]
                    sample["script_cpu_seconds"] = helper["cpu_seconds"]
                }
                samples.append(sample)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            let first = samples.first!, last = samples.last!
            let cpu = (last["cpu_seconds"]!-first["cpu_seconds"]!)/(last["time"]!-first["time"]!)*100
            phases.append(["phase":phase,"cpu_percent":cpu,"samples":samples,
                "footprint_average_mib":samples.reduce(0) { $0+($1["footprint_mib"] ?? 0) }/Double(samples.count)])
        }
        let output = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories:true)
        let report: [String:Any] = ["conditions":"release / isolated demo / day / desktop 48pt / 30fps / 7 fixture work ends / 8 samples per phase",
            "startup":start,"phases":phases]
        try JSONSerialization.data(withJSONObject: report,options:[.prettyPrinted,.sortedKeys])
            .write(to:output.appendingPathComponent("memory-check.json"))
        print("Memory workload completed: startup, idle, settings and actions")
    }
}

private func memoryReading(_ pid: Int32) -> [String:Double] {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to:&info) {
        $0.withMemoryRebound(to:Optional<rusage_info_t>.self,capacity:1) { proc_pid_rusage(pid,RUSAGE_INFO_V4,$0) }
    }
    guard result == 0 else { return [:] }
    return ["footprint_mib":Double(info.ri_phys_footprint)/1048576,
        "lifetime_peak_mib":Double(info.ri_lifetime_max_phys_footprint)/1048576,
        "rss_mib":Double(info.ri_resident_size)/1048576,
        "cpu_seconds":Double(info.ri_user_time+info.ri_system_time)/1e9,
        "time":ProcessInfo.processInfo.systemUptime]
}
