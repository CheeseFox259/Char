import Foundation
import CoreGraphics
import CharCore

struct CompanionGeometryChecks {
    func run() throws {
        let bounds = CGRect(origin: .zero, size: CompanionGeometry.canvasSize)
        for size in [36.0, 48.0, 88.0] {
        for placement in PetPlacement.allCases {
            // Edge pet frames may extend past the panel; the physical screen clips the authored peek.
            if placement == .desktop { try check(bounds.contains(CompanionGeometry.petFrame(placement: placement, petSize: size))) }
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
                let slots = CompanionGeometry.layout(count: count, offset: -2, placement: placement, petSize: size)
                try checkEqual(slots.count, min(count, 6))
                for slot in slots {
                    try check(bounds.contains(slot.frame), "edge slot must stay inside panel")
                    try check(slot.miniFrames.allSatisfy(bounds.contains))
                    try check(physical.contains(slot.frame), "\(placement) bubble clipped by physical screen")
                    try check(slot.miniFrames.allSatisfy(physical.contains), "\(placement) mini clipped by physical screen")
                }
            }
        }
        }
        var wheel = CompanionScrollPolicy()
        try checkEqual(wheel.step(delta: 80, precise: true, momentum: false, count: 6, now: 0), 0)
        try checkEqual(wheel.step(delta: 5, precise: true, momentum: false, count: 7, now: 0), 0)
        try checkEqual(wheel.step(delta: 1, precise: true, momentum: false, count: 7, now: 0.01), 1)
        try checkEqual(wheel.step(delta: 80, precise: true, momentum: true, count: 7, now: 0.2), 0)
        try checkEqual(wheel.step(delta: 36, precise: true, momentum: false, count: 7, now: 0.05), 0)
        try checkEqual(wheel.step(delta: -35, precise: true, momentum: false, count: 7, now: 0.20), 0)
        try checkEqual(wheel.step(delta: -1, precise: true, momentum: false, count: 7, now: 0.21), -1)
        try checkEqual(wheel.step(delta: 6, precise: true, momentum: false, count: 7, now: 0.5), 1)
        var mouseWheel = CompanionScrollPolicy()
        try checkEqual(mouseWheel.step(delta: 1, precise: false, momentum: false, count: 7, now: 0), 1)
        try checkEqual(mouseWheel.step(delta: 1, precise: false, momentum: false, count: 7, now: 0.05), 0)
        try checkEqual(mouseWheel.step(delta: 1, precise: false, momentum: false, count: 7, now: 0.20), 1)
        try checkEqual(CompanionPlayback(departure: nil, arrival: nil).duration, 0.24)
        for reason in [StopReason.question, .approval, .unclassified] { try checkEqual(AttentionPresentationGroup.forReason(reason), .interaction) }
        for reason in [StopReason.failure, .rateLimit, .contextExhausted] { try checkEqual(AttentionPresentationGroup.forReason(reason), .issue) }
        try checkEqual(AttentionPresentationGroup.forReason(.turnEnded), .ended)
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
        try checkEqual(CompanionGeometry.spaceArrivalProgress(0), 0)
        try checkEqual(CompanionGeometry.spaceArrivalProgress(1), 1)
        try check(CompanionGeometry.spaceArrivalProgress(0.15) < CompanionGeometry.arrivalProgress(0.15))
        try checkEqual(CompanionGeometry.arrivalProgress(0), 0)
        try checkEqual(CompanionGeometry.arrivalProgress(1), 1)
        try check(CompanionGeometry.arrivalProgress(0.3) > 1, "arrival has elastic overshoot")
    }
}
