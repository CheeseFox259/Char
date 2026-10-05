import QuartzCore

/// Artwork uses uniform XY scale; CALayer's aggregate scale also includes Z.
enum LayerGeometry {
    static func planarScale(of layer: CALayer) -> CGFloat {
        hypot(layer.transform.m11, layer.transform.m12)
    }
}
