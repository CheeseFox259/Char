import Foundation
import Darwin
import CharCore
import CharPluginHost

enum Failure: Error { case check(String) }
func check(_ value: Bool, _ message: String) throws { if !value { throw Failure.check(message) } }
@main struct PluginChecks {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("char-capability-check-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("new.charintegration")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let script = #"""
        import {createInterface} from 'node:readline';
        import {writeFileSync} from 'node:fs';
        const config=JSON.parse(process.env.CHAR_PLUGIN_CONFIG||'{}');
        let active=false;
        createInterface({input:process.stdin}).on('line',line=>{
          const r=JSON.parse(line), p=r.params||{};
          if(p.hang) return;
          if(p.malformed) { console.log('broken-frame'); return; }
          let result={};
          switch(r.method) {
          case 'hello': result={protocolVersion:config.badVersion?'9':1}; break;
          case 'inspect': result={status:'ready'}; break;
          case 'start':
            for(const [workEnd,isChild] of [[process.env.CHAR_WORK_END,false],['other.client',false],[process.env.CHAR_WORK_END,true]])
              console.log(JSON.stringify({version:1,event:{workEnd,nativeID:isChild?'child':'root',timestamp:new Date().toISOString(),state:'stopped',reason:'question',isChild,target:{bundleIdentifier:'spoofed.app'}}}));
            break;
          case 'capture': result={token:'opaque',processID:p.processID}; break;
          case 'check': result={valid:true,active}; break;
          case 'focus': active=true; result={outcome:'exact',verified:true}; break;
          case 'visit': if(p.fail) {console.log(JSON.stringify({version:1,id:r.id,error:'fixture failure'})); return;} result={outcome:'exact',verified:true}; break;
          case 'install': case 'update': case 'uninstall':
            if(config.receipt) writeFileSync(config.receipt,r.method); result={status:r.method==='uninstall'?'notInstalled':'reloadRequired'}; break;
          }
          console.log(JSON.stringify({version:1,id:r.id,result}));
        });
        """#
        try Data(script.utf8).write(to: source.appendingPathComponent("adapter.mjs"))
        let end = WorkEnd(rawValue: "vendor.new.desktop")!
        var manifest = IntegrationPlugin(schemaVersion: 3, id: "vendor.new", name: "Independent client", workEnd: end,
            bundleIdentifier: "com.example.independent", version: "1", clientInterface: .desktop,
            adapter: AdapterDescriptor(runtime: .node, entrypoint: "adapter.mjs", capabilities: Set(PluginCapability.allCases), configuration: ["receipt":root.appendingPathComponent("receipt").path]))
        func save() throws { try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json")) }
        try save()
        let store = try IntegrationPluginStore(directory: root.appendingPathComponent("catalog"))
        var entry = try store.importPackage(at: source)
        let environment = ["PATH":"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME":root.path]
        let host = CapabilityHost(environment: environment)
        defer { host.stopAll() }
        await host.configure([entry])
        try check(host.health[entry.id]?.status == .ready, "handshake/inspect")
        _ = try await host.request(entry.id, method: "inspect")
        let events = host.drainEvents()
        try check(events.count == 2 && events.allSatisfy { $0.key.workEnd == end && $0.target.bundleIdentifier == manifest.bundleIdentifier }, "event identity authority")
        let router = AttentionRouter(startedAt: events.map(\.timestamp).min()!.addingTimeInterval(-1), settings: CharSettings(filterSeconds: 0))
        router.ingest(events); router.advance(to: Date())
        try check(router.snapshot.bubbles.count == 1 && router.snapshot.bubbles.first?.head?.key.nativeID == "root", "new client aggregation/child suppression")
        let visit = try await host.request(entry.id, method: "visit", params: ["nativeID":"root"])
        try check(visit["outcome"] as? String == "exact", "visit")
        let origin = try await host.request(entry.id, method: "capture", params:["processID":123])
        try check(origin["token"] as? String == "opaque", "capture")
        let before = try await host.request(entry.id, method: "check")
        try check(before["active"] as? Bool == false, "origin initially inactive")
        _ = try await host.request(entry.id, method: "focus")
        let after = try await host.request(entry.id, method: "check")
        try check(after["active"] as? Bool == true, "verified origin arrival")
        for method in ["install","update","uninstall"] {
            _ = try await host.lifecycle(entry, method: method)
            try check(try String(contentsOf: root.appendingPathComponent("receipt"), encoding:.utf8) == method, "lifecycle \(method)")
        }
        do { _ = try await host.request(entry.id, method:"visit", params:["fail":true]); throw Failure.check("failure accepted") } catch let error as Failure { throw error } catch {}
        if CommandLine.arguments.contains("--measure") {
            let pid = host.runningProcessIDs.first!
            func sample() throws -> (Double, Double) {
                let task = Process(); let pipe = Pipe()
                task.executableURL = URL(fileURLWithPath:"/bin/ps");task.arguments = ["-p",String(pid),"-o","time=,rss="];task.standardOutput = pipe
                try task.run();let text = String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);task.waitUntilExit()
                let values = text.split(whereSeparator: \.isWhitespace)
                let clock = values[0].split(separator:":").map { Double($0)! }
                return (clock.dropLast().reduce(0) { $0*60+$1 }*60+clock.last!,Double(values[1])!/1024)
            }
            let before = try sample(), start = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(nanoseconds:20_000_000_000)
            let after = try sample(), elapsed = ProcessInfo.processInfo.systemUptime-start
            print(String(format:"Adapter idle sample: %.2fs, %.3f%% single-core CPU, RSS %.2f → %.2f MiB (Node fixture; no live client)", elapsed,(after.0-before.0)/elapsed*100,before.1,after.1))
        }
        let originalPIDs = host.runningProcessIDs
        let originalInstance = host.instanceID(entry.id)
        try store.setEnabled(false, for: entry.id); await host.configure(store.entries.filter { $0.id == entry.id })
        try check(host.runningProcessIDs.isEmpty && host.drainEvents().isEmpty, "disable cleanup")
        try await Task.sleep(nanoseconds:100_000_000)
        try check(originalPIDs.allSatisfy { kill($0,0) != 0 }, "disabled process still exists in OS")
        let disabled = IntegrationPluginEntry(plugin:manifest,enabled:false,packageURL:source,isBuiltIn:false)
        _ = try await host.lifecycle(disabled,method:"inspect")
        try check(host.runningProcessIDs.isEmpty,"disabled lifecycle process leaked")
        let operation = Task { try await host.lifecycle(disabled,method:"install",params:["hang":true]) }
        for _ in 0..<30 { if !host.runningProcessIDs.isEmpty { break }; try await Task.sleep(nanoseconds:10_000_000) }
        let maintenancePIDs = host.runningProcessIDs
        try check(!maintenancePIDs.isEmpty,"disabled maintenance was not owned by host")
        host.stopAll()
        do { _ = try await operation.value; throw Failure.check("stopped maintenance succeeded") } catch let error as Failure { throw error } catch {}
        try await Task.sleep(nanoseconds:100_000_000)
        try check(maintenancePIDs.allSatisfy { kill($0,0) != 0 },"maintenance process survived host exit")
        manifest.version = "2"; try save()
        entry = try store.importPackage(at: source, replacingExisting:true)
        try check(!entry.enabled, "update preserves disabled state")
        try store.setEnabled(true, for: entry.id)
        await host.configure(store.entries.filter { $0.id == entry.id })
        try check(host.instanceID(entry.id) != originalInstance, "update replaces process generation")
        try store.remove(id: entry.id); await host.configure(store.entries.filter { $0.id == entry.id })
        try check(host.runningProcessIDs.isEmpty, "delete cleanup")
        let direct = try AdapterProcess(plugin:manifest,descriptor:manifest.adapter!,packageURL:source,environment:environment)
        do { _ = try await direct.request("visit",params:["hang":true],timeout:0.1); throw Failure.check("timeout missing") } catch let error as Failure { throw error } catch {}
        _ = try await direct.request("hello")
        do { _ = try await direct.request("visit",params:["malformed":true]); throw Failure.check("invalid frame accepted") } catch let error as Failure { throw error } catch {}
        direct.stop()
        manifest.adapter?.configuration = ["badVersion":"yes"]; try save()
        entry = try store.importPackage(at:source)
        await host.configure([entry])
        try check(host.health[entry.id]?.status == .unavailable && host.runningProcessIDs.isEmpty, "version mismatch cleanup")
        print("CharPluginHost: imported new client, monitor, visit, origin, lifecycle, update/disable/delete, timeout, malformed frame and version checks passed")
    }
}
