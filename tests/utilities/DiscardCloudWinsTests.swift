import Foundation
import SwiftData
import Testing
@testable import GymPerformance

@Suite
struct DiscardCloudWinsTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "DiscardCloudWinsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test
    @MainActor
    func clearRemovesTrainingRowsAndIdentityButLeavesCatalog() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let memberId = AccessControl.persistedMemberId()
        let otherMember = UUID()

        let exercise = ExerciseModel(
            id: UUID(),
            name: "Test Lift",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeightAtReps,
            displayOrder: 1
        )
        context.insert(exercise)

        let session = SessionModel(memberId: memberId, date: Date())
        try dataAccess.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exercise.id)
        try dataAccess.saveExerciseEntry(entry)
        try dataAccess.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 5))
        try dataAccess.savePersonalBest(
            PersonalBestModel(
                memberId: memberId,
                exerciseId: exercise.id,
                weight: 100,
                reps: 5,
                achievedAt: Date(),
                entryType: .manualEntry
            )
        )
        context.insert(
            ExerciseResetModel(memberId: memberId, exerciseId: exercise.id, resetAt: Date())
        )
        _ = try MemberState.updateStalenessSetting(
            MemberStalenessSetting(enabled: true, periods: 1, unit: .month),
            in: context,
            memberId: memberId
        )

        // Other member's data must survive.
        try dataAccess.saveSession(SessionModel(memberId: otherMember, date: Date()))

        try DiscardCloudWins.clearAnonymousLocalHistory(
            anonymousMemberId: memberId,
            in: context,
            performanceDataAccess: dataAccess
        )

        #expect(try dataAccess.fetchSessions(memberId: memberId).isEmpty)
        #expect(try dataAccess.fetchSessions(memberId: otherMember).count == 1)

        let pbs = try context.fetch(
            FetchDescriptor<PersonalBestModel>(predicate: #Predicate { $0.memberId == memberId })
        )
        #expect(pbs.isEmpty)

        let resets = try context.fetch(
            FetchDescriptor<ExerciseResetModel>(predicate: #Predicate { $0.memberId == memberId })
        )
        #expect(resets.isEmpty)

        let identities = try context.fetch(
            FetchDescriptor<UserIdentityModel>(predicate: #Predicate { $0.id == memberId })
        )
        #expect(identities.isEmpty)

        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>())
        #expect(exercises.contains(where: { $0.id == exercise.id }))
    }

    @Test
    func adoptCanonicalMemberIdUpdatesPersistedIdentity() {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()
        #expect(anonymous != canonical)

        AccessControl.adoptCanonicalMemberId(canonical)
        #expect(AccessControl.persistedMemberId() == canonical)
    }

    @Test
    func assessBranchTriggerMatchesIssue33() async throws {
        // Documented contract: discard only when adopted AND local history AND cloud history.
        // Unit-level: LocalMemberHistoryProbe + adopted flag gate; cloud check is integration.
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let deviceId = AccessControl.persistedMemberId()

        #expect(
            try !LocalMemberHistoryProbe.hasLocalHistory(
                memberId: deviceId,
                in: context,
                performanceDataAccess: dataAccess
            )
        )

        try dataAccess.saveSession(SessionModel(memberId: deviceId, date: Date()))
        #expect(
            try LocalMemberHistoryProbe.hasLocalHistory(
                memberId: deviceId,
                in: context,
                performanceDataAccess: dataAccess
            )
        )
    }
}
