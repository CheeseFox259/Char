import Foundation

public enum WorkEnd: String, CaseIterable, Codable, Sendable {
    case claudeCode, codexCLI, codexDesktop, deepseekDesktop, kimiCLI, kimiDesktop, pi
}

public enum StopReason: String, CaseIterable, Codable, Sendable {
    case question, approval, turnEnded, failure, rateLimit, contextExhausted, unclassified
}

public struct SessionKey: Hashable, Codable, Sendable {
    public var workEnd: WorkEnd
    public var nativeID: String

    public init(workEnd: WorkEnd, nativeID: String) {
        self.workEnd = workEnd
        self.nativeID = nativeID
    }
}

public struct SessionTarget: Hashable, Codable, Sendable {
    public var bundleIdentifier: String
    public var tmuxPaneID: String?
    public var processID: Int32?
    public var sourcePath: String?

    public init(bundleIdentifier: String, tmuxPaneID: String? = nil, processID: Int32? = nil, sourcePath: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.tmuxPaneID = tmuxPaneID
        self.processID = processID
        self.sourcePath = sourcePath
    }
}

public enum SessionState: Equatable, Codable, Sendable {
    case running, stopped(StopReason), closed
}

public struct ObservationEvent: Equatable, Codable, Sendable {
    public var key: SessionKey
    public var target: SessionTarget
    public var timestamp: Date
    public var state: SessionState
    public var isChild: Bool

    public init(key: SessionKey, target: SessionTarget, timestamp: Date, state: SessionState, isChild: Bool = false) {
        self.key = key
        self.target = target
        self.timestamp = timestamp
        self.state = state
        self.isChild = isChild
    }
}

public enum AnchorAccuracy: String, Codable, Sendable { case exact, application }

public struct ReturnAnchor: Equatable, Codable, Sendable {
    public var id: String
    public var bundleIdentifier: String
    public var token: String
    public var accuracy: AnchorAccuracy

    public init(id: String, bundleIdentifier: String, token: String, accuracy: AnchorAccuracy) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.token = token
        self.accuracy = accuracy
    }
}

public enum NavigationOutcome: String, Codable, Sendable { case exact, fallback, unavailable }

public struct FocusContext: Equatable, Sendable {
    public var exactSession: SessionKey?
    public var isAgent: Bool
    public var sourceAnchorID: String?

    public init(exactSession: SessionKey? = nil, isAgent: Bool = false, sourceAnchorID: String? = nil) {
        self.exactSession = exactSession
        self.isAgent = isAgent
        self.sourceAnchorID = sourceAnchorID
    }
}
