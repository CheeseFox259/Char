import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    /// Compare identical authored pixels across the actual renderer's clip boundary.
    /// Different file identities ensure the idle redraw also exercises the texture cache.
    func runAppearanceEdgeCheck() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw PetSkinError.invalid(message) }
        }
        guard demo, let skinStore,
              let path = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_PACKAGE"] else {
            throw PetSkinError.invalid("isolated profile and CHAR_APPEARANCE_CHECK_PACKAGE required")
        }
        let root = store.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: path)
        let sourceManifest = try PetSkinStore.validatePackage(at: source)
        let fixture = root.appendingPathComponent("edge-regression.charpet")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let bytes = try Data(contentsOf: source.appendingPathComponent(sourceManifest.clips["idle"]!.frames[0]))
        for name in ["pose.png", "next.png"] { try bytes.write(to: fixture.appendingPathComponent(name)) }
        let clips = Dictionary(uniqueKeysWithValues: PetSkinClip.allCases.map {
            ($0.rawValue, PetSkinAnimation(frames: ["pose.png", "next.png"], fps: 24))
        })
        let manifest = PetSkinManifest(id: "fixture.edge-regression", name: "Edge regression",
                                      canvasSize: sourceManifest.canvasSize, anchor: sourceManifest.anchor, clips: clips)
        try JSONEncoder().encode(manifest).write(to: fixture.appendingPathComponent("manifest.json"))
        _ = try skinStore.importPackage(at: fixture)
        selectSkin(manifest.id)
        try require(sourceBadgeAnchor == nil && sourceBadgeOpacity == 0, "unexpected origin badge in isolated fixture")
        router.clearNavigationFeedback(); publish()
        for size in [36.0, 48.0, 88.0] {
            setPetSize(size)
            for placement in PetPlacement.allCases {
                let pet = GraphicButton(kind: .pet, runtime: self)
                pet.frame = NSRect(x: 0, y: 0, width: size, height: size)
                pet.placement = placement
                pet.clip = "edgePeek"; pet.clipElapsed = 0
                pet.refreshPetArtwork()
                guard let peek = pet.artworkPixelData else { throw PetSkinError.invalid("missing peek raster") }
                pet.clip = "idle"; pet.clipElapsed = 1.0 / 24
                pet.refreshPetArtwork()
                try require(pet.artworkPixelData == peek, "\(placement) \(size)pt changed orientation on edgePeek → idle")
                for clip in ["press", "return", "edgeHide"] {
                    pet.feedbackClip = clip; pet.feedbackElapsed = 0
                    pet.refreshPetArtwork()
                    try require(pet.artworkPixelData == peek, "\(placement) changed orientation during \(clip)")
                }
            }
        }
        deleteSkin(manifest.id)
        let actual = try skinStore.importPackage(at: source)
        selectSkin(actual.id); setPetSize(48)
        for placement in [PetPlacement.top, .left, .right, .bottom] {
            setPlacement(placement)
            let deadline = ProcessInfo.processInfo.systemUptime
                + (customPetClipDuration(clip: "edgeHide") ?? 0)
                + (customPetClipDuration(clip: "edgePeek") ?? 0) + 0.5
            while (panel.surface.pet.placement != placement || panel.surface.pet.clip != "idle"),
                  ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(petPlacement == placement && panel.surface.pet.placement == placement,
                        "\(placement) placement reverted after arrival")
            try require(panel.surface.pet.clip == "idle", "\(placement) did not settle to idle")
            if let output = ProcessInfo.processInfo.environment["CHAR_APPEARANCE_CHECK_OUTPUT"],
               let screen = panel.screen {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let visible = panel.frame.intersection(screen.visibleFrame)
                let rect = visible.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
                let image = NSImage(size: rect.size, flipped: false) { _ in
                    guard let context = NSGraphicsContext.current?.cgContext else { return false }
                    context.translateBy(x: -rect.minX, y: -rect.minY)
                    self.panel.surface.layer?.render(in: context)
                    return true
                }
                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    throw PetSkinError.invalid("missing \(placement) layer snapshot")
                }
                try png.write(to: directory.appendingPathComponent("\(placement.rawValue).png"))
            }
        }
        print("Char appearance edge check passed: identical pixels through peek/idle/feedback/hide, five placements at 36/48/88pt; actual \(actual.id) settles on all four edges")
    }
}
