import AppKit
import CryptoKit

/// Updates a writable ad hoc installation through a verified staging copy.
/// No FinderInfo/resource-fork icon is written inside the signed bundle.
public enum InstalledAppearanceIcon {
    public static func synchronize(app: URL, png: Data?, archiveDirectory: URL) throws {
        let fm = FileManager.default
        guard app.pathExtension == "app", fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else { throw PetSkinError.invalid("installation is not writable") }
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let current = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String:Any],
              let version = current["CFBundleShortVersionString"] as? String, current["CFBundleIdentifier"] as? String == "com.cheesefox.char" else { throw PetSkinError.invalid("not a Char installation") }
        if png == nil && current["CharAppearanceIcon"] == nil { return }
        let identity = png.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "default"
        guard current["CharAppearanceIcon"] as? String != identity else { return }
        // This product's public Release is ad hoc signed. Never silently replace a Developer ID signature.
        let signature = try command("/usr/bin/codesign", ["-dv",app.path])
        guard signature.contains("Signature=adhoc") else { throw PetSkinError.invalid("automatic icon sync requires an ad hoc Char installation") }
        try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let archive = archiveDirectory.appendingPathComponent("Char-\(version)-pristine.zip")
        if !fm.fileExists(atPath: archive.path) {
            guard current["CharAppearanceIcon"] == nil else { throw PetSkinError.invalid("pristine Release backup missing") }
            _ = try command("/usr/bin/ditto", ["-c","-k","--keepParent",app.path,archive.path])
        }
        let transaction = app.deletingLastPathComponent().appendingPathComponent(".char-icon-\(UUID().uuidString)")
        try fm.createDirectory(at: transaction, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: transaction) }
        _ = try command("/usr/bin/ditto", ["-x","-k",archive.path,transaction.path])
        let staged = transaction.appendingPathComponent("Char.app")
        _ = try command("/usr/bin/codesign", ["--verify","--deep","--strict",staged.path])
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: staged.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String:Any]
        guard plist["CFBundleIdentifier"] as? String == "com.cheesefox.char", plist["CFBundleShortVersionString"] as? String == version else { throw PetSkinError.invalid("pristine backup identity mismatch") }
        if let png {
            guard let source = NSBitmapImageRep(data: png), source.pixelsWide > 0 else { throw PetSkinError.invalid("icon is not a PNG") }
            let iconset = transaction.appendingPathComponent("Appearance.iconset")
            try fm.createDirectory(at: iconset, withIntermediateDirectories: false)
            let image = NSImage(size: NSSize(width: source.pixelsWide,height: source.pixelsHigh)); image.addRepresentation(source)
            for size in [16,32,128,256,512] {
                for scale in [1,2] {
                    let px = size*scale
                    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: px,pixelsHigh: px,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw PetSkinError.invalid("icon raster failed") }
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                    image.draw(in: NSRect(x: 0,y: 0,width: px,height: px), from: .zero, operation: .copy, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                    try bitmap.representation(using: .png,properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
                }
            }
            let name = "CharAppearance-" + String(identity.prefix(16))
            _ = try command("/usr/bin/iconutil", ["-c","icns",iconset.path,"-o",staged.appendingPathComponent("Contents/Resources/\(name).icns").path])
            plist["CFBundleIconFile"] = name
        }
        plist["CharAppearanceIcon"] = identity
        try PropertyListSerialization.data(fromPropertyList: plist,format: .xml,options: 0).write(to: staged.appendingPathComponent("Contents/Info.plist"),options: .atomic)
        _ = try command("/usr/bin/codesign", ["--force","--sign","-",staged.path])
        _ = try command("/usr/bin/codesign", ["--verify","--deep","--strict",staged.path])
        let rollback = transaction.appendingPathComponent("rollback")
        try fm.moveItem(at: app,to: rollback)
        do { try fm.moveItem(at: staged,to: app) }
        catch { try fm.moveItem(at: rollback,to: app); throw error }
        // A changed resource name also invalidates LaunchServices' cached icon identity.
        _ = try? command("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f",app.path])
    }
    private static func command(_ path: String, _ args: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output = String(decoding: data,as: UTF8.self)
        guard process.terminationStatus == 0 else { throw PetSkinError.invalid("\(URL(fileURLWithPath: path).lastPathComponent): \(output.prefix(500))") }
        return output
    }
}
