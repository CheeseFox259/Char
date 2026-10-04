import AppKit
import CharPlatform
import CharCore
import Foundation

private enum PetSkinCheckFailure: Error { case failed(String) }
private func skinRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw PetSkinCheckFailure.failed(message) }
}

/// Exercises shipped bytes, not a mocked manifest or image decoder.
@MainActor func petSkinChecks() throws {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("char-skin-check-\(UUID().uuidString)")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sample = project.appendingPathComponent("Resources/Skins/example.charpet")
    let manifest = try PetSkinStore.validatePackage(at: sample)
    try skinRequire(manifest.clips.count == 7, "shipped package lacks required clips")
    let store = try PetSkinStore(directory: temp.appendingPathComponent("store"))
    try skinRequire(store.selectedSkin.id == PetSkinStore.defaultID, "first launch default")
    try store.importPackage(at: sample)
    try store.select(id: manifest.id)
    for clip in PetSkinClip.allCases {
        try skinRequire(store.image(for: manifest.id, clip: clip, elapsed: 0) != nil, "first frame did not decode")
        try skinRequire(store.image(for: manifest.id, clip: clip, elapsed: 0.2) != nil, "animated frame did not decode")
        try skinRequire(store.image(for: manifest.id, clip: clip, elapsed: .infinity) != nil, "nonfinite time failed")
    }
    let first = store.image(for: manifest.id, clip: .idle, elapsed: 0)!.tiffRepresentation
    let next = store.image(for: manifest.id, clip: .idle, elapsed: 0.4)!.tiffRepresentation
    try skinRequire(first != next, "sample is not animated")
    let duration = Double(manifest.clips["idle"]!.frames.count) / manifest.clips["idle"]!.fps
    try skinRequire(first == store.image(for: manifest.id, clip: .idle, elapsed: duration)!.tiffRepresentation, "idle loop does not wrap")
    // A valid slow package exercises the same authored durations used by the UI phases.
    let slow = temp.appendingPathComponent("slow.charpet")
    try fm.copyItem(at: sample, to: slow)
    let manifestURL = slow.appendingPathComponent("manifest.json")
    var slowJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    slowJSON["id"] = "char.slow-check"
    var slowClips = slowJSON["clips"] as! [String: [String: Any]]
    for key in slowClips.keys { slowClips[key]!["fps"] = 1 }
    slowJSON["clips"] = slowClips
    try JSONSerialization.data(withJSONObject: slowJSON).write(to: manifestURL)
    let slowStore = try PetSkinStore(directory: temp.appendingPathComponent("slow-store"))
    let slowManifest = try slowStore.importPackage(at: slow)
    let departDuration = Double(slowManifest.clips["depart"]!.frames.count)
    let arriveDuration = Double(slowManifest.clips["arrive"]!.frames.count)
    let playback = CompanionPlayback(departure: departDuration, arrival: arriveDuration)
    let finalImage = slowStore.image(for: slowManifest.id, clip: .arrive, elapsed: playback.clipElapsed(at: playback.duration))!.tiffRepresentation
    let finalFile = NSImage(contentsOf: slow.appendingPathComponent(slowManifest.clips["arrive"]!.frames.last!))!.tiffRepresentation
    try skinRequire(finalImage == finalFile, "full slow arrival must reach authored final frame")
    try skinRequire(slowStore.image(for: slowManifest.id, clip: .arrive, elapsed: 0)!.tiffRepresentation != finalImage,
                    "slow arrival fixture must distinguish first and final poses")
    let reloaded = try PetSkinStore(directory: temp.appendingPathComponent("store"))
    try skinRequire(reloaded.selectedSkin.id == manifest.id, "selection did not survive restart")
    do { try store.importPackage(at: sample); throw PetSkinCheckFailure.failed("duplicate accepted") }
    catch PetSkinError.duplicateID {}
    do { try store.delete(id: PetSkinStore.defaultID); throw PetSkinCheckFailure.failed("deleted default") }
    catch PetSkinError.cannotDeleteDefault {}

    func reject(_ name: String, mutate: (URL) throws -> Void) throws {
        let fixture = temp.appendingPathComponent(name + ".charpet")
        try fm.copyItem(at: sample, to: fixture)
        try mutate(fixture)
        do { try store.importPackage(at: fixture); throw PetSkinCheckFailure.failed("accepted \(name)") }
        catch is PetSkinCheckFailure { throw PetSkinCheckFailure.failed("accepted \(name)") }
        catch {}
        try skinRequire(store.selectedSkin.id == manifest.id && store.skins.count == 2, "invalid import altered store")
    }
    func changeManifest(_ root: URL, edit: (inout [String: Any]) -> Void) throws {
        let url = root.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        edit(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
    try reject("version") { root in try changeManifest(root) { $0["schemaVersion"] = 2 } }
    try reject("path") { root in try changeManifest(root) { object in
        var clips = object["clips"] as! [String: Any]
        clips["idle"] = ["fps":24,"frames":["../outside.png","../outside.png"]]; object["clips"] = clips
    } }
    try reject("missing") { root in try fm.removeItem(at: root.appendingPathComponent("frames/idle-000.png")) }
    try reject("symlink") { root in
        try fm.removeItem(at: root.appendingPathComponent("frames/idle-000.png"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("frames/idle-000.png"), withDestinationURL: sample.appendingPathComponent("frames/idle-000.png"))
    }
    try reject("missingClip") { root in try changeManifest(root) { object in
        var clips = object["clips"] as! [String: Any]; clips.removeValue(forKey: "edgeHide"); object["clips"] = clips
    } }
    try reject("extraFile") { root in try Data("untrusted".utf8).write(to: root.appendingPathComponent("run.sh")) }
    let link = temp.appendingPathComponent("linked.charpet")
    try fm.createSymbolicLink(at: link, withDestinationURL: sample)
    do { _ = try PetSkinStore.validatePackage(at: link); throw PetSkinCheckFailure.failed("accepted linked package") }
    catch is PetSkinCheckFailure { throw PetSkinCheckFailure.failed("accepted linked package") }
    catch {}
    try reject("canvas") { root in try changeManifest(root) { $0["canvasSize"] = ["width":64,"height":64] } }
    try reject("rgb") { root in
        let url = root.appendingPathComponent("frames/idle-000.png")
        var data = try Data(contentsOf: url); data[25] = 2; try data.write(to: url)
    }
    try reject("rate") { root in try changeManifest(root) { object in
        var clips = object["clips"] as! [String: Any], idle = clips["idle"] as! [String: Any]
        idle["fps"] = 100; clips["idle"] = idle; object["clips"] = clips
    } }
    try store.delete(id: manifest.id)
    let afterDelete = try PetSkinStore(directory: temp.appendingPathComponent("store"))
    try skinRequire(afterDelete.selectedSkin.id == PetSkinStore.defaultID && afterDelete.skins.count == 1, "delete did not persist default fallback")
    print("Pet skins: shipped animation, import/selection/restart/delete and invalid-package checks passed")
}
