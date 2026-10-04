import Foundation
import CoreGraphics
import CharCore

struct CompanionGeometryChecks {
    func run() throws {
        let bounds = CGRect(origin: .zero, size: CompanionGeometry.canvasSize)
        for placement in PetPlacement.allCases {
            try check(bounds.contains(CompanionGeometry.petFrame(placement: placement)))
            for count in 0...16 {
                let slots = CompanionGeometry.layout(count: count, offset: -2, placement: placement)
                try checkEqual(slots.count, min(count, 6))
                for slot in slots {
                    try check(bounds.contains(slot.frame), "edge slot must stay inside panel")
                    try check(slot.miniFrames.allSatisfy(bounds.contains))
                }
            }
        }
        for count in 7...16 {
            var reached = Set<Int>()
            for offset in 0..<count {
                for slot in CompanionGeometry.layout(count: count, offset: offset, placement: .desktop) {
                    if let index = slot.primaryIndex { reached.insert(index) }
                    reached.formUnion(slot.overflowIndices)
                    try check(slot.overflowIndices.count <= 3)
                }
            }
            try checkEqual(reached, Set(0..<count))
        }
        try checkEqual(CompanionGeometry.normalizedOffset(-1, count: 7), 6)
        try checkEqual(CompanionGeometry.arrivalProgress(0), 0)
        try checkEqual(CompanionGeometry.arrivalProgress(1), 1)
        try check(CompanionGeometry.arrivalProgress(0.3) > 1, "arrival has elastic overshoot")
    }
}
