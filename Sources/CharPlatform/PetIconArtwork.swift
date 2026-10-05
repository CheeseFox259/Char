import AppKit

/// Native artwork shared by the default companion and its software/project identity.
public enum PetIconArtwork {
    public static let ink = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1)
    public static func drawDefaultBody() {
        let body = NSBezierPath(roundedRect: NSRect(x: 7, y: 8, width: 62, height: 60), xRadius: 21, yRadius: 21)
        NSColor(calibratedRed: 1, green: 0.97, blue: 0.87, alpha: 1).setFill(); body.fill()
        ink.setStroke(); body.lineWidth = 3.5; body.stroke()
    }
    public static func rightEdgeIcon(pet: NSImage? = nil, anchor: NSPoint = NSPoint(x: 0.5, y: 0.5)) -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 184, yRadius: 184)
            tile.addClip()
            NSGradient(starting: NSColor(calibratedRed: 0.97, green: 0.98, blue: 1, alpha: 1),
                       ending: NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.99, alpha: 1))?.draw(in: tile, angle: -70)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 80, y: 80, width: 700, height: 864)).addClip()
            let transform = NSAffineTransform()
            transform.translateX(by: 712, yBy: 512)
            transform.rotate(byDegrees: pet == nil ? 8 : 90)
            transform.concat()
            let shadow = NSShadow(); shadow.shadowColor = NSColor(calibratedWhite: 0.1, alpha: 0.14)
            shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: -4, height: -12); shadow.set()
            if let pet {
                let scale = 608 / max(pet.size.width, pet.size.height)
                let size = NSSize(width: pet.size.width * scale, height: pet.size.height * scale)
                pet.draw(in: NSRect(x: -anchor.x * size.width, y: -anchor.y * size.height, width: size.width, height: size.height))
            } else {
                let local = NSAffineTransform(); local.scaleX(by: 8, yBy: 8); local.translateX(by: -38, yBy: -38); local.concat()
                drawDefaultBody()
                NSShadow().set()
                ink.setFill()
                for x in [10.0, 29.0] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: 33, width: 4, height: 12), xRadius: 2, yRadius: 2).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedRed: 0.52, green: 0.60, blue: 0.72, alpha: 0.45).setFill()
            NSRect(x: 780, y: 80, width: 6, height: 864).fill()
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSRect(x: 786, y: 80, width: 9, height: 864).fill()
            return true
        }
    }
}
