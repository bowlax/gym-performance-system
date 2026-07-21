import Foundation
import SwiftData

/// Entry point for sync operations: first-connect push and full pull-merge-push cycles.
///
/// Anonymous-local-then-adopt with existing cloud data is **discard-cloud-wins** (#33),
/// orchestrated by `ConnectFlowService.discardLocalAndPullFromCloud` — not merge/re-parent.
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
            let (credentials, _) = try makeCredentials(from: brokerSession)
            return await runFullSyncCycle(
                brokerSession: brokerSession,
                credentials: credentials,
                syncServiceAccess: PostgRESTSyncServiceAccess(credentials: credentials)
            )
        } catch {
            return SyncCycleResult(
                pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: error),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
    }

    /// Test / harness entry: inject `SyncServiceAccess` for pull-merge-push.
    func runFullSyncCycle(
        brokerSession: BrokerSession,
        syncServiceAccess: SyncServiceAccess
    ) async -> SyncCycleResult {
        do {
            let (credentials, _) = try makeCredentials(from: brokerSession)
            return await runFullSyncCycle(
                brokerSession: brokerSession,
                credentials: credentials,
                syncServiceAccess: syncServiceAccess
            )
        } catch {
            return SyncCycleResult(
                pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: error),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
    }

    private func runFullSyncCycle(
        brokerSession: BrokerSession,
        credentials: SyncCredentials,
        syncServiceAccess: SyncServiceAccess
    ) async -> SyncCycleResult {
        do {
            let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token)
            let localDataAccess = SwiftDataSyncLocalDataAccess(context: modelContext)

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

            let performanceDataAccess = SwiftDataPerformanceDataAccess(context: modelContext)
            try AdoptLocalHistoryRetag.healStrandedLocalHistoryIfNeeded(
                canonicalMemberId: claims.memberId,
                skipWhenCloudHasMemberHistory: pull.mergeCounts.total > 0,
                in: modelContext,
                performanceDataAccess: performanceDataAccess
            )

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
        guard let brokerURL = GymPerfCloudConfig.tokenBrokerURL,
              let publishableKey = GymPerfCloudConfig.publishableKey else {
            throw SyncError.cloudNotConfigured
        }

        let deviceMemberId = GymPerfCloudConfig.testDeviceMemberId
            ?? AccessControl.persistedMemberId()

        #if DEBUG
        let broker: TokenBrokerClient = StubTeamUpTokenBroker(
            brokerURL: brokerURL,
            publishableKey: publishableKey
        )
        #else
        let broker: TokenBrokerClient = ReleaseBlockedTokenBroker()
        #endif

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
