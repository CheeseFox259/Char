import Foundation

public struct CharSettings: Equatable, Codable, Sendable {
    public var filterSeconds: TimeInterval
    public var graceSeconds: TimeInterval
    public var soundEnabled: Bool
    public var audioFilePath: String?
    public var launchAtLogin: Bool

    public init(filterSeconds: TimeInterval = 10, graceSeconds: TimeInterval = 300,
                soundEnabled: Bool = true, audioFilePath: String? = nil, launchAtLogin: Bool = true) {
        self.filterSeconds = filterSeconds
        self.graceSeconds = graceSeconds
        self.soundEnabled = soundEnabled
        self.audioFilePath = audioFilePath
        self.launchAtLogin = launchAtLogin
        self = normalized()
    }

    /// Invalid durations revert to their defaults. Zero is a valid immediate threshold.
    public func normalized() -> CharSettings {
        var result = self
        if !filterSeconds.isFinite || filterSeconds < 0 { result.filterSeconds = 10 }
        if !graceSeconds.isFinite || graceSeconds < 0 { result.graceSeconds = 300 }
        return result
    }
}

/// Stores preferences only. Session state and return anchors are deliberately transient.
public struct CharSettingsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Char", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// A missing file uses defaults; corrupt or unreadable preferences report their error to the caller.
    public func load() throws -> CharSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return CharSettings() }
        return try JSONDecoder().decode(CharSettings.self, from: Data(contentsOf: fileURL)).normalized()
    }

    public func save(_ settings: CharSettings) throws {
        let data = try JSONEncoder().encode(settings.normalized())
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
