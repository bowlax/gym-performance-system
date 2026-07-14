import Foundation
import SwiftData

/// Entry point for sync operations: first-connect push and full pull-merge-push cycles.
///
/// The anonymous-local-then-adopt edge case (pre-existing anonymous local data adopting an
/// existing member) is intentionally not handled here.
@MainActor
final class SyncManager {
    private let modelContext: ModelContext
    private let tokenBroker: TokenBrokerClient
    private let deviceMemberId: UUID

    init(
        modelContext: ModelContext,
        tokenBroker: TokenBrokerClient,
        deviceMemberId: UUID
    ) {
        self.modelContext = modelContext
        self.tokenBroker = tokenBroker
        self.deviceMemberId = deviceMemberId
    }

    /// Runs the resumable first-connect bulk upload after a successful broker connect.
    func uploadLocalHistoryAfterConnect(brokerSession: BrokerSession) async -> FirstConnectUploadResult {
        do {
            let (credentials, claims) = try makeCredentials(from: brokerSession)
            return await makeUploader(credentials: credentials).upload(memberId: claims.memberId)
        } catch {
            return .interrupted(counts: FirstConnectUploadCounts(), error: error)
        }
    }

    /// Full sync cycle: PULL → MERGE → PUSH. Pull first so local merges land before push.
    func runFullSyncCycle(brokerSession: BrokerSession) async -> SyncCycleResult {
        do {
            let (credentials, claims) = try makeCredentials(from: brokerSession)
            let localDataAccess = SwiftDataSyncLocalDataAccess(context: modelContext)
            let syncServiceAccess = PostgRESTSyncServiceAccess(credentials: credentials)

            let puller = SyncPuller(
                localDataAccess: localDataAccess,
                syncServiceAccess: syncServiceAccess,
                memberId: claims.memberId
            )
            let pull = await puller.pullAndMerge()
            if !pull.completed {
                return SyncCycleResult(
                    pull: pull,
                    push: FirstConnectUploadResult(
                        counts: FirstConnectUploadCounts(),
                        completed: false,
                        errorMessage: "Push skipped because pull did not complete"
                    )
                )
            }

            let push = await makeUploader(
                credentials: credentials,
                localDataAccess: localDataAccess,
                syncServiceAccess: syncServiceAccess
            ).upload(memberId: claims.memberId)

            return SyncCycleResult(pull: pull, push: push)
        } catch {
            return SyncCycleResult(
                pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: error),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
    }

    /// Convenience for tests: mint stub broker session then run a full cycle.
    func mintStubSessionAndRunFullSyncCycle() async -> SyncCycleResult {
        do {
            let brokerSession = try await mintStubBrokerSession()
            return await runFullSyncCycle(brokerSession: brokerSession)
        } catch {
            return SyncCycleResult(
                pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: error),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
    }

    /// Convenience for tests and manual harnesses: mint stub broker session then upload.
    func mintStubSessionAndUpload() async -> FirstConnectUploadResult {
        do {
            let brokerSession = try await mintStubBrokerSession()
            return await uploadLocalHistoryAfterConnect(brokerSession: brokerSession)
        } catch {
            return .interrupted(counts: FirstConnectUploadCounts(), error: error)
        }
    }

    /// Mints a stub broker session using the configured device member id.
    func mintStubBrokerSession() async throws -> BrokerSession {
        try await tokenBroker.mintStubSession(deviceMemberId: deviceMemberId)
    }

    static func makeFromCloudConfig(modelContext: ModelContext) throws -> SyncManager {
        guard let supabaseURL = GymPerfCloudConfig.supabaseURL,
              let publishableKey = GymPerfCloudConfig.publishableKey,
              let brokerURL = GymPerfCloudConfig.tokenBrokerURL,
              let deviceMemberId = GymPerfCloudConfig.testDeviceMemberId else {
            throw SyncError.cloudNotConfigured
        }

        let broker = StubTeamUpTokenBroker(
            brokerURL: brokerURL,
            publishableKey: publishableKey
        )
        return SyncManager(
            modelContext: modelContext,
            tokenBroker: broker,
            deviceMemberId: deviceMemberId
        )
    }

    private func makeCredentials(
        from brokerSession: BrokerSession
    ) throws -> (SyncCredentials, JWTClaimsDecoder.Claims) {
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token)
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
        return (credentials, claims)
    }

    private func makeUploader(
        credentials: SyncCredentials,
        localDataAccess: SyncLocalDataAccess? = nil,
        syncServiceAccess: SyncServiceAccess? = nil
    ) -> FirstConnectUploader {
        FirstConnectUploader(
            localDataAccess: localDataAccess ?? SwiftDataSyncLocalDataAccess(context: modelContext),
            syncServiceAccess: syncServiceAccess ?? PostgRESTSyncServiceAccess(credentials: credentials),
            credentials: credentials
        )
    }
}
