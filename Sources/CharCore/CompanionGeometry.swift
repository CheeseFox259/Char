import Foundation
import CoreGraphics

public enum PetPlacement: String, Codable, CaseIterable, Sendable {
    case desktop, left, right, top, bottom
}

/// Window-local geometry. Positions are pet centers, independent of panel origin.
public enum CompanionGeometry {
    public static let canvasSize = CGSize(width: 340, height: 340)
    public struct Slot: Equatable, Sendable {
        public let frame: CGRect
        public let primaryIndex: Int?
        public let overflowIndices: [Int]
        public let miniFrames: [CGRect]
    }
    public static func petFrame(placement: PetPlacement, petSize: Double = 48) -> CGRect {
        let center: CGPoint
        switch placement {
        case .desktop: center = CGPoint(x: 170, y: 170)
        case .left: center = CGPoint(x: 38, y: 170)
        case .right: center = CGPoint(x: 302, y: 170)
        case .top: center = CGPoint(x: 170, y: 302)
        case .bottom: center = CGPoint(x: 170, y: 38)
        }
        let size = min(88, max(36, petSize))
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }
    public static func normalizedOffset(_ offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((offset % count) + count) % count
    }
    public static func radius(petSize: Double = 48, bubbleDistance: Double = 20) -> Double {
        min(88, max(36, petSize)) / 2 + 22 + min(72, max(8, bubbleDistance))
    }
    public static func capacity(placement: PetPlacement, petSize: Double = 48, bubbleDistance: Double = 20) -> Int {
        let r = radius(petSize: petSize, bubbleDistance: bubbleDistance)
        let minimumAngle = 2 * asin(min(1, 48 / (2 * r)))
        return placement == .desktop ? max(3, Int(floor(2 * .pi / minimumAngle)))
            : max(2, Int(floor(edgeSpan(radius: r) / minimumAngle)) + 1)
    }
    private static func edgeSpan(radius: Double) -> Double { min(140 * .pi / 180, 2 * acos(min(1, 18 / radius))) }
    public static func angle(slot: Int, number: Int, placement: PetPlacement, radius: Double = 66) -> Double {
        let fraction = number == 1 ? 0.5 : Double(slot) / Double(number - 1)
        let span = edgeSpan(radius: radius)
        switch placement {
        case .desktop: return .pi / 2 + Double(slot) * 2 * .pi / Double(max(1, number))
        case .left: return -span / 2 + fraction * span
        case .right: return .pi - span / 2 + fraction * span
        case .top: return 3 * .pi / 2 - span / 2 + fraction * span
        case .bottom: return .pi / 2 - span / 2 + fraction * span
        }
    }
    public static func layout(count: Int, offset: Int, placement: PetPlacement, petSize: Double = 48, bubbleDistance: Double = 20) -> [Slot] {
        guard count > 0 else { return [] }
        let capacity = capacity(placement: placement, petSize: petSize, bubbleDistance: bubbleDistance)
        let number = min(count, capacity)
        let pet = petFrame(placement: placement, petSize: petSize)
        let center = CGPoint(x: pet.midX, y: pet.midY)
        let order = (0..<count).map { normalizedOffset($0 + offset, count: count) }
        let radius = radius(petSize: petSize, bubbleDistance: bubbleDistance)
        return (0..<number).map { index in
            let a = angle(slot: index, number: number, placement: placement, radius: radius)
            let point = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            let frame = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let overflow = count > capacity && index == number - 1
            let indices = overflow ? Array(order.dropFirst(number - 1).prefix(3)) : []
            let mini = indices.indices.map { miniIndex -> CGRect in
                let a = .pi / 2 + Double(miniIndex) * 2 * .pi / 3
                return CGRect(x: point.x + cos(a) * 11 - 9, y: point.y + sin(a) * 11 - 9, width: 18, height: 18)
            }
            return Slot(frame: frame, primaryIndex: overflow ? nil : order[index], overflowIndices: indices, miniFrames: mini)
        }
    }
    /// A slower, gentler response for a Space appearance, distinct from migration.
    public static func spaceArrivalProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        if t == 1 { return 1 }
        return 1 - exp(-6 * t) * (cos(5 * t) + 1.2 * sin(5 * t))
    }
    /// Monotone ease-in/out: zero speed at both ends, no directional overshoot.
    public static func orbitProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return t * t * (3 - 2 * t)
    }
    /// Accelerating withdrawal with a smooth start and finish.
    public static func departureProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return t * t * t * (10 + t * (-15 + 6 * t))
    }
    /// Zero initial velocity with one small elastic recovery; exact end pose.
    public static func arrivalProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        if t == 1 { return 1 }
        return 1 - exp(-7 * t) * (cos(7 * t) + sin(7 * t))
    }
}

/// A complete authored clip plays during each phase; only native navigation is immediate.
public struct CompanionPlayback: Sendable {
    public let departure: TimeInterval
    public let arrival: TimeInterval
    public init(departure: TimeInterval?, arrival: TimeInterval?) {
        self.departure = departure ?? 0.10; self.arrival = arrival ?? 0.22
    }
    public var duration: TimeInterval { departure + arrival }
    public func isArriving(at elapsed: TimeInterval) -> Bool { elapsed >= departure }
    public func clipElapsed(at elapsed: TimeInterval) -> TimeInterval {
        isArriving(at: elapsed) ? min(arrival, max(0, elapsed - departure)) : max(0, elapsed)
    }
    public func progress(at elapsed: TimeInterval) -> Double {
        isArriving(at: elapsed) ? min(1, max(0, (elapsed - departure) / arrival)) : min(1, max(0, elapsed / departure))
    }
    /// Package edge clips are authored toward bottom; upright clips retain zero rotation.
    public static func edgeRotation(placement: PetPlacement) -> Double {
        switch placement { case .left: return -90; case .right: return 90; case .top: return 180; case .bottom, .desktop: return 0 }
    }
}
