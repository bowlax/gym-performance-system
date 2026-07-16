import Foundation
import Testing
@testable import GymPerformance

@Suite
struct SyncStatusStoreTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "SyncStatusStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test
    func successClearsUnrecoveredFailure() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let memberId = UUID()
        SyncStatusStore.recordFailure(
            memberId: memberId,
            message: "network down",
            defaults: defaults
        )
        #expect(SyncStatusStore.unrecoveredFailureMessage(memberId: memberId, defaults: defaults) == "network down")

        let successAt = Date(timeIntervalSince1970: 1_700_000_000)
        SyncStatusStore.recordSuccess(memberId: memberId, at: successAt, defaults: defaults)

        #expect(SyncStatusStore.lastSuccessfulCycleAt(memberId: memberId, defaults: defaults) == successAt)
        #expect(SyncStatusStore.unrecoveredFailureMessage(memberId: memberId, defaults: defaults) == nil)
        #expect(SyncStatusStore.unrecoveredFailureAt(memberId: memberId, defaults: defaults) == nil)
    }

    @Test
    func foregroundThrottleUsesLastSuccess() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let memberId = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            SyncStatusStore.shouldRunForegroundSync(memberId: memberId, now: now, defaults: defaults)
        )

        SyncStatusStore.recordSuccess(
            memberId: memberId,
            at: now.addingTimeInterval(-3600),
            defaults: defaults
        )
        #expect(
            !SyncStatusStore.shouldRunForegroundSync(memberId: memberId, now: now, defaults: defaults)
        )

        SyncStatusStore.recordSuccess(
            memberId: memberId,
            at: now.addingTimeInterval(-(SyncStatusStore.foregroundThrottleInterval + 1)),
            defaults: defaults
        )
        #expect(
            SyncStatusStore.shouldRunForegroundSync(memberId: memberId, now: now, defaults: defaults)
        )
    }
}
