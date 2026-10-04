import Foundation
import CharCore

struct CompanionPosition: Codable {
    var x: Double
    var y: Double
    var placement: PetPlacement
}
struct CompanionPreferences: Codable {
    var placement: PetPlacement = .desktop
    var displays: [String: CompanionPosition] = [:]
}
