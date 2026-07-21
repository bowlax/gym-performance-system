#if canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import GymPerformance

private final class MockSyncServiceAccess: SyncServiceAccess, @unchecked Sendable {
    private(set) var sessionBatches: [[[String: Any]]] = []
    private(set) var entryBatches: [[[String: Any]]] = []
    private(set) var setBatches: [[[String: Any]]] = []
    private(set) var pbBatches: [[[String: Any]]] = []
    private(set) var exerciseResetBatches: [[[String: Any]]] = []

    func upsertSessions(_ rows: [[String: Any]]) async throws { sessionBatches.append(rows) }
    func upsertExerciseEntries(_ rows: [[String: Any]]) async throws { entryBatches.append(rows) }
    func upsertSets(_ rows: [[String: Any]]) async throws { setBatches.append(rows) }
    func upsertPersonalBests(_ rows: [[String: Any]]) async throws { pbBatches.append(rows) }
    func upsertExerciseResets(_ rows: [[String: Any]]) async throws { exerciseResetBatches.append(rows) }
    func patchMemberSettings(memberId: UUID, fields: [String: Any]) async throws -> Bool { true }
    func pullSessions(since: Date?) async throws -> [CloudSessionRow] { [] }
    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow] { [] }
    func pullSets(since: Date?) async throws -> [CloudSetRow] { [] }
    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow] { [] }
    func pullMembers(since: Date?) async throws -> [CloudMemberRow] { [] }
    func pullExerciseResets(since: Date?) async throws -> [CloudExerciseResetRow] { [] }
}

@Suite
struct AdoptLocalHistoryRetagTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "AdoptLocalHistoryRetagTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test
    @MainActor
    func retagMigratesTrainingIdentityAndUploadFindsCanonicalRows() async throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        AdoptLocalHistoryRetag.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            AdoptLocalHistoryRetag.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()
        #expect(anonymous != canonical)

        let exercise = ExerciseModel(
            id: UUID(),
            name: "Retag Lift",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeightAtReps,
            displayOrder: 1
        )
        context.insert(exercise)

        let session = SessionModel(memberId: anonymous, date: Date())
        try dataAccess.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exercise.id)
        try dataAccess.saveExerciseEntry(entry)
        try dataAccess.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 80, reps: 5))
        try dataAccess.savePersonalBest(
            PersonalBestModel(
                memberId: anonymous,
                exerciseId: exercise.id,
                weight: 80,
                reps: 5,
                achievedAt: Date(),
                entryType: .manualEntry
            )
        )
        context.insert(
            ExerciseResetModel(memberId: anonymous, exerciseId: exercise.id, resetAt: Date())
        )
        _ = try MemberState.updateStalenessSetting(
            MemberStalenessSetting(enabled: true, periods: 3, unit: .month),
            in: context,
            memberId: anonymous
        )

        try AdoptLocalHistoryRetag.retagAndAdopt(
            anonymousMemberId: anonymous,
            canonicalMemberId: canonical,
            in: context,
            performanceDataAccess: dataAccess
        )

        #expect(AccessControl.persistedMemberId() == canonical)
        #expect(defaults.string(forKey: AdoptLocalHistoryRetag.pendingAdoptFromKey) == nil)
        #expect(defaults.string(forKey: AdoptLocalHistoryRetag.pendingAdoptToKey) == nil)
        #expect(try dataAccess.fetchSessions(memberId: anonymous).isEmpty)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 1)

        let pbs = try context.fetch(
            FetchDescriptor<PersonalBestModel>(predicate: #Predicate { $0.memberId == canonical })
        )
        #expect(pbs.count == 1)

        let resets = try context.fetch(
            FetchDescriptor<ExerciseResetModel>(predicate: #Predicate { $0.memberId == canonical })
        )
        #expect(resets.count == 1)

        let identities = try context.fetch(
            FetchDescriptor<UserIdentityModel>(predicate: #Predicate { $0.id == canonical })
        )
        #expect(identities.count == 1)
        #expect(identities.first?.stalenessEnabled == true)
        #expect(identities.first?.stalenessPeriods == 3)
        #expect(identities.first?.stalenessUnit == .month)

        let staleness = try MemberState.stalenessSetting(in: context, memberId: canonical)
        #expect(staleness.enabled == true)
        #expect(staleness.periods == 3)
        #expect(staleness.unit == .month)

        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let cloud = MockSyncServiceAccess()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable",
            accessToken: "token",
            memberId: canonical,
            gymId: gymId,
            deviceId: UUID()
        )
        let result = await FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials
        ).upload(memberId: canonical)

        #expect(result.completed == true)
        #expect(result.counts.sessions == 1)
        #expect(result.counts.exerciseEntries == 1)
        #expect(result.counts.sets == 1)
        #expect(result.counts.personalBests == 1)
        #expect(result.counts.exerciseResets == 1)
        #expect(result.counts.total > 0)
        #expect(cloud.sessionBatches.first?.first?["member_id"] as? String == canonical.uuidString)
    }

    @Test
    @MainActor
    func retagIsIdempotentOnSecondRun() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        AdoptLocalHistoryRetag.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            AdoptLocalHistoryRetag.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: anonymous, date: Date()))

        try AdoptLocalHistoryRetag.retagAndAdopt(
            anonymousMemberId: anonymous,
            canonicalMemberId: canonical,
            in: context,
            performanceDataAccess: dataAccess
        )
        try AdoptLocalHistoryRetag.retagAndAdopt(
            anonymousMemberId: anonymous,
            canonicalMemberId: canonical,
            in: context,
            performanceDataAccess: dataAccess
        )

        #expect(try dataAccess.fetchSessions(memberId: anonymous).isEmpty)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 1)
        #expect(AccessControl.persistedMemberId() == canonical)
    }

    @Test
    @MainActor
    func completePendingAdoptFinishesAfterSwiftDataSaveWithoutUserDefaultsAdopt() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        AdoptLocalHistoryRetag.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            AdoptLocalHistoryRetag.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: anonymous, date: Date()))
        defaults.set(anonymous.uuidString, forKey: AdoptLocalHistoryRetag.pendingAdoptFromKey)
        defaults.set(canonical.uuidString, forKey: AdoptLocalHistoryRetag.pendingAdoptToKey)

        // Simulate save succeeded but adoptCanonicalMemberId did not run.
        for session in try dataAccess.fetchSessions(memberId: anonymous) {
            session.memberId = canonical
        }
        try context.save()

        try AdoptLocalHistoryRetag.completePendingAdoptIfNeeded(
            in: context,
            performanceDataAccess: dataAccess
        )

        #expect(AccessControl.persistedMemberId() == canonical)
        #expect(defaults.string(forKey: AdoptLocalHistoryRetag.pendingAdoptFromKey) == nil)
    }

    @Test
    @MainActor
    func branchContractRetagWhenAdoptedWithLocalHistory() throws {
        // #33 discard only when adopted AND local AND cloud history.
        // Re-tag runs on proceedToUpload when adopted AND local (cloud empty is the
        // branch gate that avoids discard — retag is keyed on captured anonymous id).
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let deviceId = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: deviceId, date: Date()))
        #expect(deviceId != canonical)
        #expect(
            try LocalMemberHistoryProbe.hasLocalHistory(
                memberId: deviceId,
                in: context,
                performanceDataAccess: dataAccess
            )
        )

        let shouldRetag = canonical != deviceId
        #expect(shouldRetag == true)
    }

    @Test
    @MainActor
    func resolvePriorDeviceMemberIdPrefersPendingMarker() {
        let (defaults, suite) = makeIsolatedDefaults()
        AdoptLocalHistoryRetag.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AdoptLocalHistoryRetag.userDefaults = .standard
        }

        let prior = UUID()
        let canonical = UUID()
        let other = UUID()
        defaults.set(prior.uuidString, forKey: AdoptLocalHistoryRetag.pendingAdoptFromKey)
        defaults.set(canonical.uuidString, forKey: AdoptLocalHistoryRetag.pendingAdoptToKey)

        #expect(AdoptLocalHistoryRetag.resolvePriorDeviceMemberId(canonicalMemberId: canonical) == prior)
        #expect(AdoptLocalHistoryRetag.resolvePriorDeviceMemberId(canonicalMemberId: other) == nil)
    }

    @Test
    @MainActor
    func syncCycleHealRetagsStrandedRowsThenUploadPushes() async throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        AdoptLocalHistoryRetag.userDefaults = defaults
        MemberConnectionStore.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            AdoptLocalHistoryRetag.userDefaults = .standard
            MemberConnectionStore.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()
        #expect(anonymous != canonical)

        let exercise = ExerciseModel(
            id: UUID(),
            name: "Stranded Lift",
            category: .pbExercise,
            measurementType: .weightAndReps,
            pbRule: .heaviestWeightAtReps,
            displayOrder: 1
        )
        context.insert(exercise)

        let session = SessionModel(memberId: anonymous, date: Date())
        try dataAccess.saveSession(session)
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exercise.id)
        try dataAccess.saveExerciseEntry(entry)
        try dataAccess.saveSet(ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 3))

        MemberConnectionStore.save(
            session: BrokerSession(
                token: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            claims: JWTClaimsDecoder.Claims(memberId: canonical, gymId: UUID())
        )

        let healed = try AdoptLocalHistoryRetag.healStrandedLocalHistoryIfNeeded(
            canonicalMemberId: canonical,
            skipWhenCloudHasMemberHistory: false,
            in: context,
            performanceDataAccess: dataAccess
        )
        #expect(healed == true)
        #expect(AccessControl.persistedMemberId() == canonical)
        #expect(try dataAccess.fetchSessions(memberId: anonymous).isEmpty)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 1)

        let cloud = MockSyncServiceAccess()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable",
            accessToken: "token",
            memberId: canonical,
            gymId: UUID(),
            deviceId: UUID()
        )
        let push = await FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials
        ).upload(memberId: canonical)

        #expect(push.completed == true)
        #expect(push.counts.total > 0)
        #expect(push.counts.sessions == 1)

        let healedAgain = try AdoptLocalHistoryRetag.healStrandedLocalHistoryIfNeeded(
            canonicalMemberId: canonical,
            skipWhenCloudHasMemberHistory: false,
            in: context,
            performanceDataAccess: dataAccess
        )
        #expect(healedAgain == false)
    }

    @Test
    @MainActor
    func syncCycleHealSkippedWhenCloudHasMemberHistory() throws {
        let (defaults, suite) = makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        AdoptLocalHistoryRetag.userDefaults = defaults
        MemberConnectionStore.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            AdoptLocalHistoryRetag.userDefaults = .standard
            MemberConnectionStore.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: anonymous, date: Date()))

        MemberConnectionStore.save(
            session: BrokerSession(
                token: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600)
            ),
            claims: JWTClaimsDecoder.Claims(memberId: canonical, gymId: UUID())
        )

        let healed = try AdoptLocalHistoryRetag.healStrandedLocalHistoryIfNeeded(
            canonicalMemberId: canonical,
            skipWhenCloudHasMemberHistory: true,
            in: context,
            performanceDataAccess: dataAccess
        )
        #expect(healed == false)
        #expect(AccessControl.persistedMemberId() == anonymous)
        #expect(try dataAccess.fetchSessions(memberId: anonymous).count == 1)
    }
}
#endif
