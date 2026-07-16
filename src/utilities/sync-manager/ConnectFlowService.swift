import Foundation
import SwiftData

/// Post-auth branch after the broker returns a member id (#31 / #33).
enum ConnectPostAuthBranch: Equatable, Sendable {
    /// Safe to push local history (new member, or adopted with empty cloud).
    case proceedToUpload
    /// Adopted member already has cloud data AND this device has anonymous local
    /// history. Show the discard-cloud-wins choice screen — do not auto-clear (#33).
    case discardCloudWinsChoice
}

/// Orchestrates authenticate → post-auth branch → first-connect upload (#31).
@MainActor
final class ConnectFlowService {
    private let modelContext: ModelContext
    private let performanceDataAccess: PerformanceDataAccess
    private let authClient: ConnectAuthClient
    private let deviceMemberId: UUID

    init(
        modelContext: ModelContext,
        performanceDataAccess: PerformanceDataAccess,
        authClient: ConnectAuthClient,
        deviceMemberId: UUID = AccessControl.persistedMemberId()
    ) {
        self.modelContext = modelContext
        self.performanceDataAccess = performanceDataAccess
        self.authClient = authClient
        self.deviceMemberId = deviceMemberId
    }

    static func makeFromCloudConfig(
        modelContext: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws -> ConnectFlowService {
        guard let brokerURL = GymPerfCloudConfig.tokenBrokerURL,
              let publishableKey = GymPerfCloudConfig.publishableKey else {
            throw SyncError.cloudNotConfigured
        }
        return ConnectFlowService(
            modelContext: modelContext,
            performanceDataAccess: performanceDataAccess,
            authClient: StubConnectAuthClient(
                brokerURL: brokerURL,
                publishableKey: publishableKey
            ),
            deviceMemberId: AccessControl.persistedMemberId()
        )
    }

    func authenticate() async throws -> (BrokerSession, JWTClaimsDecoder.Claims) {
        let session = try await authClient.authenticate(deviceMemberId: deviceMemberId)
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: session.token)
        return (session, claims)
    }

    func assessBranch(
        session: BrokerSession,
        claims: JWTClaimsDecoder.Claims
    ) async throws -> ConnectPostAuthBranch {
        let adopted = claims.memberId != deviceMemberId
        let hasLocal = try LocalMemberHistoryProbe.hasLocalHistory(
            memberId: deviceMemberId,
            in: modelContext,
            performanceDataAccess: performanceDataAccess
        )
        guard adopted, hasLocal else {
            return .proceedToUpload
        }

        let hasCloud = try await cloudHasHistory(session: session, claims: claims)
        return hasCloud ? .discardCloudWinsChoice : .proceedToUpload
    }

    func uploadLocalHistory(session: BrokerSession) async -> FirstConnectUploadResult {
        guard let brokerURL = GymPerfCloudConfig.tokenBrokerURL,
              let publishableKey = GymPerfCloudConfig.publishableKey else {
            return .interrupted(
                counts: FirstConnectUploadCounts(),
                error: SyncError.cloudNotConfigured
            )
        }
        let syncManager = SyncManager(
            modelContext: modelContext,
            tokenBroker: StubTeamUpTokenBroker(
                brokerURL: brokerURL,
                publishableKey: publishableKey
            ),
            deviceMemberId: deviceMemberId
        )
        return await syncManager.uploadLocalHistoryAfterConnect(brokerSession: session)
    }

    func persistConnected(session: BrokerSession, claims: JWTClaimsDecoder.Claims) {
        MemberConnectionStore.save(session: session, claims: claims)
    }

    /// Discard-cloud-wins (#33): clear anonymous local history, adopt canonical id, pull.
    ///
    /// If clear succeeds and pull fails, the member is already connected with an empty
    /// device — cloud history is intact. Next Sync now / foreground pull recovers it.
    /// We do **not** roll back the clear (anonymous data is gone by design once they Proceed).
    func discardLocalAndPullFromCloud(
        session: BrokerSession,
        claims: JWTClaimsDecoder.Claims
    ) async -> DiscardCloudWinsResult {
        let anonymousId = deviceMemberId
        do {
            try DiscardCloudWins.clearAnonymousLocalHistory(
                anonymousMemberId: anonymousId,
                in: modelContext,
                performanceDataAccess: performanceDataAccess
            )
        } catch {
            return .failedBeforeClear(error: error)
        }

        SyncLastPullMarker.clear(memberId: anonymousId)
        SyncLastPullMarker.clear(memberId: claims.memberId)
        SyncStatusStore.clear(memberId: anonymousId)
        SyncStatusStore.clear(memberId: claims.memberId)

        AccessControl.adoptCanonicalMemberId(claims.memberId)
        persistConnected(session: session, claims: claims)

        return await pullAccountHistory(session: session, claims: claims, afterClear: true)
    }

    /// Retry pull only (local already cleared / connected after a failed discard pull).
    func retryPullAfterDiscard(
        session: BrokerSession,
        claims: JWTClaimsDecoder.Claims
    ) async -> DiscardCloudWinsResult {
        await pullAccountHistory(session: session, claims: claims, afterClear: true)
    }

    private func pullAccountHistory(
        session: BrokerSession,
        claims: JWTClaimsDecoder.Claims,
        afterClear: Bool
    ) async -> DiscardCloudWinsResult {
        do {
            guard let publishableKey = GymPerfCloudConfig.publishableKey,
                  let supabaseURL = GymPerfCloudConfig.supabaseURL else {
                throw SyncError.cloudNotConfigured
            }
            let credentials = SyncCredentials(
                supabaseURL: supabaseURL,
                publishableKey: publishableKey,
                accessToken: session.token,
                memberId: claims.memberId,
                gymId: claims.gymId,
                deviceId: SyncDeviceIdentity.persistedDeviceId()
            )
            let puller = SyncPuller(
                localDataAccess: SwiftDataSyncLocalDataAccess(context: modelContext),
                syncServiceAccess: PostgRESTSyncServiceAccess(credentials: credentials),
                memberId: claims.memberId
            )
            let pull = await puller.pullAndMerge()
            if pull.completed {
                SyncStatusStore.recordSuccess(memberId: claims.memberId)
            } else if afterClear {
                SyncStatusStore.recordFailure(
                    memberId: claims.memberId,
                    message: pull.errorMessage ?? "Couldn’t download account history"
                )
            }
            return .clearedThenPull(pull)
        } catch {
            if afterClear {
                SyncStatusStore.recordFailure(
                    memberId: claims.memberId,
                    message: error.localizedDescription
                )
            }
            return DiscardCloudWinsResult(
                cleared: afterClear,
                pull: .interrupted(
                    mergeCounts: SyncMergeCounts(),
                    highWaterSyncedAt: nil,
                    error: error
                ),
                completed: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func cloudHasHistory(
        session: BrokerSession,
        claims: JWTClaimsDecoder.Claims
    ) async throws -> Bool {
        guard let publishableKey = GymPerfCloudConfig.publishableKey,
              let supabaseURL = GymPerfCloudConfig.supabaseURL else {
            throw SyncError.cloudNotConfigured
        }
        let credentials = SyncCredentials(
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            accessToken: session.token,
            memberId: claims.memberId,
            gymId: claims.gymId,
            deviceId: SyncDeviceIdentity.persistedDeviceId()
        )
        let access = PostgRESTSyncServiceAccess(credentials: credentials)
        let sessions = try await access.pullSessions(since: nil)
        if sessions.contains(where: { $0.deletedAt == nil }) { return true }
        let pbs = try await access.pullPersonalBests(since: nil)
        if pbs.contains(where: { $0.deletedAt == nil }) { return true }
        let resets = try await access.pullExerciseResets(since: nil)
        return resets.contains(where: { $0.deletedAt == nil })
    }
}
