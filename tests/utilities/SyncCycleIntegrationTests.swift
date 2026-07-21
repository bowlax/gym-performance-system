import Foundation
import SwiftData
import Testing
@testable import GymPerformance

/// Live-cloud integration test for the full pull-merge-push cycle.
///
/// Requires:
/// - `GYMPERF_SUPABASE_URL`
/// - `GYMPERF_SUPABASE_PUBLISHABLE_KEY`
/// - `GYMPERF_TEST_DEVICE_MEMBER_ID` (optional DEBUG override for stub broker device id)
struct SyncCycleIntegrationTests {
    @Test
    @MainActor
    func fullCycleMergesCloudChangeAndSecondCycleIsIdempotent() async throws {
        guard GymPerfCloudConfig.isConfiguredForLiveSync else {
            return
        }

        let context = try TestHelpers.makeInMemoryContext()
        let syncManager = try SyncManager.makeFromCloudConfig(modelContext: context)

        let brokerSession = try await syncManager.mintStubBrokerSession()
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token)
        SyncLastPullMarker.clear(memberId: claims.memberId)

        let exerciseId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let session = SessionModel(
            memberId: claims.memberId,
            date: Date(),
            notes: "cycle seed \(UUID().uuidString.prefix(8))"
        )
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exerciseId)
        let set = ModelSet(exerciseEntryId: entry.id, weight: 75, reps: 5)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        try context.save()

        let pushOnly = await syncManager.uploadLocalHistoryAfterConnect(brokerSession: brokerSession)
        #expect(pushOnly.completed == true, Comment(rawValue: pushOnly.errorMessage ?? "push failed"))
        #expect(pushOnly.counts.sessions == 1)
        #expect(pushOnly.counts.exerciseEntries == 1)
        #expect(pushOnly.counts.sets == 1)

        // Simulate a cloud-side edit after our push (member JWT + PostgREST upsert).
        let cloudEditedNotes = "cloud edit \(UUID().uuidString.prefix(8))"
        let cloudSyncedAt = Date().addingTimeInterval(2)
        try await simulateCloudSessionUpdate(
            brokerSession: brokerSession,
            claims: claims,
            session: session,
            notes: cloudEditedNotes,
            updatedAt: Date().addingTimeInterval(1),
            syncedAt: cloudSyncedAt
        )

        // Local still has the pre-edit notes and syncedAt from the first push.
        #expect(session.notes != cloudEditedNotes)

        let firstCycle = await syncManager.runFullSyncCycle(brokerSession: brokerSession)
        #expect(firstCycle.completed == true, Comment(rawValue: firstCycle.errorMessage ?? "cycle failed"))
        #expect(firstCycle.pull.mergeCounts.total >= 1)
        #expect(session.notes == cloudEditedNotes)
        #expect(session.syncedAt != nil)
        #expect(SyncDirtiness.isDirty(updatedAt: session.updatedAt, syncedAt: session.syncedAt) == false)
        #expect(firstCycle.push.counts.total == 0)

        let secondCycle = await syncManager.runFullSyncCycle(brokerSession: brokerSession)
        #expect(secondCycle.completed == true, Comment(rawValue: secondCycle.errorMessage ?? "second cycle failed"))
        #expect(secondCycle.pull.mergeCounts.total == 0)
        #expect(secondCycle.push.counts.total == 0)
    }

    private func simulateCloudSessionUpdate(
        brokerSession: BrokerSession,
        claims: JWTClaimsDecoder.Claims,
        session: SessionModel,
        notes: String,
        updatedAt: Date,
        syncedAt: Date
    ) async throws {
        guard let publishableKey = GymPerfCloudConfig.publishableKey,
              let supabaseURL = GymPerfCloudConfig.supabaseURL else {
            throw SyncError.cloudNotConfigured
        }

        let credentials = SyncCredentials(
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            accessToken: brokerSession.token,
            memberId: claims.memberId,
            gymId: claims.gymId,
            deviceId: SyncDeviceIdentity.persistedDeviceId()
        )
        let access = PostgRESTSyncServiceAccess(credentials: credentials)
        let row = SyncPayloadMapper.sessionRow(
            SessionModel(
                id: session.id,
                memberId: claims.memberId,
                date: session.date,
                notes: notes,
                caloriesBurned: session.caloriesBurned,
                createdAt: session.createdAt,
                updatedAt: updatedAt,
                syncedAt: syncedAt
            ),
            gymId: claims.gymId,
            deviceId: credentials.deviceId,
            syncedAt: syncedAt
        )
        // Force the payload's updated_at/synced_at to the simulated cloud values.
        var forced = row
        forced["notes"] = notes
        forced["updated_at"] = ISO8601DateFormatter.syncFractional.string(from: updatedAt)
        forced["synced_at"] = ISO8601DateFormatter.syncFractional.string(from: syncedAt)
        try await access.upsertSessions([forced])
    }
}

private extension ISO8601DateFormatter {
    static let syncFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
