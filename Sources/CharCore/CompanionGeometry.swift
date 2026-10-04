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
    public static func petFrame(placement: PetPlacement) -> CGRect {
        let center: CGPoint
        switch placement {
        case .desktop: center = CGPoint(x: 170, y: 170)
        case .left: center = CGPoint(x: 38, y: 170)
        case .right: center = CGPoint(x: 302, y: 170)
        case .top: center = CGPoint(x: 170, y: 302)
        case .bottom: center = CGPoint(x: 170, y: 38)
        }
        return CGRect(x: center.x - 38, y: center.y - 38, width: 76, height: 76)
    }
    public static func normalizedOffset(_ offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((offset % count) + count) % count
    }
    public static func layout(count: Int, offset: Int, placement: PetPlacement) -> [Slot] {
        guard count > 0 else { return [] }
        let number = min(count, 6)
        let pet = petFrame(placement: placement)
        let center = CGPoint(x: pet.midX, y: pet.midY)
        let order = (0..<count).map { normalizedOffset($0 + offset, count: count) }
        return (0..<number).map { index in
            let fraction = number == 1 ? 0.5 : Double(index) / Double(number - 1)
            let angle: Double
            switch placement {
            case .desktop: angle = .pi / 2 + Double(index) * 2 * .pi / Double(number)
            case .left: angle = -.pi / 2 + fraction * .pi
            case .right: angle = .pi / 2 + fraction * .pi
            case .top: angle = .pi + fraction * .pi
            case .bottom: angle = fraction * .pi
            }
            let radius = placement == .desktop ? 112.0 : 128.0
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let frame = CGRect(x: point.x - 26, y: point.y - 26, width: 52, height: 52)
            let overflow = count > 6 && index == 5
            let indices = overflow ? Array(order.dropFirst(5).prefix(3)) : []
            let mini = indices.indices.map { miniIndex -> CGRect in
                let a = .pi / 2 + Double(miniIndex) * 2 * .pi / 3
                return CGRect(x: point.x + cos(a) * 15 - 11, y: point.y + sin(a) * 15 - 11, width: 22, height: 22)
            }
            return Slot(frame: frame, primaryIndex: overflow ? nil : order[index], overflowIndices: indices, miniFrames: mini)
        }
    }
    /// Spring response used only for drawing; event bounds never deform.
    public static func arrivalProgress(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        if t == 1 { return 1 }
        return 1 - exp(-7 * t) * cos(10 * t)
    }
}
