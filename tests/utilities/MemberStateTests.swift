import Foundation
import SwiftData
import Testing
@testable import GymPerformance

struct MemberStateTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "MemberStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func restoreStandardDefaults(suiteName: String, defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
        AccessControl.userDefaults = .standard
    }

    @Test
    @MainActor
    func stalenessDefaultsWhenNoRow() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults(suiteName: suite, defaults: defaults) }

        let context = try TestHelpers.makeInMemoryContext()
        let setting = try MemberState.stalenessSetting(in: context)

        #expect(setting == MemberState.defaultStaleness)
        #expect(setting.enabled == false)
        #expect(setting.periods == 2)
        #expect(setting.unit == .quarter)
    }

    @Test
    @MainActor
    func updateCreatesRowAndMarksDirty() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults(suiteName: suite, defaults: defaults) }

        let context = try TestHelpers.makeInMemoryContext()
        let memberId = AccessControl.persistedMemberId()
        let setting = MemberStalenessSetting(enabled: true, periods: 1, unit: .month)

        let row = try MemberState.updateStalenessSetting(setting, in: context)
        #expect(row.id == memberId)
        #expect(row.stalenessEnabled == true)
        #expect(row.stalenessPeriods == 1)
        #expect(row.stalenessUnit == .month)
        #expect(row.syncedAt == nil)
        #expect(SyncDirtiness.isDirty(updatedAt: row.updatedAt, syncedAt: row.syncedAt))

        let resolved = try MemberState.stalenessSetting(in: context)
        #expect(resolved == setting)
    }

    @Test
    @MainActor
    func updateExistingRowBumpsUpdatedAtWithoutDuplicate() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults(suiteName: suite, defaults: defaults) }

        let context = try TestHelpers.makeInMemoryContext()
        let memberId = AccessControl.persistedMemberId()

        try MemberState.updateStalenessSetting(
            MemberStalenessSetting(enabled: true, periods: 2, unit: .quarter),
            in: context,
            at: Date(timeIntervalSince1970: 1_000)
        )
        try MemberState.updateStalenessSetting(
            MemberStalenessSetting(enabled: false, periods: 2, unit: .quarter),
            in: context,
            at: Date(timeIntervalSince1970: 2_000)
        )

        let descriptor = FetchDescriptor<UserIdentityModel>(
            predicate: #Predicate { $0.id == memberId }
        )
        let rows = try context.fetch(descriptor)
        #expect(rows.count == 1)
        #expect(rows[0].stalenessEnabled == false)
        #expect(rows[0].updatedAt == Date(timeIntervalSince1970: 2_000))
    }
}
