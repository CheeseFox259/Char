import AppKit

@main struct GenerateAppIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let set = root.appendingPathComponent("Char.iconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        let pet: NSImage?
        if CommandLine.arguments.dropFirst(2).first == "--example" {
            pet = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { _ in
                NSColor(calibratedRed: 1, green: 0.97, blue: 0.87, alpha: 1).setFill()
                PetIconArtwork.ink.setStroke()
                let body = NSBezierPath(roundedRect: NSRect(x: 25, y: 22, width: 78, height: 89), xRadius: 24, yRadius: 24)
                body.lineWidth = 4; body.fill(); body.stroke()
                for x in [38.0, 90.0] {
                    let foot = NSBezierPath(ovalIn: NSRect(x: x-10, y: 24, width: 20, height: 20))
                    foot.lineWidth = 3; foot.fill(); foot.stroke()
                }
                PetIconArtwork.ink.setFill()
                for x in [48.0, 74.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 58, width: 5, height: 17), xRadius: 2.5, yRadius: 2.5).fill() }
                return true
            }
        } else { pet = CommandLine.arguments.count > 2 ? NSImage(contentsOfFile: CommandLine.arguments[2]) : nil }
        let image = PetIconArtwork.rightEdgeIcon(pet: pet)
        func png(_ size: Int) -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let old = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.current = old
            return bitmap.representation(using: .png, properties: [:])!
        }
        for size in [16, 32, 128, 256, 512] {
            try png(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
            try png(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
        try png(1024).write(to: root.appendingPathComponent("Char.png"))
    }
}
