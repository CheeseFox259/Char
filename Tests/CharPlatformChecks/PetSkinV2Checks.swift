import AppKit
import Foundation
import CharCore
import CharPlatform

@MainActor func petSkinV2Checks() throws {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("char-v2-check-\(UUID().uuidString)")
    try fm.createDirectory(at: root,withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let package = root.appendingPathComponent("fixture.charpet")
    let generator = Process(); generator.executableURL = URL(fileURLWithPath: "/usr/bin/env"); generator.arguments = ["python3",project.appendingPathComponent("scripts/make-appearance-fixture.py").path,package.path]
    try generator.run(); generator.waitUntilExit(); assert(generator.terminationStatus == 0)
    let manifest = try PetSkinStore.validatePackage(at: package)
    assert(manifest.schemaVersion == 2 && manifest.features?.script == "behavior.js")
    let store = try PetSkinStore(directory: root.appendingPathComponent("store"))
    try store.importPackage(at: package); try store.select(id: manifest.id)
    let day = store.image(clip: "idle",elapsed: 0,placement: "desktop")!
    assert(day === store.image(clip: "idle",elapsed: 0,placement: "desktop"),"frame cache must reuse identity")
    let top = manifest.pose(placement: "top",theme: "day")
    assert(top.rotation == 0 && top.anchor.y == 0.3 && top.clips["idle"]?.frames.first == "alternate.png")
    assert(manifest.pose(placement: "left",theme: "day").mirrorX)
    try store.selectTheme("night")
    assert(store.image(clip: "idle",elapsed: 0,placement: "desktop") !== day,"theme did not switch resource")
    try store.setBehaviorEnabled(false)
    let restored = try PetSkinStore(directory: root.appendingPathComponent("store"))
    assert(restored.selectedTheme == "night" && !restored.behaviorEnabled)
    assert(restored.icon(for: manifest.id) != nil)
    try store.selectTheme("")
    let baseReload = try PetSkinStore(directory: root.appendingPathComponent("store"))
    assert(baseReload.selectedTheme == nil,"explicit base theme must survive restart")
    let jsonURL = package.appendingPathComponent("manifest.json")
    let original = try Data(contentsOf: jsonURL)
    func rejects(_ mutate: (inout [String:Any]) -> Void) throws {
        var json = try JSONSerialization.jsonObject(with: original) as! [String:Any]
        mutate(&json); try JSONSerialization.data(withJSONObject: json).write(to: jsonURL)
        do { _ = try PetSkinStore.validatePackage(at: package); assertionFailure("invalid v2 package accepted") }
        catch { }
        try original.write(to: jsonURL)
    }
    try rejects { var f = $0["features"] as! [String:Any]; f["script"] = "../escape.js"; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["eyeFollow"] = true; $0["features"] = f }
    try rejects { $0["features"] = ["bindings":["frame":[["type":"shell","value":"ls"]]]] }
    try rejects { $0["features"] = ["bindings":["click":[["type":"showSettings","value":"bad"]]]] }
    try rejects { var f = $0["features"] as! [String:Any]; f["bubbles"] = ["hoverAmplitude":0.8]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["defaultTheme"] = "missing"; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["variants"] = ["top":["anchor":["x":2,"y":0.5]]]; $0["features"] = f }
    try rejects { var clips = $0["clips"] as! [String:Any]; var idle = clips["idle"] as! [String:Any]; idle["trackingFrames"] = [["opacity":0]]; clips["idle"] = idle; $0["clips"] = clips }
    try rejects { var clips = $0["clips"] as! [String:Any]; var idle = clips["idle"] as! [String:Any]; idle["trackingFrames"] = [["state":"absent"],["state":"absent"]]; clips["idle"] = idle; $0["clips"] = clips }
    try rejects { var clips = $0["clips"] as! [String:Any]; var idle = clips["idle"] as! [String:Any]; idle["trackingFrames"] = [["transform":[1,0,0,1]],["opacity":2]]; clips["idle"] = idle; $0["clips"] = clips }
    var pooled = try JSONSerialization.jsonObject(with: original) as! [String:Any]
    var pooledFeatures = pooled["features"] as! [String:Any]
    pooledFeatures["sounds"] = ["interaction":["files":["tone.wav"],"cooldown":0,"volume":0.4]]
    pooledFeatures["soundBindings"] = ["interaction":"interaction", "petClick":"interaction"]
    pooledFeatures["edgeBoundary"] = ["width":1.3,"thickness":1.2,"opacity":0.55,"glowOpacity":0.12,"glowRadius":4]
    pooled["features"] = pooledFeatures
    try JSONSerialization.data(withJSONObject: pooled).write(to: jsonURL)
    let pooledManifest = try PetSkinStore.validatePackage(at: package)
    assert(pooledManifest.features?.sounds?["interaction"]?.paths == ["tone.wav"])
    assert(pooledManifest.features?.edgeBoundary?.width == 1.3)
    try original.write(to: jsonURL)
    try rejects { var f = $0["features"] as! [String:Any]; f["sounds"] = ["bad":["file":"tone.wav","files":["tone.wav"]]]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["sounds"] = ["bad":["files":[]]]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["soundBindings"] = ["issue":"missing"]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["sounds"] = ["bad":["files":["../escape.wav"]]]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["edgeBoundary"] = ["glowOpacity":0.8]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["edgeBoundary"] = ["width":4]; $0["features"] = f }
    try rejects { var f = $0["features"] as! [String:Any]; f["edgeBoundary"] = ["unknown":1]; $0["features"] = f }
    let timeline = PetSkinAnimation(frames:["a","b","c"],fps:30)
    assert(timeline.frameIndex(elapsed:0,looping:false) == 0)
    assert(timeline.frameIndex(elapsed:1.0/30,looping:false) == 1)
    assert(timeline.frameIndex(elapsed:1,looping:false) == 2)
    assert(timeline.frameIndex(elapsed:0.1,looping:true) == 0)
    try store.delete(id: manifest.id)
    assert(store.selectedSkin.id == PetSkinStore.defaultID && store.resourceURL("behavior.js") == nil)
    // Real icon staging/signing/restoration, only on a disposable bundle.
    let app = root.appendingPathComponent("Char.app"), resources = app.appendingPathComponent("Contents/Resources"), macOS = app.appendingPathComponent("Contents/MacOS")
    try fm.createDirectory(at: resources,withIntermediateDirectories: true); try fm.createDirectory(at: macOS,withIntermediateDirectories: true)
    try fm.copyItem(at: URL(fileURLWithPath: "/bin/echo"),to: macOS.appendingPathComponent("Char"))
    let plist: [String:Any] = ["CFBundleIdentifier":"com.cheesefox.char","CFBundleExecutable":"Char","CFBundleName":"Char","CFBundlePackageType":"APPL","CFBundleShortVersionString":"fixture","CFBundleVersion":"1","CFBundleIconFile":"original"]
    try PropertyListSerialization.data(fromPropertyList: plist,format: .xml,options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); sign.arguments = ["--force","--sign","-",app.path]; try sign.run(); sign.waitUntilExit(); assert(sign.terminationStatus == 0)
    let archive = root.appendingPathComponent("backups")
    let originalCode = try Data(contentsOf: macOS.appendingPathComponent("Char"))
    try InstalledAppearanceIcon.synchronize(app: app,png: Data(contentsOf: package.appendingPathComponent("icon.png")),archiveDirectory: archive)
    let changed = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),format: nil) as! [String:Any]
    assert((changed["CFBundleIconFile"] as! String).hasPrefix("CharAppearance-"))
    try InstalledAppearanceIcon.synchronize(app: app,png: nil,archiveDirectory: archive)
    let reset = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),format: nil) as! [String:Any]
    assert(reset["CFBundleIconFile"] as? String == "original" && reset["CharAppearanceIcon"] as? String == "default")
    let archives = try fm.contentsOfDirectory(atPath:archive.path)
    assert(archives.count == 1,"re-signing must reuse one pristine archive")
    // Restoration must restore code from the matching build, never a same-version predecessor.
    let restoredCode = try Data(contentsOf: macOS.appendingPathComponent("Char"))
    assert(originalCode.count == restoredCode.count)
    try fm.removeItem(at:macOS.appendingPathComponent("Char"))
    try fm.copyItem(at:URL(fileURLWithPath:"/bin/cat"),to:macOS.appendingPathComponent("Char"))
    try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
    let signNew = Process(); signNew.executableURL = URL(fileURLWithPath:"/usr/bin/codesign"); signNew.arguments = ["--force","--sign","-",app.path]; try signNew.run(); signNew.waitUntilExit()
    try InstalledAppearanceIcon.synchronize(app:app,png:Data(contentsOf:package.appendingPathComponent("icon.png")),archiveDirectory:archive)
    try InstalledAppearanceIcon.synchronize(app:app,png:nil,archiveDirectory:archive)
    let newCode = try Data(contentsOf:macOS.appendingPathComponent("Char"))
    assert(newCode.count != restoredCode.count,"same-version new build restored previous executable")
    let refreshedArchives = try fm.contentsOfDirectory(atPath:archive.path)
    assert(refreshedArchives.count == 2,"different build must create its own archive")
    print("Appearance v2: variant/theme/cache/behavior/action/budget and signed icon restoration passed")
}
