#if canImport(Testing)
import Foundation
import Testing
import SwiftData
@testable import GymPerformance

@Suite
struct MemberIdentityMigrationTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "MemberIdentityMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func restoreStandardDefaults() {
        AccessControl.userDefaults = .standard
    }

    @Test
    func testTC_MIG1_migrationRewritesSessionMemberIdFromLegacyToPersistedUUID() throws {
        let defaults = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults() }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)

        try dataAccess.saveSession(SessionModel(memberId: AccessControl.legacyMemberId, date: Date()))
        try dataAccess.saveSession(SessionModel(memberId: AccessControl.legacyMemberId, date: Date()))

        try MemberIdentityMigration.runMigrationIfNeeded(
            context: context,
            performanceDataAccess: dataAccess
        )

        let persistedId = AccessControl.persistedMemberId()
        let migratedSessions = try dataAccess.fetchSessions(memberId: persistedId)
        let legacySessions = try dataAccess.fetchSessions(memberId: AccessControl.legacyMemberId)

        #expect(migratedSessions.count == 2)
        #expect(migratedSessions.allSatisfy { $0.memberId == persistedId })
        #expect(legacySessions.isEmpty)
    }

    @Test
    func testTC_MIG2_migrationRewritesPersonalBestMemberIdFromLegacyToPersistedUUID() throws {
        let defaults = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults() }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let exerciseId = UUID()

        try dataAccess.savePersonalBest(
            PersonalBestModel(
                memberId: AccessControl.legacyMemberId,
                exerciseId: exerciseId,
                weight: 100,
                reps: 5,
                achievedAt: Date()
            )
        )
        try dataAccess.savePersonalBest(
            PersonalBestModel(
                memberId: AccessControl.legacyMemberId,
                exerciseId: exerciseId,
                weight: 90,
                reps: 5,
                achievedAt: Date().addingTimeInterval(-86_400),
                isCurrent: false
            )
        )

        try MemberIdentityMigration.runMigrationIfNeeded(
            context: context,
            performanceDataAccess: dataAccess
        )

        let persistedId = AccessControl.persistedMemberId()
        let migratedPBs = try dataAccess.fetchAllPBs(memberId: persistedId, exerciseId: exerciseId)
        let legacyPBs = try dataAccess.fetchAllPBs(memberId: AccessControl.legacyMemberId, exerciseId: exerciseId)

        #expect(migratedPBs.count == 2)
        #expect(migratedPBs.allSatisfy { $0.memberId == persistedId })
        #expect(legacyPBs.isEmpty)
    }

    @Test
    func testTC_MIG3_migrationIsIdempotent() throws {
        let defaults = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults() }

        let persistedId = UUID()
        defaults.set(persistedId.uuidString, forKey: AccessControl.memberUUIDKey)
        defaults.set(true, forKey: MemberIdentityMigration.migrationCompleteKey)

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)

        try dataAccess.saveSession(SessionModel(memberId: AccessControl.legacyMemberId, date: Date()))

        try MemberIdentityMigration.runMigrationIfNeeded(
            context: context,
            performanceDataAccess: dataAccess
        )

        let legacySessions = try dataAccess.fetchSessions(memberId: AccessControl.legacyMemberId)
        #expect(legacySessions.count == 1)
        #expect(legacySessions.first?.memberId == AccessControl.legacyMemberId)
    }

    @Test
    func testTC_MIG4_memberUUIDIsStableAcrossMultipleCurrentUserCalls() throws {
        let defaults = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer { restoreStandardDefaults() }

        let first = AccessControl.currentUser()
        let second = AccessControl.currentUser()
        let third = AccessControl.currentUser()

        #expect(first.id == second.id)
        #expect(second.id == third.id)
        #expect(first.displayName == "Member")
        #expect(defaults.string(forKey: AccessControl.memberUUIDKey) == first.id.uuidString)
    }
}
#endif
