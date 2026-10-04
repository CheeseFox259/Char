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
    public static func layout(count: Int, offset: Int, placement: PetPlacement, petSize: Double = 48) -> [Slot] {
        guard count > 0 else { return [] }
        let number = min(count, 6)
        let pet = petFrame(placement: placement, petSize: petSize)
        let center = CGPoint(x: pet.midX, y: pet.midY)
        let order = (0..<count).map { normalizedOffset($0 + offset, count: count) }
        return (0..<number).map { index in
            let fraction = number == 1 ? 0.5 : Double(index) / Double(number - 1)
            let angle: Double
            // Trim the semicircle tips inward: the pet panel extends 30pt off-screen.
            // 140 degrees preserves 52pt hit areas on the physical screen at all edges.
            let span = 140.0 * .pi / 180
            switch placement {
            case .desktop: angle = .pi / 2 + Double(index) * 2 * .pi / Double(number)
            case .left: angle = -span / 2 + fraction * span
            case .right: angle = .pi - span / 2 + fraction * span
            case .top: angle = 3 * .pi / 2 - span / 2 + fraction * span
            case .bottom: angle = .pi / 2 - span / 2 + fraction * span
            }
            let radius = placement == .desktop ? max(66, petSize / 2 + 30) : 94.0
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let frame = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let overflow = count > 6 && index == 5
            let indices = overflow ? Array(order.dropFirst(5).prefix(3)) : []
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
    /// Spring response used only for drawing; event bounds never deform.
    public static func arrivalProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        if t == 1 { return 1 }
        return 1 - exp(-7 * t) * cos(10 * t)
    }
}

/// A complete authored clip plays during each phase; only native navigation is immediate.
public struct CompanionPlayback: Sendable {
    public let departure: TimeInterval
    public let arrival: TimeInterval
    public init(departure: TimeInterval?, arrival: TimeInterval?) {
        self.departure = departure ?? 0.09; self.arrival = arrival ?? 0.15
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
