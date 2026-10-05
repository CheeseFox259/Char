import Foundation
import CharCore

struct SettingsChecks {
    private func withStore(_ action: (CharSettingsStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try action(CharSettingsStore(fileURL: directory.appendingPathComponent("nested/settings.json")))
    }

    func testMissingPreferencesHaveProductDefaults() throws {
        try withStore { store in
            let settings = try store.load()
            try checkEqual(settings.filterSeconds, 10)
            try checkEqual(settings.graceSeconds, 300)
            try check(settings.soundEnabled)
            try check(settings.launchAtLogin)
            try check(settings.audioFilePath == nil)
        }
    }

    func testPreferencesRoundTripAndReplace() throws {
        try withStore { store in
            let settings = CharSettings(filterSeconds: 2, graceSeconds: 120, soundEnabled: false,
                                        audioFilePath: "/tmp/local tone.aiff", launchAtLogin: false)
            try store.save(settings)
            try checkEqual(try store.load(), settings)
            try store.save(CharSettings())
            try checkEqual(try store.load(), CharSettings())
        }
    }

    func testInvalidDurationsNormalizeBeforeSaving() throws {
        try withStore { store in
            for value in [-1.0, Double.infinity, -Double.infinity, Double.nan] {
                var settings = CharSettings()
                settings.filterSeconds = value
                settings.graceSeconds = value
                try store.save(settings)
                try checkEqual(try store.load(), CharSettings())
            }
            let immediate = CharSettings(filterSeconds: 0, graceSeconds: 0)
            try store.save(immediate)
            try checkEqual(try store.load(), immediate)
        }
    }

    func testStoredNegativeDurationsNormalizeOnLoad() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let json = #"{"filterSeconds":-10,"graceSeconds":-5,"soundEnabled":true,"launchAtLogin":true}"#
            try Data(json.utf8).write(to: store.fileURL)
            try checkEqual(try store.load(), CharSettings())
        }
    }
    func testLanguageDefaultsMigrationAndPersistence() throws {
        try checkEqual(AppLanguage.preferred(for: ["zh-TW", "en"]), .chinese)
        try checkEqual(AppLanguage.preferred(for: ["en-US", "zh-Hans"]), .english)
        try checkEqual(AppLanguage.preferred(for: []), .english)
        try withStore { store in
            try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let legacy = #"{"filterSeconds":2,"graceSeconds":90,"soundEnabled":false,"launchAtLogin":false}"#
            try Data(legacy.utf8).write(to: store.fileURL)
            let migrated = try store.load()
            try checkEqual(migrated.language, .systemDefault)
            try checkEqual(migrated.filterSeconds, 2)
            for language in AppLanguage.allCases {
                var settings = migrated
                settings.language = language
                try store.save(settings)
                try checkEqual(try store.load(), settings)
            }
        }
    }

}
