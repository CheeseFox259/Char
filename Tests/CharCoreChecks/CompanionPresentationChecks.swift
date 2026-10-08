import Foundation
import CoreGraphics
import CharCore

func companionPresentationChecks() throws {
    struct VisibilityRecord: Decodable { let time: Double; let event: String; let visible: Bool }
    let traceURL = Bundle.module.url(forResource:"space-visibility-20261008",withExtension:"json",subdirectory:"Fixtures")!
    let records = try JSONDecoder().decode([VisibilityRecord].self,from:Data(contentsOf:traceURL))
    var replay = CompanionPresentation()
    let fixed = CGRect(x:10,y:20,width:420,height:420)
    replay.move(to:fixed,placement:.top,animated:false,playback:CompanionPlayback(departure:nil,arrival:nil),at:0)
    for record in records {
        if record.event == "workspace" { replay.spaceChanged(at:record.time) }
        replay.visibilityChanged(record.visible,at:record.time)
        let pose = replay.sample(at:record.time,reduced:false)
        try check(pose.frame == fixed && pose.opacity == 1 && pose.scale == 1 && pose.retraction == 0,
                  "captured user Space timeline replayed scene motion at \(record.time)")
    }
    // WindowServer owns Space visibility. Reordered and late occlusion must
    // not repaint the already-visible companion as transparent or retracted.
    var continuous = CompanionPresentation()
    continuous.move(to: CGRect(x:10,y:20,width:420,height:420), placement:.top, animated:false,
                    playback:CompanionPlayback(departure:nil,arrival:nil), at:0)
    for (time, event) in [(1.0,"hidden"),(1.12,"shown"),(1.2,"space"),
                          (1.39,"hidden"),(1.4,"space"),(1.41,"shown"),
                          (1.8,"space"),(2.03,"hidden"),(2.05,"shown")] {
        switch event {
        case "space": continuous.spaceChanged(at:time)
        default: continuous.visibilityChanged(event == "shown",at:time)
        }
        let pose = continuous.sample(at:time,reduced:false)
        try check(pose.opacity == 1 && pose.scale == 1 && pose.retraction == 0 && pose.clip == "idle",
                  "late Space/occlusion notification repainted a visible companion or replayed arrival: \(event)@\(time)")
    }
    var scene = CompanionPresentation()
    let origin = CGRect(x: 10, y: 20, width: 340, height: 340)
    scene.move(to: origin, placement: .desktop, animated: false, playback: CompanionPlayback(departure: nil, arrival: nil), at: 0)
    let dragged = origin.offsetBy(dx: 50, dy: 30)
    scene.commitDrag(from: dragged, to: dragged, placement: .desktop, playback: CompanionPlayback(departure: 0.5, arrival: 0.5), at: 1)
    let drag = scene.sample(at: 1, reduced: false)
    try checkEqual(drag.frame, dragged); try checkEqual(drag.opacity, 1); try checkEqual(drag.clip, "idle")
    scene.visibilityChanged(false, at: 2); scene.visibilityChanged(true, at: 2.01)
    scene.spaceChanged(at: 2.02)
    let first = scene.sample(at: 2.08, reduced: false)
    try checkEqual(first.opacity, 1)
    scene.visibilityChanged(false, at: 2.09); scene.visibilityChanged(true, at: 2.1); scene.spaceChanged(at: 2.1)
    let afterDuplicate = scene.sample(at: 2.12, reduced: false)
    try check(afterDuplicate.opacity >= first.opacity, "duplicate notifications restarted Space arrival")
    try checkEqual(scene.sample(at: 2.19, reduced: false).opacity, 1)
    scene.visibilityChanged(false, at: 3); scene.visibilityChanged(true, at: 3.01)
    try check(scene.sample(at: 3.07, reduced: false).opacity == 1, "ordinary occlusion stranded the pet")
    scene.feedback("focus", duration: nil, at: 4)
    scene.move(to: origin, placement: .left, animated: true, playback: CompanionPlayback(departure: 0.1, arrival: 0.16), at: 4.1)
    scene.feedback("focus", duration: nil, at: 4.12)
    try check(scene.sample(at: 4.13, reduced: false).feedbackClip == nil, "feedback replaced placement motion")
    var reordered = CompanionPresentation()
    reordered.move(to: origin, placement: .desktop, animated: false, playback: CompanionPlayback(departure: nil, arrival: nil), at: 0)
    reordered.spaceChanged(at: 5)
    reordered.visibilityChanged(false, at: 5.02); reordered.visibilityChanged(true, at: 5.04)
    try checkEqual(reordered.sample(at: 5.08, reduced: false).opacity, 1)
    try checkEqual(reordered.sample(at: 5.19, reduced: false).opacity, 1)
    var display = CompanionPresentation()
    try check(display.focusedDisplay("right",current:"left",at:0) == nil)
    try check(display.focusedDisplay("left",current:"left",at:0.2) == nil)
    try check(display.focusedDisplay("right",current:"left",at:0.3) == nil)
    display.visibilityChanged(false,at:0.4)
    try check(display.focusedDisplay("right",current:"left",at:1) == nil, "occluded foreground triggered screen migration")
    display.visibilityChanged(true,at:1.1); display.spaceChanged(at:1.2)
    try check(display.focusedDisplay("right",current:"left",at:1.6) == nil, "Space compositor transient moved screens")
    try check(display.focusedDisplay("right",current:"left",at:1.8) == nil)
    try check(display.focusedDisplay(nil,current:"left",at:2) == nil)
    try check(display.focusedDisplay("right",current:"left",at:2.1) == nil)
    try check(display.focusedDisplay("right",current:"left",at:2.6) == "right", "stable deliberate screen focus did not migrate")
    reordered.beginDrag(at: 6)
    reordered.commitDrag(from: dragged, to: origin, placement: .left, playback: CompanionPlayback(departure: 0.1, arrival: 0.16), at: 6)
    try check(reordered.sample(at: 6, reduced: false).frame == dragged, "edge commit jumped back to pre-drag position")
    print("Companion presentation: continuous drag, continuous Space visibility, duplicate notifications and animation ownership passed")
}
