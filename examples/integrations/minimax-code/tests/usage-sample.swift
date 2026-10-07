import Foundation
import Darwin
let pids = CommandLine.arguments.dropFirst().compactMap(Int32.init)
var previous: [Int32:(Double,Double)] = [:]
for _ in 0..<21 {
  for pid in pids {
    var info = rusage_info_v2()
    let ok = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: Optional<rusage_info_t>.self,capacity: 1) { proc_pid_rusage(pid,RUSAGE_INFO_V2,$0) } }
    if ok != 0 { continue }
    let now = ProcessInfo.processInfo.systemUptime
    let cpu = (Double(info.ri_user_time)+Double(info.ri_system_time))/1e9
    let percent = previous[pid].map { (cpu-$0.1)/(now-$0.0)*100 }
    let row: [String:Any] = ["pid":pid,"uptime":now,"cpuPercent":percent as Any? ?? NSNull(),"rssMiB":Double(info.ri_resident_size)/1048576,"footprintMiB":Double(info.ri_phys_footprint)/1048576]
    print(String(data: try! JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]),encoding:.utf8)!)
    previous[pid] = (now,cpu)
  }
    Thread.sleep(forTimeInterval:1)
}
