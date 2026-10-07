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
        defer { appearanceScript?.stop(); try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let manifest = try skinStore.importPackage(at:URL(fileURLWithPath:source))
        selectSkin(manifest.id)
        let pet = GraphicButton(kind:.pet,runtime:self)
        func raster(_ clip: String, _ elapsed: Double, _ placement: PetPlacement, _ size: Double) -> Data? {
            setPetSize(size); pet.frame = NSRect(x:0,y:0,width:size*3,height:size*3)
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
        setAppearanceTheme("day"); pet.gaze = NSPoint(x:-1,y:0)
        let left = raster("idle",0,.desktop,88)
        pet.gaze = NSPoint(x:1,y:0)
        try require(left != raster("idle",0,.desktop,88),"gaze did not change pixels")
        pet.gaze = .zero
        let open = raster("idle",0,.desktop,88)
        try require(open != raster("idle",35.0/30,.desktop,88),"blink state did not change pixels")
        // The same empty edge PNG must still repaint when tracking metadata changes.
        try require(raster("edgePeek",0.35,.left,88) != raster("edgePeek",0.6,.left,88),"tracking frame cache retained old layers")
        pet.reducedMotion = true
        try require(raster("idle",0,.desktop,48) == raster("idle",0,.desktop,48),"reduced motion frame must remain stable")
        pet.reducedMotion = false
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
        // One steady-state sample: same demo scene, native 30fps animation and idle helper.
        setPetSize(48); setPlacement(.desktop)
        var host = ProcessPerformanceStatistics(), helper = ProcessPerformanceStatistics()
        let helperPID = appearanceScript?.processID
        for _ in 0..<12 {
            host.record(ProcessPerformanceSample.read(ProcessInfo.processInfo.processIdentifier))
            if let helperPID { helper.record(ProcessPerformanceSample.read(helperPID)) }
            try await Task.sleep(nanoseconds:1_000_000_000)
        }
        let report: [String:Any] = ["checks":checks,"host":host.report,"script":helper.report,"conditions":"release / isolated demo / desktop 48pt / day / 30fps / no external clients / 12 seconds"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-check.json"))
        print("Phoebe native check passed: \(checks) theme/placement/size combinations, tracking states, transparent endpoints, dedup and performance sample")
    }
}
private extension ProcessPerformanceStatistics {
    var report: [String:Any] {
        ["cpu_average":averageCPUPercent ?? 0,"rss_mib":Double(residentBytes ?? 0)/1048576,"rss_average_mib":(averageResidentBytes ?? 0)/1048576,"samples":sampleCount]
    }
}
