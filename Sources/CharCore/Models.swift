import Foundation

/// String identity allows imported adapters to add clients without an enum edit.
public struct WorkEnd: RawRepresentable, Hashable, Codable, CaseIterable, Comparable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard rawValue.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue
    }
    public static let claudeCode = WorkEnd(rawValue: "claudeCode")!
    public static let codexCLI = WorkEnd(rawValue: "codexCLI")!
    public static let codexDesktop = WorkEnd(rawValue: "codexDesktop")!
    public static let deepseekDesktop = WorkEnd(rawValue: "deepseekDesktop")!
    public static let kimiCLI = WorkEnd(rawValue: "kimiCLI")!
    public static let kimiDesktop = WorkEnd(rawValue: "kimiDesktop")!
    public static let pi = WorkEnd(rawValue: "pi")!
    public static let allCases: [WorkEnd] = [.claudeCode, .codexCLI, .codexDesktop, .deepseekDesktop, .kimiCLI, .kimiDesktop, .pi]
    public static func < (lhs: WorkEnd, rhs: WorkEnd) -> Bool {
        let l = allCases.firstIndex(of: lhs) ?? allCases.count
        let r = allCases.firstIndex(of: rhs) ?? allCases.count
        return l == r ? lhs.rawValue < rhs.rawValue : l < r
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let value = try c.decode(String.self)
        guard let parsed = Self(rawValue: value) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid work-end ID") }
        self = parsed
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
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
