import AppKit
import QuartzCore
import CharPlatform

/// Stationary desktop seam. Separate from artwork clipping so the soft light
/// can extend into a transparent menu bar without exposing the hidden body.
@MainActor final class CompanionEdgeBoundary {
    let layer = CALayer()
    private let light = CAGradientLayer()
    private let taper = CAShapeLayer()
    private let glow = CAShapeLayer()
    private var style: PetSkinEdgeBoundary?
    private var size: Double = 0
    init() {
        layer.actions = ["position":NSNull(),"transform":NSNull(),"opacity":NSNull(),"hidden":NSNull()]
        light.startPoint = CGPoint(x:0,y:0.5); light.endPoint = CGPoint(x:1,y:0.5)
        light.colors = [NSColor.clear.cgColor,NSColor.white.cgColor,NSColor.clear.cgColor]
        light.locations = [0,0.5,1]; light.mask = taper
        layer.addSublayer(glow); layer.addSublayer(light)
        layer.isHidden = true
    }
    func update(style: PetSkinEdgeBoundary?, petSize: Double, center: CGPoint, vertical: Bool, opacity: Float) {
        guard let style else { if !layer.isHidden { layer.isHidden = true }; return }
        let orientation = vertical ? CGAffineTransform(rotationAngle:.pi/2) : .identity
        guard self.style != style || size != petSize || layer.position != center || layer.opacity != opacity || layer.affineTransform() != orientation || layer.isHidden else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if self.style != style || size != petSize {
            self.style = style; size = petSize
            let span = petSize * (style.width ?? 1.25)
            let thickness = petSize / 48 * (style.thickness ?? 1.2)
            let rect = CGRect(x:0,y:0,width:span,height:thickness)
            let shape = CGMutablePath()
            shape.move(to:CGPoint(x:0,y:thickness/2))
            shape.addCurve(to:CGPoint(x:span,y:thickness/2),control1:CGPoint(x:span*0.25,y:thickness*1.17),control2:CGPoint(x:span*0.75,y:thickness*1.17))
            shape.addCurve(to:CGPoint(x:0,y:thickness/2),control1:CGPoint(x:span*0.75,y:-thickness*0.17),control2:CGPoint(x:span*0.25,y:-thickness*0.17))
            shape.closeSubpath()
            layer.bounds = rect; light.frame = rect; taper.frame = rect; taper.path = shape
            light.opacity = Float(style.opacity ?? 0.55)
            glow.frame = rect; glow.path = shape; glow.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
            glow.shadowColor = NSColor.white.cgColor; glow.shadowOffset = .zero
            glow.shadowRadius = petSize / 48 * (style.glowRadius ?? 4)
            glow.shadowOpacity = Float(style.glowOpacity ?? 0.12); glow.shadowPath = shape
        }
        layer.position = center
        layer.setAffineTransform(orientation)
        layer.opacity = opacity; layer.isHidden = false
    }
}
