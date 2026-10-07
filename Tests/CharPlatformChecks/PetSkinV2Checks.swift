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
    try InstalledAppearanceIcon.synchronize(app: app,png: Data(contentsOf: package.appendingPathComponent("icon.png")),archiveDirectory: archive)
    let changed = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),format: nil) as! [String:Any]
    assert((changed["CFBundleIconFile"] as! String).hasPrefix("CharAppearance-"))
    try InstalledAppearanceIcon.synchronize(app: app,png: nil,archiveDirectory: archive)
    let reset = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),format: nil) as! [String:Any]
    assert(reset["CFBundleIconFile"] as? String == "original" && reset["CharAppearanceIcon"] as? String == "default")
    print("Appearance v2: variant/theme/cache/behavior/action/budget and signed icon restoration passed")
}
