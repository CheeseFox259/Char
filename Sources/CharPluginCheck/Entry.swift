import Foundation
import CharCore
import CharPluginHost

@main struct PluginTool {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 3 && args[1] == "inspect" || args.count == 4 && args[1] == "replay" else {
            fputs("Usage: swift run char-plugin-check inspect <package>\n       swift run char-plugin-check replay <package> <events.jsonl>\n",stderr);exit(2)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("char-plugin-tool-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at:root) }
        do {
            let catalog = try IntegrationPluginStore(directory:root.appendingPathComponent("catalog"))
            for item in catalog.entries { try catalog.setEnabled(false,for:item.id) }
            let entry = try catalog.importPackage(at:URL(fileURLWithPath:args[2]))
            guard var descriptor = entry.plugin.adapter, entry.plugin.schemaVersion == 3 else { throw AdapterFailure.unavailable("Package has no process adapter; use char-package-check for configuration-only packages") }
            var plugin = entry.plugin
            var environment = ["PATH":"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME":FileManager.default.homeDirectoryForCurrentUser.path,
                               "CHAR_PLUGIN_ID":entry.id,"CHAR_WORK_END":plugin.workEnd?.rawValue ?? "", "CHAR_PLUGIN_VERSION":plugin.version ?? "1",
                               "CHAR_PLUGIN_DIRECTORY":entry.packageURL!.path,"CHAR_SUPPORT_DIRECTORY":root.path,"CHAR_HOOK_EVENTS":root.appendingPathComponent("events.jsonl").path,
                               "CHAR_HOOK_BINARY":"/Applications/Char.app/Contents/MacOS/char-hook"]
            if args[1] == "replay" {
                guard descriptor.capabilities.contains(.monitor) else { throw AdapterFailure.unavailable("Replay requires monitor capability") }
                let data = try Data(contentsOf:URL(fileURLWithPath:args[3]))
                let records = try String(decoding:data,as:UTF8.self).split(separator:"\n").map { line -> [String:Any] in
                    let record = try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any] ?? [:]
                    let event = record["event"] as? [String:Any] ?? record
                    guard event["workEnd"] as? String == plugin.workEnd?.rawValue else { throw AdapterFailure.unavailable("Replay workEnd differs from manifest") }
                    return ["version":1,"event":event]
                }
                let encoded = try JSONSerialization.data(withJSONObject:records)
                let script = """
                import {createInterface} from 'node:readline';
                const records=\(String(decoding:encoded,as:UTF8.self));
                createInterface({input:process.stdin}).on('line',l=>{const r=JSON.parse(l);if(r.method==='start')for(const e of records)console.log(JSON.stringify(e));console.log(JSON.stringify({version:1,id:r.id,result:r.method==='hello'?{protocolVersion:1}:r.method==='inspect'?{status:'ready'}:{}}));});
                """
                descriptor = AdapterDescriptor(runtime:.node,entrypoint:"replay.mjs",capabilities:[.monitor])
                plugin.adapter = descriptor
                try Data(script.utf8).write(to:entry.packageURL!.appendingPathComponent(descriptor.entrypoint))
                let process = try AdapterProcess(plugin:plugin,descriptor:descriptor,packageURL:entry.packageURL!,environment:environment)
                defer { process.stop() }
                _ = try await process.request("hello"); _ = try await process.request("start")
                let events = process.drainEvents()
                guard events.count == records.count else { throw AdapterFailure.unavailable("One or more replay events violated the wire contract") }
                let start = events.map(\.timestamp).min() ?? Date()
                let router = AttentionRouter(startedAt:start,settings:CharSettings(filterSeconds:0,soundEnabled:false))
                router.ingest(events);router.advance(to:events.map(\.timestamp).max() ?? start)
                print("REPLAY: \(events.count) valid events, \(router.snapshot.bubbles.count) bubbles, \(router.snapshot.bubbles.reduce(0){$0+$1.count}) attention items (fixture only)")
            } else {
                environment["CHAR_PLUGIN_CONFIG"] = String(data:try JSONSerialization.data(withJSONObject:descriptor.configuration ?? [:]),encoding:.utf8)
                let process = try AdapterProcess(plugin:plugin,descriptor:descriptor,packageURL:entry.packageURL!,environment:environment)
                defer { process.stop() }
                let hello = try await process.request("hello")
                guard hello["protocolVersion"] as? Int == 1 else { throw AdapterFailure.unavailable("Adapter protocol mismatch") }
                let inspected = try await process.request("inspect")
                guard let raw = inspected["status"] as? String, PluginReadiness(rawValue:raw) != nil else { throw AdapterFailure.unavailable("Invalid readiness response") }
                print("PROTOCOL VALID: \(entry.id), readiness=\(raw); no install/start/navigation was requested")
            }
        } catch { fputs("FAILED: \(error)\n",stderr);exit(1) }
    }
}
