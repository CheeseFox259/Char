import AppKit
import CharPlatform

func imageCacheChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Char-image-cache-\(UUID())")
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:root) }
    func png(_ color: NSColor) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:512,pixelsHigh:512,bitsPerSample:8,
            samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        color.setFill(); NSRect(x:0,y:0,width:512,height:512).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using:.png,properties:[:])!
    }
    let first = root.appendingPathComponent("cli.png"), second = root.appendingPathComponent("desktop.png")
    try png(.red).write(to:first); try FileManager.default.copyItem(at:first,to:second)
    let cache = DecodedImageCache(budget:2*88*88*4)
    let cli = cache.image(at:first,maxPixels:88,owner:"cli")!
    let desktop = cache.image(at:second,maxPixels:88,owner:"desktop")!
    let cg = cli.cgImage(forProposedRect:nil,context:nil,hints:nil)!
    assert(cli === desktop,"identical packaged icons must share the bitmap")
    assert(cg.width == 88 && cg.height == 88 && cg.bitsPerPixel == 32)
    assert(cache.bytes == cg.bytesPerRow*cg.height && cache.usage(owner:"cli").shared == cache.bytes)
    cache.retainOwners(["cli"])
    assert(cache.usage(owner:"desktop").bytes == 0 && cache.usage(owner:"cli").shared == 0)
    let extra = root.appendingPathComponent("extra.png"); try png(.blue).write(to:extra)
    _ = cache.image(at:extra,maxPixels:88,owner:"extra")
    _ = cache.image(at:first,maxPixels:64,owner:"cli")
    assert(cache.bytes <= cache.budget,"different decoded sizes must share one strict budget")
    assert(cache.image(at:first,maxPixels:88,owner:"cli") != nil,"evicted artwork must reload")
    let fullCache = DecodedImageCache(budget:2*1024*1024)
    let native = fullCache.image(at:first,maxPixels:512,owner:"native")
    assert(native === fullCache.image(at:first,maxPixels:1024,owner:"large"),"oversized requests must reuse the original-size bitmap")
    cache.removeAll(); assert(cache.bytes == 0 && cache.usage(owner:"cli").bytes == 0)
    print("Images: thumbnail pixels, 8-bit storage, content sharing, ownership, eviction and pressure release passed")
}
