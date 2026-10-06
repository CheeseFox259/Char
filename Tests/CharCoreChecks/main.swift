import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String, String, Int)
    var description: String {
        switch self {
        case let .failed(message, file, line): return "\(file):\(line): \(message)"
        }
    }
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "condition failed",
           file: String = #filePath, line: Int = #line) throws {
    if try !condition() { throw CheckFailure.failed(message, file, line) }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T,
                              file: String = #filePath, line: Int = #line) throws {
    try check(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

let settings = SettingsChecks()
try settings.testMissingPreferencesHaveProductDefaults()
try settings.testPreferencesRoundTripAndReplace()
try settings.testInvalidDurationsNormalizeBeforeSaving()
try settings.testStoredNegativeDurationsNormalizeOnLoad()
try settings.testLanguageDefaultsMigrationAndPersistence()
print("CharCore: 5 settings checks passed")

let attention = AttentionChecks()
try attention.testThresholdAndTransientWait()
try attention.testExactFocusAndApplicationFocus()
try attention.testStartupChildrenAndWorkEndIdentity()
try attention.testReasonReplacementAndPastResume()
try attention.testOrderingAndIgnoreOnlyHead()
try attention.testSoundDebounceMuteAndRemovedItems()
try attention.testSleepCompleteBatchUsesFinalState()
try attention.testSuccessfulVisitsDismissOnlyClickedItemAndKeepFirstAnchor()
try attention.testFallbackDismissalPreservesOtherItemsAndRunningBubble()
try attention.testAgentOriginFirstAnchorAndReturn()
try attention.testExactVisitAndUnavailableVisit()
try attention.testUnsupportedApplicationSourcesAndNoSource()
try attention.testGraceAccumulatesPausesAndExpiresSilently()
try attention.testManualReturnInvalidSourceEndAndRestart()
try attention.testDegradedWeChatHoldAndReturn()
try attention.testSettingsChangesAndClosedSession()
try attention.testClosureRetainsVisibleAttentionOnly()
try attention.testFailedReturnsKeepRetryableOriginalAnchor()
print("CharCore: 18 attention/return checks passed")

let plugins = PluginChecks()
try plugins.testPersistenceAndHotReload()
try plugins.testImportConflictsAndAtomicFailures()
try plugins.testAssetsAndSymlinks()
try plugins.testLegacyMigrationAndUnifiedCapabilities()
print("CharCore: 4 integration plugin groups passed")

try CompanionGeometryChecks().run()
print("CharCore: companion physical-edge and playback checks passed")

try ObservationGenerationChecks().run()
print("CharCore: observation generation checks passed")

try CompanionPreferencesChecks().run()
print("CharCore: shared-display placement and size migration checks passed")

try originPolicyChecks()
print("CharCore: original/latest/disabled, failed visit, generic origin preference and migration passed")
