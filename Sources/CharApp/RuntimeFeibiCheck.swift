import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    /// Isolated, offscreen checks of the official layered example. User acceptance
    /// of Spaces, external apps, sounds and installed icons remains manual.
    func runFeibiCheck() async throws {
        func require(_ value: Bool, _ message: String) throws { if !value { throw PetSkinError.invalid(message) } }
        guard demo, let skinStore, let source = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_PACKAGE"],
              let destination = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_OUTPUT"] else { throw PetSkinError.invalid("isolated example required") }
        let output = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories:true)
        presentationTracing = true
        defer { appearanceScript?.stop(); try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let manifest = try skinStore.importPackage(at:URL(fileURLWithPath:source))
        selectSkin(manifest.id)
        // The pointer path receives surface coordinates, unlike direct local
        // hit tests. Exercise a displaced pet as laid out in the real panel.
        setPetSize(48)
        let hitPet = GraphicButton(kind:.pet,runtime:self)
        hitPet.frame = NSRect(x:120,y:100,width:48,height:48)
        hitPet.presentPetFrame(hitPet.frame)
        try require(hitPet.containsInteractivePoint(NSPoint(x:24,y:24)),"local pet center must be interactive")
        try require(hitPet.containsSurfacePoint(NSPoint(x:144,y:124)),"surface pet center must accept clicks and drags")
        let surfaceLayer = CALayer(), scene = CALayer()
        surfaceLayer.addSublayer(scene); hitPet.attachArtwork(to:scene)
        scene.setAffineTransform(CGAffineTransform(a:0.8,b:0,c:0,d:0.8,tx:17,ty:-11))
        try require(hitPet.containsSurfacePoint(NSPoint(x:132.2,y:88.2)),"transformed scene must preserve pet hit region")
        try require(!hitPet.containsSurfacePoint(NSPoint(x:5,y:5)),"blank surface must pass clicks through")
        panel.surface.prepareSpaceAppearance()
        panel.surface.spaceFeedback()
        try await Task.sleep(nanoseconds:120_000_000)
        try require(panel.surface.pet.clip == "idle","Space appearance must not stack the package arrival over the shared scene arrival")
        let pet = GraphicButton(kind:.pet,runtime:self)
        func raster(_ clip: String, _ elapsed: Double, _ placement: PetPlacement, _ size: Double) -> Data? {
            setPetSize(size); pet.frame = NSRect(x:0,y:0,width:size,height:size)
            pet.placement = placement; pet.clip = clip; pet.clipElapsed = elapsed; pet.feedbackElapsed = nil
            pet.refreshPetArtwork(); return pet.artworkPixelData
        }
        var checks = 0
        for theme in ["day","night"] {
            setAppearanceTheme(theme)
            for size in [36.0,48.0,88.0] {
                for placement in PetPlacement.allCases {
                    let pose = manifest.pose(placement:placement.rawValue,theme:theme)
                    let rest = raster("idle",0,placement,size)
                    try require(rest != nil,"missing idle artwork")
                    checks += 1
                    if placement != .desktop {
                        let peek = pose.clips["edgePeek"]!
                        try require(rest == raster("edgePeek",Double(peek.frames.count-1)/peek.fps,placement,size),"edge settling seam: \(theme)/\(placement)/\(size)")
                    }
                    for (clip,time) in [("depart",100.0),("arrive",0),("edgeHide",100.0),("edgePeek",0)] {
                        let data = raster(clip,time,placement,size)!
                        try require(data.allSatisfy { $0 == 0 },"transparent frame retains layers: \(theme)/\(placement)/\(clip)")
                    }
                    _ = raster("idle",0,placement,size)
                    if let cg = pet.artworkCGImage {
                        try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(theme)-\(placement)-\(Int(size)).png"))
                    }
                }
            }
        }
        setAppearanceTheme("day")
        for placement in PetPlacement.allCases {
            pet.gaze = .zero
            let center = raster("idle",0,placement,48)
            for gaze in [NSPoint(x:-1,y:0), NSPoint(x:1,y:0), NSPoint(x:0,y:-1), NSPoint(x:0,y:1),
                         NSPoint(x:-1,y:-1), NSPoint(x:1,y:-1), NSPoint(x:-1,y:1), NSPoint(x:1,y:1)] {
                pet.gaze = authoredGaze(gaze, placement: placement)
                try require(center != raster("idle",0,placement,48), "48pt gaze did not change pixels: \(placement)/\(gaze)")
            }
        }
        pet.gaze = .zero
        let open = raster("idle",0,.desktop,88)
        try require(open != raster("idle",35.0/30,.desktop,88),"blink state did not change pixels")
        // The same empty edge PNG must still repaint when tracking metadata changes.
        try require(raster("edgePeek",0.04,.left,48) != raster("edgePeek",0.12,.left,48),"tracking frame cache retained old layers")
        pet.reducedMotion = true
        try require(raster("idle",0,.desktop,48) == raster("idle",0,.desktop,48),"reduced motion frame must remain stable")
        pet.reducedMotion = false
        // Verify the real scene clip separately from the light outside it.
        setPetSize(48)
        for edge in [PetPlacement.left,.right,.top,.bottom] {
            let previous = petPlacement
            let motion = CompanionPlayback(departure:customPetClipDuration(clip:previous == .desktop ? "depart" : "edgeHide",placement:previous),
                                           arrival:customPetClipDuration(clip:"edgePeek",placement:edge))
            setPlacement(edge)
            try await Task.sleep(nanoseconds:UInt64((motion.duration+0.1)*1_000_000_000))
            let surface = panel.surface
            try require(surface.pet.clip == "idle" && surface.visualOpacity == 1,"edge scene sampled before placement settled")
            guard let root = surface.layer else { throw PetSkinError.invalid("missing native scene") }
            let pixels = Int(surface.bounds.width*2)
            guard let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,
                                          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PetSkinError.invalid("scene bitmap unavailable") }
            context.scaleBy(x:2,y:2); root.render(in:context)
            guard let image = context.makeImage() else { throw PetSkinError.invalid("scene capture failed") }
            try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("scene-\(edge).png"))
            let area = panel.screen!.visibleFrame
            let edgePoint: NSPoint
            switch edge {
            case .left: edgePoint = NSPoint(x:area.minX-panel.frame.minX,y:surface.pet.frame.midY+35)
            case .right: edgePoint = NSPoint(x:area.maxX-panel.frame.minX,y:surface.pet.frame.midY+35)
            case .top: edgePoint = NSPoint(x:surface.pet.frame.midX+35,y:area.maxY-panel.frame.minY)
            default: edgePoint = NSPoint(x:surface.pet.frame.midX+35,y:area.minY-panel.frame.minY)
            }
            try require(surface.hitTest(edgePoint) == nil,"edge boundary intercepted desktop input")
        }
        let executable = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("char-appearance-script")
        let script = try AppearanceScriptHost(executable:executable,source:String(contentsOf:URL(fileURLWithPath:source).appendingPathComponent("behavior.js")))
        defer { script.stop() }
        let event = ["name":"attention","workEnd":"fixture","state":"approval"]
        let first = try await script.event(event), duplicate = try await script.event(event)
        try require(first.first?.value == "curious" && duplicate.isEmpty,"script did not deduplicate attention")
        let hover = try await script.event(["name":"hoverEnter"])
        try require(hover.first?.value == "focus","hover focus missing")
        let leave = try await script.event(["name":"hoverLeave"])
        try require(leave.first?.value == "idle","hover leave did not restore idle")
        script.stop()
        // Exercise actual layer conversions at the maximum age size.
        let bubble = GraphicButton(kind: .bubble(.claudeCode), runtime: self)
        bubble.frame = NSRect(x:100,y:100,width:44,height:44)
        bubble.presentBubble(frame:bubble.frame,miniature:false,visible:true,animated:false,orbitCenter:.zero)
        let root = CALayer(), bubbleHost = CALayer(); root.addSublayer(bubbleHost); bubble.attachArtwork(to:bubbleHost)
        _ = bubble.setAgeScale(1.5)
        try require(bubble.containsSurfacePoint(NSPoint(x:153,y:122)), "grown bubble rim cannot receive clicks")
        try require(!bubble.containsSurfacePoint(NSPoint(x:157,y:122)), "outside grown bubble did not pass through")
        try require(abs(bubble.presentationFrame.width-66)<0.01, "grown bubble geometry is not66pt")
        setPetSize(48); setPlacement(.desktop)
        try await Task.sleep(nanoseconds:1_200_000_000)
        // Edge checks finish near a screen margin. Start this regression in
        // the actual desktop middle, where a small drag is not clamped.
        let desktop = panel.screen!.visibleFrame
        panel.setFrame(NSRect(x:desktop.midX-210,y:desktop.midY-210,width:420,height:420),display:true)
        saveDraggedPosition()
        let dragged = panel.frame.offsetBy(dx:20,dy:15)
        panel.surface.beginDrag(); panel.setFrame(dragged,display:true); saveDraggedPosition()
        try require(panel.surface.visualOpacity == 1 && panel.surface.pet.clip == "idle", "desktop drag commit replayed migration")
        try await Task.sleep(nanoseconds:100_000_000)
        try require(panel.frame == dragged, "desktop drag commit reverted its location")
        try require(presentationTraceCount > 0, "diagnostic notification timeline was not recorded")
        try Data(contentsOf:presentationTraceURL).write(to:output.appendingPathComponent("presentation-trace.log"))
        presentationTracing = false
        for language in AppLanguage.allCases {
            setLanguage(language); settings.collapsedSettingsSections = ["general","appearance","return","plugins","performance"]
            showSettings()
            try await Task.sleep(nanoseconds:100_000_000)
            if let view = settingsWindow?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("settings-\(language.rawValue).png"))
            }
            settingsWindow?.close()
        }
        // Native playback probe is silent; verifies delegate completion and category priority.
        let probe = CompanionAudio(), epoch = Date(timeIntervalSince1970:1)
        let reminders = AttentionRouter(startedAt:epoch,settings:CharSettings(filterSeconds:0))
        reminders.ingest([StopReason.question,.failure,.turnEnded].enumerated().map { index,reason in
            ObservationEvent(key:SessionKey(workEnd:.pi,nativeID:"audio-\(index)"),target:SessionTarget(bundleIdentifier:"fixture-only"),timestamp:epoch,state:.stopped(reason))
        })
        reminders.advance(to:epoch); reminders.advance(to:epoch.addingTimeInterval(0.25))
        guard let tone = NSSound(named:NSSound.Name("Ping")) else { throw PetSkinError.invalid("native sound fixture unavailable") }
        try require(probe.interaction(id:"touch",sound:tone,volume:0,cooldown:0),"initial interaction playback failed")
        try require(probe.interaction(id:"touch",sound:tone,volume:0,cooldown:0),"zero cooldown did not interrupt")
        probe.enqueue(reminders.drainEffects().map { CompanionAudio.Request(notices:$0.notices,resolve:{(tone,0)},isValid:{_ in true}) })
        try require(probe.currentGroup == .interaction,"attention did not preempt interaction")
        try require(probe.interaction(id:"touch",sound:tone,volume:0,cooldown:0),"suppressed click must retain visual success")
        var groups:[AttentionPresentationGroup] = [.interaction]
        let deadline = ProcessInfo.processInfo.systemUptime+5
        while probe.isPlayingAttention && ProcessInfo.processInfo.systemUptime<deadline {
            if let group = probe.currentGroup, groups.last != group { groups.append(group) }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        try require(!probe.isPlayingAttention && groups == [.interaction,.issue,.ended],"native attention queue did not finish in category order")
        probe.stop()
        // One steady-state sample: same demo scene, native 30fps animation and idle helper.
        setPetSize(48); setPlacement(.desktop)
        var host = ProcessPerformanceStatistics(), helper = ProcessPerformanceStatistics()
        let helperPID = appearanceScript?.processID
        for _ in 0..<12 {
            host.record(ProcessPerformanceSample.read(ProcessInfo.processInfo.processIdentifier))
            if let helperPID { helper.record(ProcessPerformanceSample.read(helperPID)) }
            try await Task.sleep(nanoseconds:1_000_000_000)
        }
        let report: [String:Any] = ["checks":checks,"host":host.report,"script":helper.report,
            "image_cache_bytes":skinStore.cachedImageBytes,
            "conditions":"isolated demo / desktop 48pt / day / 30fps / no external clients / 12 seconds"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-check.json"))
        print("Phoebe native check passed: \(checks) theme/placement/size combinations, tracking states, transparent endpoints, dedup and performance sample")
    }
}
private extension ProcessPerformanceStatistics {
    var report: [String:Any] {
        ["cpu_average":averageCPUPercent ?? 0,"rss_mib":Double(residentBytes ?? 0)/1048576,
         "rss_average_mib":(averageResidentBytes ?? 0)/1048576,
         "footprint_average_mib":(averagePhysicalFootprintBytes ?? 0)/1048576,"samples":sampleCount]
    }
}
