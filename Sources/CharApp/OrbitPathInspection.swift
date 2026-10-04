import QuartzCore

// [DEBUG-char-wheel-deep] Read the actual submitted layer path, never an inferred fallback.
enum OrbitPathInspection {
    struct Samples { let positions: [NSValue]; let scales: [NSNumber] }
    enum Failure: Error { case missing(String) }
    static func read(_ layer: CALayer, required: Bool) throws -> Samples? {
        guard let group = layer.animation(forKey: "orbit") as? CAAnimationGroup else {
            if required { throw Failure.missing("required orbit group") }
            return nil // Hidden before and after this step; intentionally not animated.
        }
        guard let path = group.animations?.first(where: { ($0 as? CAPropertyAnimation)?.keyPath == "position" }) as? CAKeyframeAnimation,
              let values = path.values as? [NSValue], values.count >= 2 else { throw Failure.missing("position samples") }
        guard let grow = group.animations?.first(where: { ($0 as? CAPropertyAnimation)?.keyPath == "transform.scale" }) else { throw Failure.missing("scale animation") }
        let scales: [NSNumber]
        if let frames = grow as? CAKeyframeAnimation, let samples = frames.values as? [NSNumber] { scales = samples }
        else if let basic = grow as? CABasicAnimation, let from = basic.fromValue as? NSNumber, let to = basic.toValue as? NSNumber {
            scales = values.indices.map { NSNumber(value: from.doubleValue + (to.doubleValue-from.doubleValue)*Double($0)/Double(values.count-1)) }
        } else { throw Failure.missing("scale samples") }
        guard scales.count == values.count else { throw Failure.missing("matching scale samples") }
        return Samples(positions: values, scales: scales)
    }
}
