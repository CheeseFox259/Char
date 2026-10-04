import Foundation

/// Deliberate orbit cycling: trackpads accumulate distance and ignore momentum.
public struct CompanionScrollPolicy: Sendable {
    private var accumulated = 0.0
    private var lastInput = -Double.infinity
    private var lastStep = -Double.infinity
    private var awaitingFirstStep = true
    public init() {}
    public mutating func step(delta: Double, precise: Bool, momentum: Bool, count: Int, now: TimeInterval) -> Int {
        guard count > 6 else { accumulated = 0; awaitingFirstStep = true; lastInput = -Double.infinity; return 0 }
        guard !momentum, delta != 0 else { return 0 }
        if now - lastInput > 0.25 { accumulated = 0; awaitingFirstStep = true }
        lastInput = now
        if precise {
            // A changed direction starts a fresh intentional gesture.
            if accumulated * delta < 0 { accumulated = 0 }
            accumulated += delta
            guard abs(accumulated) >= (awaitingFirstStep ? 6 : 36) else { return 0 }
        }
        guard now - lastStep >= 0.18 else { return 0 }
        lastStep = now
        awaitingFirstStep = false
        accumulated = 0
        return delta > 0 ? 1 : -1
    }
}

public enum AttentionPresentationGroup: String, CaseIterable, Sendable {
    case interaction, issue, ended
    public static func forReason(_ reason: StopReason) -> Self {
        switch reason {
        case .question, .approval, .unclassified: return .interaction
        case .failure, .rateLimit, .contextExhausted: return .issue
        case .turnEnded: return .ended
        }
    }
    public var title: String {
        switch self { case .interaction: return "需关注"; case .issue: return "发生问题"; case .ended: return "轮次结束" }
    }
    public var symbol: String {
        switch self { case .interaction: return "ellipsis.bubble.fill"; case .issue: return "exclamationmark"; case .ended: return "checkmark" }
    }
}
