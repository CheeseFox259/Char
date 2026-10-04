import QuartzCore
import Foundation

/// NSView-free check of the exact planar sampling helper used by the renderer.
@main struct CheckPlanarLayerScale {
    static func main() {
        for expected in [18.0/44.0, 0.08, 0.55, 1, 1.025] {
            for rotation in [0.0, 0.17, -0.3] {
                let layer = CALayer()
                layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation).scaledBy(x: expected, y: expected))
                let actual = LayerGeometry.planarScale(of: layer)
                guard abs(actual-expected) < 0.000001 else {
                    fputs("RED: planar scale \(actual) != \(expected)\n", stderr); exit(1)
                }
            }
        }
        let mini = CALayer(); mini.setAffineTransform(CGAffineTransform(scaleX: 18.0/44.0, y: 18.0/44.0))
        let aggregate = (mini.value(forKeyPath: "transform.scale") as! NSNumber).doubleValue
        print("CALayer planar-scale check passed: mini XY=\(LayerGeometry.planarScale(of: mini)); aggregate XYZ=\(aggregate)")
    }
}
