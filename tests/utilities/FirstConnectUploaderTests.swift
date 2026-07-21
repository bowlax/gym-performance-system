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
    var failOnTable: String?

    func upsertSessions(_ rows: [[String: Any]]) async throws {
        if failOnTable == "sessions" {
            throw SyncError.uploadFailed(table: "sessions", statusCode: 500, detail: "injected")
        }
        sessionBatches.append(rows)
    }

    func upsertExerciseEntries(_ rows: [[String: Any]]) async throws {
        if failOnTable == "exercise_entries" {
            throw SyncError.uploadFailed(table: "exercise_entries", statusCode: 500, detail: "injected")
        }
        entryBatches.append(rows)
    }

    func upsertSets(_ rows: [[String: Any]]) async throws {
        if failOnTable == "sets" {
            throw SyncError.uploadFailed(table: "sets", statusCode: 500, detail: "injected")
        }
        setBatches.append(rows)
    }

    func upsertPersonalBests(_ rows: [[String: Any]]) async throws {
        if failOnTable == "personal_bests" {
            throw SyncError.uploadFailed(table: "personal_bests", statusCode: 500, detail: "injected")
        }
        pbBatches.append(rows)
    }

    func upsertExerciseResets(_ rows: [[String: Any]]) async throws {
        if failOnTable == "exercise_resets" {
            throw SyncError.uploadFailed(table: "exercise_resets", statusCode: 500, detail: "injected")
        }
        exerciseResetBatches.append(rows)
    }

    var patchMemberUpdated = true
    private(set) var memberPatches: [[String: Any]] = []

    func patchMemberSettings(memberId: UUID, fields: [String: Any]) async throws -> Bool {
        if failOnTable == "members" {
            throw SyncError.uploadFailed(table: "members", statusCode: 500, detail: "injected")
        }
        memberPatches.append(fields)
        _ = memberId
        return patchMemberUpdated
    }

    func pullSessions(since: Date?) async throws -> [CloudSessionRow] { [] }
    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow] { [] }
    func pullSets(since: Date?) async throws -> [CloudSetRow] { [] }
    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow] { [] }
    func pullMembers(since: Date?) async throws -> [CloudMemberRow] { [] }
    func pullExerciseResets(since: Date?) async throws -> [CloudExerciseResetRow] { [] }
}

struct FirstConnectUploaderTests {
    @Test
    @MainActor
    func uploadMarksRecordsAndIsResumableAfterPartialFailure() async throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let cloud = MockSyncServiceAccess()
        cloud.failOnTable = "sets"

        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "test-key",
            accessToken: "token",
            memberId: memberId,
            gymId: gymId,
            deviceId: UUID()
        )

        let session = SessionModel(memberId: memberId, date: Date())
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: UUID())
        let set = ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 5)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        try context.save()

        let uploader = FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials,
            batchSize: 10
        )

        let first = await uploader.upload(memberId: memberId)
        #expect(first.completed == false)
        #expect(first.counts.sessions == 1)
        #expect(first.counts.exerciseEntries == 1)
        #expect(first.counts.sets == 0)
        #expect(session.syncedAt != nil)
        #expect(entry.syncedAt != nil)
        #expect(set.syncedAt == nil)

        cloud.failOnTable = nil
        let second = await uploader.upload(memberId: memberId)
        #expect(second.completed == true)
        #expect(second.counts.sessions == 0)
        #expect(second.counts.exerciseEntries == 0)
        #expect(second.counts.sets == 1)
        #expect(set.syncedAt != nil)
        #expect(cloud.sessionBatches.count == 1)
        #expect(cloud.entryBatches.count == 1)
        #expect(cloud.setBatches.count == 1)
    }

    @Test
    @MainActor
    func uploadSkipsOrphanChildrenForOtherMembers() async throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let cloud = MockSyncServiceAccess()

        let syncedMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let otherMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000099")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "test-key",
            accessToken: "token",
            memberId: syncedMemberId,
            gymId: gymId,
            deviceId: UUID()
        )

        let ownedSession = SessionModel(memberId: syncedMemberId, date: Date())
        let ownedEntry = ExerciseEntryModel(sessionId: ownedSession.id, exerciseId: UUID())
        let ownedSet = ModelSet(exerciseEntryId: ownedEntry.id, weight: 50, reps: 5)

        let orphanSession = SessionModel(memberId: otherMemberId, date: Date())
        let orphanEntry = ExerciseEntryModel(sessionId: orphanSession.id, exerciseId: UUID())
        let orphanSet = ModelSet(exerciseEntryId: orphanEntry.id, weight: 70, reps: 3)

        context.insert(ownedSession)
        context.insert(ownedEntry)
        context.insert(ownedSet)
        context.insert(orphanSession)
        context.insert(orphanEntry)
        context.insert(orphanSet)
        try context.save()

        let uploader = FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials,
            batchSize: 10
        )

        let result = await uploader.upload(memberId: syncedMemberId)
        #expect(result.completed == true)
        #expect(result.counts.sessions == 1)
        #expect(result.counts.exerciseEntries == 1)
        #expect(result.counts.sets == 1)
        #expect(orphanEntry.syncedAt == nil)
        #expect(orphanSet.syncedAt == nil)
        #expect(cloud.entryBatches.flatMap { $0 }.count == 1)
        #expect(cloud.setBatches.flatMap { $0 }.count == 1)
    }

    @Test
    @MainActor
    func uploadMemberSettingsSkipsWhenCloudMemberMissing() async throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let cloud = MockSyncServiceAccess()
        cloud.patchMemberUpdated = false

        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "test-key",
            accessToken: "token",
            memberId: memberId,
            gymId: UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!,
            deviceId: UUID()
        )

        let member = UserIdentityModel(
            id: memberId,
            role: .member,
            displayName: "Lee",
            stalenessEnabled: true
        )
        context.insert(member)
        try context.save()

        let uploader = FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials,
            batchSize: 10
        )

        let result = await uploader.upload(memberId: memberId)
        #expect(result.completed == false)
        #expect(result.errorMessage == SyncError.memberIdentityNotEstablished.localizedDescription)
        #expect(member.syncedAt == nil)
        #expect(cloud.memberPatches.count == 1)
        #expect(cloud.memberPatches[0]["id"] == nil)
        #expect(cloud.memberPatches[0]["gym_id"] == nil)
        #expect(result.counts.sessions == 0)
    }

    @Test
    @MainActor
    func uploadPersonalBestsReUpsertsReferencedSetsEvenWhenClean() async throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let cloud = MockSyncServiceAccess()

        let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        let credentials = SyncCredentials(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "test-key",
            accessToken: "token",
            memberId: memberId,
            gymId: gymId,
            deviceId: UUID()
        )

        let exerciseId = UUID()
        let session = SessionModel(memberId: memberId, date: Date())
        session.syncedAt = Date()
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exerciseId)
        entry.syncedAt = Date()
        let set = ModelSet(exerciseEntryId: entry.id, weight: 100, reps: 5)
        set.syncedAt = Date()
        let pb = PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            setId: set.id,
            weight: 100,
            reps: 5,
            achievedAt: Date(),
            entryType: .sessionDerived
        )
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(pb)
        try context.save()

        let uploader = FirstConnectUploader(
            localDataAccess: local,
            syncServiceAccess: cloud,
            credentials: credentials,
            batchSize: 10
        )

        let result = await uploader.upload(memberId: memberId)
        #expect(result.completed == true)
        #expect(result.counts.sessions == 0)
        #expect(result.counts.exerciseEntries == 0)
        #expect(result.counts.sets == 0)
        #expect(result.counts.personalBests == 1)
        #expect(cloud.sessionBatches.count == 1)
        #expect(cloud.entryBatches.count == 1)
        #expect(cloud.setBatches.count == 1)
        #expect(cloud.pbBatches.count == 1)
        #expect(cloud.pbBatches.first?.first?["set_id"] as? String == set.id.uuidString)
    }
}
