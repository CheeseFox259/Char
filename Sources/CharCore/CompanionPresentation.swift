import Foundation
import CoreGraphics

/// Native scene motion owns placement, feedback and settled display selection.
/// WindowServer owns Space visibility; occlusion never changes the scene pose.
public struct CompanionPresentation: Sendable {
    public struct Pose: Sendable {
        public var frame: CGRect = .zero
        public var placement: PetPlacement = .desktop
        public var opacity: Double = 1
        public var scale: Double = 1
        public var retraction: Double = 0
        public var clip = "idle"
        public var clipElapsed: Double = 0
        public var feedbackClip: String?
        public var feedbackElapsed: Double?
    }
    private struct Movement: Sendable {
        let destination: CGRect
        let placement: PetPlacement
        let started: Double
        let playback: CompanionPlayback
        let initial: Pose
    }
    private var pose = Pose()
    private var movement: Movement?
    private var feedbackMotion: (clip: String, started: Double, duration: Double?)?
    private var visible = true
    private var displayCandidate: (id: String, since: Double)?
    private var displayHoldUntil: Double = 0
    public var isMoving: Bool { movement != nil }
    public var placement: PetPlacement { pose.placement }
    public init() {}
    public mutating func feedback(_ clip: String, duration: Double?, at now: Double) {
        guard movement == nil else { return }
        feedbackMotion = clip == "idle" ? nil : (clip, now, duration)
    }
    public mutating func beginDrag(at now: Double) {
        movement = nil; feedbackMotion = nil
        pose.opacity = 1; pose.scale = 1; pose.retraction = 0
    }
    public mutating func commitDrag(from currentFrame: CGRect, to frame: CGRect, placement: PetPlacement, playback: CompanionPlayback, at now: Double) {
        pose.frame = currentFrame
        move(to: frame, placement: placement, animated: placement != pose.placement, playback: playback, at: now)
    }
    public mutating func move(to frame: CGRect, placement: PetPlacement, animated: Bool, playback: CompanionPlayback, at now: Double) {
        feedbackMotion = nil
        if animated {
            movement = Movement(destination: frame, placement: placement, started: now, playback: playback, initial: pose)
        } else {
            movement = nil; pose = Pose(frame: frame, placement: placement)
        }
    }
    public mutating func visibilityChanged(_ isVisible: Bool, at now: Double) {
        visible = isVisible
        displayCandidate = nil
        displayHoldUntil = max(displayHoldUntil, now + 0.4)
    }
    public mutating func spaceChanged(at now: Double) {
        displayCandidate = nil
        displayHoldUntil = max(displayHoldUntil, now + 0.55)
    }
    /// A transient foreground window during a Space transition is not a user
    /// display choice. Require a stable target after the compositor settles.
    public mutating func focusedDisplay(_ proposed: String?, current: String, at now: Double) -> String? {
        guard visible, now >= displayHoldUntil, let proposed, proposed != current else {
            displayCandidate = nil; return nil
        }
        guard let candidate = displayCandidate, candidate.id == proposed else {
            displayCandidate = (proposed, now); return nil
        }
        guard now - candidate.since >= 0.45 else { return nil }
        displayCandidate = nil
        return proposed
    }
    public mutating func sample(at now: Double, reduced: Bool) -> Pose {
        pose.clip = "idle"; pose.clipElapsed = reduced ? 0 : now
        pose.feedbackClip = nil; pose.feedbackElapsed = nil
        if let feedback = feedbackMotion {
            if let duration = feedback.duration, now - feedback.started >= duration { feedbackMotion = nil }
            else { pose.feedbackClip = feedback.clip; pose.feedbackElapsed = reduced ? 0 : now - feedback.started }
        }
        if let motion = movement {
            let playback = reduced ? CompanionPlayback(departure: 0.056, arrival: 0.104) : motion.playback
            let elapsed = max(0, now - motion.started), arriving = playback.isArriving(at: elapsed)
            let p = playback.progress(at: elapsed)
            pose.feedbackClip = nil; pose.feedbackElapsed = nil
            pose.clip = arriving ? (motion.placement == .desktop ? "arrive" : "edgePeek") : (motion.initial.placement == .desktop ? "depart" : "edgeHide")
            pose.clipElapsed = reduced ? 0 : playback.clipElapsed(at: elapsed)
            if arriving {
                pose.frame = motion.destination; pose.placement = motion.placement
                pose.opacity = CompanionGeometry.orbitProgress(min(1, p * 1.8))
                pose.scale = reduced || pose.placement != .desktop ? 1 : 0.2 + 0.8 * CompanionGeometry.arrivalProgress(p)
                pose.retraction = reduced || pose.placement == .desktop ? 0 : 38 * (1 - CompanionGeometry.arrivalProgress(p))
            } else {
                let p = CompanionGeometry.departureProgress(p)
                pose.opacity = motion.initial.opacity * (1 - p)
                pose.scale = reduced || pose.placement != .desktop ? 1 : motion.initial.scale * (1 - 0.8 * p)
                pose.retraction = reduced || pose.placement == .desktop ? 0 : motion.initial.retraction + (38 - motion.initial.retraction) * p
            }
            if elapsed >= playback.duration { movement = nil; pose.opacity = 1; pose.scale = 1; pose.retraction = 0; pose.clip = "idle" }
        }
        return pose
    }
}
