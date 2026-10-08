import AppKit
import CharCore

/// One native badge drawing path for desktop bubbles and inline settings samples.
@MainActor public enum AttentionArtwork {
    public static func draw(group: AttentionPresentationGroup?, pending: Bool, count: Int, past: Bool,
                            color: NSColor, font: NSFont = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)) {
        let badge = NSRect(x: 18, y: 0, width: 26, height: 15)
        color.withAlphaComponent(past ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 7.5, yRadius: 7.5).fill()
        let symbol = past ? CompanionSymbols.resumed : pending ? CompanionSymbols.pending : group?.symbol ?? CompanionSymbols.running
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tinted = image.copy() as! NSImage
            tinted.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 21, y: 3, width: 9, height: 9))
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        String(count).draw(in: NSRect(x: 30, y: 1, width: 13, height: 13), withAttributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: style])
    }
    public static func sample(group: AttentionPresentationGroup, past: Bool = false, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 44, height: 18))
        image.lockFocus(); draw(group: group, pending: false, count: 1, past: past, color: color); image.unlockFocus()
        return image
    }
}
