import QuartzCore
import Foundation

@main struct CheckOrbitInspection {
    static func main() throws {
        let layer = CALayer()
        guard try OrbitPathInspection.read(layer, required: false) == nil else { fatalError("hidden layer must be explicitly skipped") }
        expectFailure(layer, "required absent animation")
        let path = CAKeyframeAnimation(keyPath: "position")
        path.values = [NSValue(point: .zero), NSValue(point: CGPoint(x: 2, y: 0))]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale"); scale.values = [1, 0.4]
        let group = CAAnimationGroup(); group.duration = 1
        group.animations = [path]; layer.add(group, forKey: "orbit")
        expectFailure(layer, "missing scale")
        group.animations = [scale]; layer.add(group, forKey: "orbit")
        expectFailure(layer, "missing position")
        scale.values = [1]; group.animations = [path, scale]; layer.add(group, forKey: "orbit")
        expectFailure(layer, "mismatched scale count")
        scale.values = [1, 0.4]; group.animations = [path, scale]; layer.add(group, forKey: "orbit")
        guard let samples = try OrbitPathInspection.read(layer, required: true), samples.positions.count == 2 else { fatalError("valid actual submitted path not inspected") }
        print("Orbit inspection check passed: absent/partial animations RED; deliberate hidden skip; actual submitted path inspected")
    }
    static func expectFailure(_ layer: CALayer, _ label: String) {
        do { _ = try OrbitPathInspection.read(layer, required: true); fatalError("oracle falsely passed: \(label)") }
        catch { print("Expected RED: \(label)") }
    }
}
