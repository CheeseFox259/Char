import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    func runAppearanceV2Check() async throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw PetSkinError.invalid(message) } }
        guard demo, let skinStore, let path = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_PACKAGE"] else { throw PetSkinError.invalid("isolated fixture required") }
        let root = store.fileURL.deletingLastPathComponent()
        defer { appearanceScript?.stop(); try? FileManager.default.removeItem(at: root) }
        let manifest = try skinStore.importPackage(at: URL(fileURLWithPath: path))
        selectSkin(manifest.id)
        let pet = GraphicButton(kind: .pet,runtime: self); pet.frame = NSRect(x: 0,y: 0,width: 76,height: 76)
        pet.gaze = NSPoint(x: -1,y: 0); pet.refreshPetArtwork(); let left = pet.artworkPixelData
        pet.gaze = NSPoint(x: 1,y: 0); pet.refreshPetArtwork()
        try require(left != pet.artworkPixelData,"native eye/head tracking did not change raster")
        let day = pet.artworkPixelData
        setAppearanceTheme("night"); pet.refreshPetArtwork()
        try require(day != pet.artworkPixelData,"theme change retained old raster")
        setAppearanceTheme("day")
        for placement in PetPlacement.allCases {
            pet.placement = placement; pet.feedbackElapsed = nil; pet.clip = "idle"; pet.refreshPetArtwork()
            try require(pet.artworkPixelData != nil,"missing independent edge raster")
        }
        pet.placement = .desktop
        try require(!pet.containsInteractivePoint(.zero) && pet.containsInteractivePoint(NSPoint(x: 38,y: 38)),"authored hit region not applied")
        appearanceEvent("hoverEnter",workEnd: "pi")
        try require(panel.surface.pet.feedbackClip == "celebrate","manifest binding not dispatched")
        try require(bubbleCapacity == 4 && effectiveBubbleDistance == 24,"appearance layout preferences not applied")
        setAppearanceBehavior(false)
        try require(effectiveBubbleDistance == bubbleDistance,"user behavior override did not restore preferences")
        setAppearanceBehavior(true)
        if let output = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_OUTPUT"] {
            let directory = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
            for placement in PetPlacement.allCases {
                pet.placement = placement; pet.feedbackElapsed = nil; pet.refreshPetArtwork()
                guard let image = pet.artworkCGImage else { throw PetSkinError.invalid("missing raster") }
                try NSBitmapImageRep(cgImage: image).representation(using: .png,properties: [:])!.write(to: directory.appendingPathComponent("\(placement.rawValue).png"))
            }
            for (index,button) in panel.surface.buttons.enumerated() where index < 3 {
                button.refreshArtwork()
                if let image = button.artworkCGImage { try NSBitmapImageRep(cgImage: image).representation(using: .png,properties: [:])!.write(to: directory.appendingPathComponent("bubble-\(index).png")) }
            }
        }
        try require(appearanceClick() && settingsWindow?.isVisible == true,"custom click did not open settings")
        try await Task.sleep(nanoseconds: 250_000_000)
        if let output = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_OUTPUT"],let content = settingsWindow?.contentView,
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds,to: bitmap)
            try bitmap.representation(using: .png,properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("settings.png"))
        }
        settingsWindow?.close()
        let executable = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("char-appearance-script")
        let script = try AppearanceScriptHost(executable: executable,source: "let count=0; function onEvent(e){count++; return [{type:'playClip',value:String(count)}]} ")
        let one = try await script.event(["name":"click"]), two = try await script.event(["name":"click"])
        try require(one.first?.value == "1" && two.first?.value == "2","script state not persistent"); script.stop()
        let unsafe = try AppearanceScriptHost(executable: executable,source: "function onEvent(e){return [{type:'playClip',value:[typeof require,typeof fetch,typeof process,typeof ObjC].join(',')}]} ")
        let restricted = try await unsafe.event(["name":"click"]); unsafe.stop()
        try require(restricted.first?.value == "undefined,undefined,undefined,undefined","OS bridge exposed")
        let hang = try AppearanceScriptHost(executable: executable,source: "function onEvent(e){while(true){}}")
        let start = ProcessInfo.processInfo.systemUptime
        let unexpected = try? await hang.event(["name":"click"])
        try require(unexpected == nil && ProcessInfo.processInfo.systemUptime-start < 1.5,"script deadline did not terminate helper")
        print("Char appearance v2 check passed: actual native gaze/theme/five-edge rendering, bindings/hit/layout, persistent restricted scripts and timeout")
    }
}
