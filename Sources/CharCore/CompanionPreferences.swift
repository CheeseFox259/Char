import Foundation
import CoreGraphics

/// A single placement follows the user across displays; coordinates are normalized.
public struct CompanionPreferences: Codable, Equatable, Sendable {
    public var placement: PetPlacement = .desktop
    public var petSize: Double = 48
    public var normalizedX: Double = 0.78
    public var normalizedY: Double = 0.24
    public init() {}
    private enum CodingKeys: String, CodingKey { case placement, petSize, normalizedX, normalizedY }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        placement = try values.decodeIfPresent(PetPlacement.self, forKey: .placement) ?? .desktop
        petSize = Self.clamp(try values.decodeIfPresent(Double.self, forKey: .petSize) ?? 48, range: 36...88, fallback: 48)
        normalizedX = Self.clamp(try values.decodeIfPresent(Double.self, forKey: .normalizedX) ?? 0.78, range: 0...1, fallback: 0.78)
        normalizedY = Self.clamp(try values.decodeIfPresent(Double.self, forKey: .normalizedY) ?? 0.24, range: 0...1, fallback: 0.24)
        // Legacy `displays` coordinates deliberately do not restore per-display modes.
    }
    public mutating func setSize(_ value: Double) { petSize = Self.clamp(value, range: 36...88, fallback: 48) }
    public mutating func remember(center: CGPoint, in area: CGRect) {
        normalizedX = Self.clamp((center.x - area.minX) / max(1, area.width), range: 0...1, fallback: 0.78)
        normalizedY = Self.clamp((center.y - area.minY) / max(1, area.height), range: 0...1, fallback: 0.24)
    }
    public func center(in area: CGRect) -> CGPoint {
        CGPoint(x: area.minX + normalizedX * area.width, y: area.minY + normalizedY * area.height)
    }
    private static func clamp(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
