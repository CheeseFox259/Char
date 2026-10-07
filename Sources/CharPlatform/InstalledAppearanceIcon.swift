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
        // Same-version Release refreshes must never restore an older executable.
        let executable = app.appendingPathComponent("Contents/MacOS/Char")
        let codeIdentity = SHA256.hash(data: try buildIdentity(executable))
            .map { String(format: "%02x", $0) }.joined()
        let archive = archiveDirectory.appendingPathComponent("Char-\(version)-\(codeIdentity.prefix(16))-pristine.zip")
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
        guard plist["CFBundleIdentifier"] as? String == "com.cheesefox.char", plist["CFBundleShortVersionString"] as? String == version,
              try buildIdentity(staged.appendingPathComponent("Contents/MacOS/Char")) == buildIdentity(executable) else { throw PetSkinError.invalid("pristine backup identity mismatch") }
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
    /// LC_UUID survives resource changes and ad hoc re-signing. Include every
    /// architecture so refreshing a universal build cannot restore older code.
    static func buildIdentity(_ executable: URL) throws -> Data {
        let bytes = [UInt8](try Data(contentsOf: executable, options: .mappedIfSafe))
        func integer(_ at: Int, _ count: Int, _ big: Bool) throws -> UInt64 {
            guard at >= 0, at <= bytes.count - count else { throw PetSkinError.invalid("truncated Mach-O") }
            let slice = bytes[at..<at+count]
            return (big ? Array(slice) : Array(slice.reversed())).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        var identities: [String] = []
        func thin(_ offset: Int, _ length: Int) throws {
            guard length >= 28, offset >= 0, offset <= bytes.count - length else { throw PetSkinError.invalid("invalid Mach-O slice") }
            let magic = try integer(offset, 4, true)
            let big = magic == 0xfeedface || magic == 0xfeedfacf
            guard [0xfeedface,0xfeedfacf,0xcefaedfe,0xcffaedfe].contains(magic) else { throw PetSkinError.invalid("not a Mach-O executable") }
            let header = (magic == 0xfeedfacf || magic == 0xcffaedfe) ? 32 : 28
            let cpu = try integer(offset+4,4,big), subtype = try integer(offset+8,4,big)
            let commands = try integer(offset+16,4,big), commandBytes = try integer(offset+20,4,big)
            guard commandBytes <= length-header, commands <= commandBytes/8 else { throw PetSkinError.invalid("invalid Mach-O commands") }
            var cursor = offset+header
            for _ in 0..<commands {
                let command = try integer(cursor,4,big), size = try integer(cursor+4,4,big)
                guard size >= 8, size <= offset+header+Int(commandBytes)-cursor else { throw PetSkinError.invalid("invalid Mach-O command") }
                if command == 0x1b {
                    guard size == 24 else { throw PetSkinError.invalid("invalid Mach-O UUID") }
                    let uuid = bytes[cursor+8..<cursor+24].map { String(format:"%02x",$0) }.joined()
                    identities.append("\(cpu):\(subtype):\(uuid)")
                    return
                }
                cursor += Int(size)
            }
            throw PetSkinError.invalid("Mach-O build UUID missing")
        }
        let magic = try integer(0,4,true)
        if [0xcafebabe,0xcafebabf,0xbebafeca,0xbfbafeca].contains(magic) {
            let big = magic == 0xcafebabe || magic == 0xcafebabf
            let wide = magic == 0xcafebabf || magic == 0xbfbafeca
            let count = try integer(4,4,big), stride = wide ? 32 : 20
            guard count > 0, count <= (bytes.count-8)/stride else { throw PetSkinError.invalid("invalid fat Mach-O") }
            for index in 0..<Int(count) {
                let at = 8+index*stride
                let offset = try integer(at+8,wide ? 8 : 4,big), length = try integer(at+(wide ? 16 : 12),wide ? 8 : 4,big)
                guard offset <= UInt64(bytes.count), length <= UInt64(bytes.count)-offset else { throw PetSkinError.invalid("invalid Mach-O slice") }
                try thin(Int(offset),Int(length))
            }
        } else { try thin(0,bytes.count) }
        return Data(identities.sorted().joined(separator:"\n").utf8)
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
