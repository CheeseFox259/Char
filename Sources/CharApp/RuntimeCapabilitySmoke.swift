import AppKit
import CharCore
import CharPluginHost
import CharPlatform

extension CompanionRuntime {
    func runCapabilitySmoke() async throws {
        guard demo, let store = pluginStore, let host = capabilityHost else { throw AdapterFailure.unavailable("Fixture host missing") }
        let directory = self.store.fileURL.deletingLastPathComponent().appendingPathComponent("independent.charintegration")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let end = WorkEnd(rawValue:"fixture.independent.desktop")!
        var manifest = IntegrationPlugin(schemaVersion:3,id:"fixture.independent",name:"Independent fixture",workEnd:end,
            bundleIdentifier:"com.example.independent",version:"1",clientInterface:.cli,
            adapter:AdapterDescriptor(runtime:.node,entrypoint:"adapter.mjs",capabilities:[.monitor,.visit,.origin,.lifecycle]))
        let script = #"""
        import {createInterface} from 'node:readline';
        let active=false;
        createInterface({input:process.stdin}).on('line',line=>{
          const r=JSON.parse(line),p=r.params||{};let result={};
          switch(r.method){
            case 'hello':result={protocolVersion:1};break;
            case 'inspect':result={status:'ready'};break;
            case 'start':console.log(JSON.stringify({version:1,event:{workEnd:process.env.CHAR_WORK_END,nativeID:'fixture-root',timestamp:new Date().toISOString(),state:'stopped',reason:'question'}}));break;
            case 'capture':result={token:'fixture-opaque',processID:p.processID};break;
            case 'check':result={valid:true,active};break;
            case 'focus':active=true;result={outcome:'exact',verified:true};break;
            case 'visit':result={outcome:'exact',verified:true};break;
            case 'install':case 'update':case 'uninstall':result={status:'reloadRequired'};break;
          }
          console.log(JSON.stringify({version:1,id:r.id,result}));
        });
        """#
        try Data(script.utf8).write(to:directory.appendingPathComponent("adapter.mjs"))
        func save() throws { try JSONEncoder().encode(manifest).write(to:directory.appendingPathComponent("manifest.json")) }
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw AdapterFailure.unavailable(message) } }
        try save(); _ = try store.importPackage(at:directory);reloadPlugins()
        for _ in 0..<30 {
            if host.health[manifest.id]?.status == .ready { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        router.ingest(host.drainEvents());router.advance(to:Date());publish()
        try require(snapshot.bubbles.contains { $0.workEnd == end && $0.count == 1 },"Imported custom monitor did not reach app router")
        try require(panel.surface.buttons.contains { $0.renderedWorkEnd == end },"Dynamic bubble was not constructed")
        if CommandLine.arguments.contains("--capability-preview") {
            showSettings()
            print("Char capability preview ready; isolated profile; waiting 90 seconds")
            fflush(stdout)
            try await Task.sleep(nanoseconds:90_000_000_000)
            settingsWindow?.close()
        }
        // The optional preview is interactive: a click may have acknowledged its item.
        if router.nextVisit(for:end) == nil {
            let key = SessionKey(workEnd:end,nativeID:"fixture-after-preview")
            router.ingest([ObservationEvent(key:key,target:SessionTarget(bundleIdentifier:manifest.bundleIdentifier),timestamp:Date(),state:.stopped(.question))])
            router.advance(to:Date());publish()
        }
        guard let item = router.nextVisit(for:end) else { throw AdapterFailure.unavailable("Fixture attention missing") }
        let target = item.target
        let outcome = await visitCapability(end,target:target)
        try require(outcome == .exact,"Custom visit failed")
        let source = ForegroundSnapshot(bundleIdentifier:manifest.bundleIdentifier,processID:12345)
        guard let anchor = await captureCapabilityOrigin(from:source) else { throw AdapterFailure.unavailable("Custom capture failed") }
        router.completeVisit(key:item.key,outcome:outcome,sourceAnchor:anchor,at:Date());publish()
        try require(snapshot.hold?.anchor.id == anchor.id,"First origin not retained")
        let returned = await returnToOrigin(anchor)
        try require(returned == .exact,"Custom return verification failed")
        router.completeReturn(outcome:returned);publish()
        try require(snapshot.hold == nil,"Return did not release origin")
        setPlugin(manifest.id,enabled:false)
        await host.configure(pluginEntries.map(effectiveCapabilityEntry))
        try require(host.instanceID(manifest.id) == nil && !snapshot.bubbles.contains { $0.workEnd == end },"Disable left custom state")
        manifest.version = "2";try save();_ = try store.importPackage(at:directory,replacingExisting:true);reloadPlugins()
        try require(pluginEntries.first { $0.id == manifest.id }?.enabled == false,"Update changed user enable state")
        setPlugin(manifest.id,enabled:true)
        for _ in 0..<30 {
            if host.instanceID(manifest.id) != nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        _ = try await host.request(manifest.id,method:"inspect")
        guard let second = await captureCapabilityOrigin(from:source) else { throw AdapterFailure.unavailable("Updated capture failed") }
        let key = SessionKey(workEnd:end,nativeID:"remove-held-origin")
        router.ingest([ObservationEvent(key:key,target:target,timestamp:Date(),state:.stopped(.approval))]);router.advance(to:Date())
        router.completeVisit(key:key,outcome:.exact,sourceAnchor:second,at:Date());publish()
        deletePlugin(manifest.id);await host.configure(pluginEntries.map(effectiveCapabilityEntry))
        for _ in 0..<30 {
            if router.snapshot.hold == nil { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        publish()
        try require(host.instanceID(manifest.id) == nil && snapshot.hold == nil,"Delete retained adapter or anchor")
        try require(!panel.surface.buttons.contains { $0.renderedWorkEnd == end },"Deleted client retained artwork")
        print("Char capability fixture: dynamic import → native bubble → visit → exact origin → return → disable/update/delete passed; navigation simulated")
    }
}
