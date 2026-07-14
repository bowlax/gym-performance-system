import Foundation
import SwiftData
import Testing
@testable import GymPerformance

/// Live-cloud integration test for the first-connect upload slice.
///
/// Configure the Xcode test scheme (or `xcodebuild` env) with:
/// - `GYMPERF_SUPABASE_URL`
/// - `GYMPERF_SUPABASE_PUBLISHABLE_KEY`
/// - `GYMPERF_TEST_DEVICE_MEMBER_ID` (device id sent to broker; adopted member id may differ)
///
/// Seeds local data under the broker-adopted member id so JWT claims match session ownership.
struct FirstConnectUploadIntegrationTests {
    @Test
    @MainActor
    func uploadLocalHistoryToLiveCloud() async throws {
        guard GymPerfCloudConfig.isConfiguredForLiveSync else {
            Issue.record("GYMPERF_* environment variables are not configured")
            return
        }

        let context = try TestHelpers.makeInMemoryContext()
        let syncManager = try SyncManager.makeFromCloudConfig(modelContext: context)

        let brokerSession = try await syncManager.mintStubBrokerSession()
        let adoptedMemberId = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token).memberId

        seedSampleWorkout(context: context, memberId: adoptedMemberId)
        try context.save()

        let first = await syncManager.uploadLocalHistoryAfterConnect(brokerSession: brokerSession)
        #expect(first.completed == true, Comment(rawValue: first.errorMessage ?? "unknown error"))
        #expect(first.counts.sessions == 1)
        #expect(first.counts.exerciseEntries == 1)
        #expect(first.counts.sets == 1)
        #expect(first.counts.total > 0)

        let second = await syncManager.mintStubSessionAndUpload()
        #expect(second.completed == true)
        #expect(second.counts.total == 0, "Second run should not re-push already-synced records")
    }

    private func seedSampleWorkout(context: ModelContext, memberId: UUID) {
        let exerciseId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let session = SessionModel(memberId: memberId, date: Date(), notes: "sync integration seed")
        let entry = ExerciseEntryModel(sessionId: session.id, exerciseId: exerciseId)
        let set = ModelSet(exerciseEntryId: entry.id, weight: 60, reps: 5)
        let personalBest = PersonalBestModel(
            memberId: memberId,
            exerciseId: exerciseId,
            setId: set.id,
            weight: 60,
            reps: 5,
            achievedAt: Date()
        )
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(personalBest)
    }
}
