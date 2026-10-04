import Foundation
import CoreGraphics
import CharCore

struct CompanionGeometryChecks {
    func run() throws {
        let bounds = CGRect(origin: .zero, size: CompanionGeometry.canvasSize)
        for placement in PetPlacement.allCases {
            try check(bounds.contains(CompanionGeometry.petFrame(placement: placement)))
            // Runtime exposes only 8pt of the pet center past the screen boundary:
            // a 38pt half-size leaves 30pt of the panel beyond the physical screen.
            let physical: CGRect
            switch placement {
            case .desktop: physical = bounds
            case .left: physical = CGRect(x: 30, y: 0, width: 310, height: 340)
            case .right: physical = CGRect(x: 0, y: 0, width: 310, height: 340)
            case .top: physical = CGRect(x: 0, y: 0, width: 340, height: 310)
            case .bottom: physical = CGRect(x: 0, y: 30, width: 340, height: 310)
            }
            for count in 0...16 {
                let slots = CompanionGeometry.layout(count: count, offset: -2, placement: placement)
                try checkEqual(slots.count, min(count, 6))
                for slot in slots {
                    try check(bounds.contains(slot.frame), "edge slot must stay inside panel")
                    try check(slot.miniFrames.allSatisfy(bounds.contains))
                    try check(physical.contains(slot.frame), "\(placement) bubble clipped by physical screen")
                    try check(slot.miniFrames.allSatisfy(physical.contains), "\(placement) mini clipped by physical screen")
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
        let long = CompanionPlayback(departure: 120, arrival: 80)
        try check(!long.isArriving(at: 119.9))
        try check(long.isArriving(at: 120))
        try checkEqual(long.clipElapsed(at: 120), 0)
        try checkEqual(long.clipElapsed(at: 199.5), 79.5)
        try checkEqual(long.clipElapsed(at: 200), 80)
        try checkEqual(long.progress(at: 200), 1)
        try checkEqual(CompanionPlayback.edgeRotation(placement: .left), -90)
        try checkEqual(CompanionPlayback.edgeRotation(placement: .right), 90)
        try checkEqual(CompanionPlayback.edgeRotation(placement: .top), 180)
        try checkEqual(CompanionGeometry.normalizedOffset(-1, count: 7), 6)
        try checkEqual(CompanionGeometry.arrivalProgress(0), 0)
        try checkEqual(CompanionGeometry.arrivalProgress(1), 1)
        try check(CompanionGeometry.arrivalProgress(0.3) > 1, "arrival has elastic overshoot")
    }
}
