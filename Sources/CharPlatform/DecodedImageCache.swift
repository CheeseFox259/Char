import AppKit
import ImageIO
import CryptoKit

/// Main-thread image cache. Owns one explicit 8-bit bitmap per entry, without
/// AppKit's implicit high-resolution drawing caches. Shared owners are not apportioned.
public final class DecodedImageCache {
    private struct Entry {
        let image: NSImage
        let bytes: Int
        var owners: Set<String>
        var access: UInt64
    }
    private var entries: [String:Entry] = [:]
    private struct FileKey { let hash: String; let maxDimension: Int }
    private var fileKeys: [URL:FileKey] = [:]
    private var access: UInt64 = 0
    public let budget: Int
    public private(set) var bytes = 0
    public var sharedBytes: Int { entries.values.filter { $0.owners.count > 1 }.reduce(0) { $0+$1.bytes } }
    public init(budget: Int) { self.budget = max(0,budget) }
    public func usage(owner: String) -> (bytes: Int, shared: Int) {
        entries.values.filter { $0.owners.contains(owner) }.reduce((0,0)) {
            ($0.0+$1.bytes,$0.1+($1.owners.count > 1 ? $1.bytes:0))
        }
    }
    public func removeAll() { entries.removeAll(); fileKeys.removeAll(); bytes = 0 }
    public func remove(owner: String) {
        for key in Array(entries.keys) {
            guard var entry = entries[key] else { continue }
            entry.owners.remove(owner)
            if entry.owners.isEmpty { entries.removeValue(forKey:key); bytes -= entry.bytes }
            else { entries[key] = entry }
        }
        fileKeys.removeAll()
    }
    public func retainOwners(_ owners: Set<String>) {
        for key in Array(entries.keys) {
            entries[key]?.owners.formIntersection(owners)
            if entries[key]?.owners.isEmpty == true, let old = entries.removeValue(forKey:key) { bytes -= old.bytes }
        }
        fileKeys.removeAll()
    }
    public func removeOwners(prefix: String, except: String? = nil) {
        for key in Array(entries.keys) {
            guard var entry = entries[key] else { continue }
            entry.owners = entry.owners.filter { !$0.hasPrefix(prefix) || $0 == except }
            if entry.owners.isEmpty { entries.removeValue(forKey:key); bytes -= entry.bytes }
            else { entries[key] = entry }
        }
        fileKeys.removeAll()
    }
    public func image(at url: URL, maxPixels: Int, owner: String) -> NSImage? {
        let source = url.standardizedFileURL
        let data: Data?
        let identity: FileKey
        if let key = fileKeys[source] { identity = key; data = nil }
        else {
            guard let loaded = try? Data(contentsOf:source),
                  let imageSource = CGImageSourceCreateWithData(loaded as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource,0,nil) as? [CFString:Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            identity = FileKey(hash:SHA256.hash(data:loaded).map { String(format:"%02x",$0) }.joined(),maxDimension:max(width,height))
            fileKeys[source] = identity; data = loaded
        }
        let pixels = min(max(1,maxPixels),identity.maxDimension)
        return image(key:identity.hash,maxPixels:pixels,owner:owner) {
            autoreleasepool {
                guard let loaded = data ?? (try? Data(contentsOf:source)),
                      let source = CGImageSourceCreateWithData(loaded as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[
                        kCGImageSourceCreateThumbnailFromImageAlways:true,
                        kCGImageSourceThumbnailMaxPixelSize:pixels,
                        kCGImageSourceCreateThumbnailWithTransform:true,
                        kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
                return Self.bitmap(cg:cg)
            }
        }
    }
    public func image(key: String, maxPixels: Int, owner: String, load: () -> NSImage?) -> NSImage? {
        let key = key+"/\(max(1,maxPixels))"
        access &+= 1
        if var entry = entries[key] {
            entry.owners.insert(owner); entry.access = access; entries[key] = entry
            return entry.image
        }
        guard let image = load(), let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        let count = cg.bytesPerRow*cg.height
        guard count <= budget else { return image }
        while bytes+count > budget, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key {
            bytes -= entries.removeValue(forKey:oldest)!.bytes
        }
        entries[key] = Entry(image:image,bytes:count,owners:[owner],access:access); bytes += count
        return image
    }
    public static func thumbnail(_ image: NSImage, maxPixels: Int) -> NSImage? {
        autoreleasepool {
            let ratio = min(1,CGFloat(max(1,maxPixels))/max(1,max(image.size.width,image.size.height)))
            let width = max(1,Int(ceil(image.size.width*ratio))), height = max(1,Int(ceil(image.size.height*ratio)))
            guard let context = context(width:width,height:height) else { return nil }
            let drawing = image.copy() as! NSImage; drawing.cacheMode = .never
            let previous = NSGraphicsContext.current
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
            drawing.draw(in:NSRect(x:0,y:0,width:width,height:height),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState(); NSGraphicsContext.current = previous
            return context.makeImage().map { wrap($0) }
        }
    }
    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    private static func wrap(_ cg: CGImage) -> NSImage {
        let image = NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
        image.cacheMode = .never
        return image
    }
    private static func bitmap(cg: CGImage) -> NSImage? {
        guard let context = context(width:cg.width,height:cg.height) else { return nil }
        context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
        return context.makeImage().map { wrap($0) }
    }
}
