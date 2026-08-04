import Foundation
import SwiftData

/// Post-auth branch after the broker returns a member id (#31 / #33).
enum ConnectPostAuthBranch: Equatable, Sendable {
    /// Safe to push local history (new member, or adopted with empty cloud).
    case proceedToUpload
    /// Adopted member already has cloud data AND this device has anonymous local
    /// history. Show the discard-cloud-wins choice screen — do not auto-clear (#33).
    case discardCloudWinsChoice
    /// This install previously connected as a different member. Refuse rather than
    /// discard/retag (device-swap is unsupported for Wolf — see `disconnect()`).
    case blockedDifferentAccount
}

/// Full post-auth assessment from `ConnectFlowService.assessBranch`.
///
/// Onboarding reuses the same adopted / hasLocal / hasCloud flags that drive
/// discard-vs-upload — skip manual PB population when cloud history will (or
/// did) arrive for an adopted member.
struct ConnectBranchAssessment: Equatable, Sendable {
    var adopted: Bool
    var hasLocal: Bool
    var hasCloud: Bool
    var postAuthBranch: ConnectPostAuthBranch

    /// Adopted + cloud history → device will receive real PBs via pull / discard.
    /// Prompting hand-entry would be wrong. Same cloud signal as #33, without
    /// requiring local history (empty first-launch connect still skips populate).
    var shouldSkipManualPBPopulation: Bool {
        ConnectBranchLogic.shouldSkipManualPBPopulation(
            adopted: adopted,
            hasCloud: hasCloud
        )
    }
}

/// Pure branch resolution — unit-tested without network / SwiftData.
enum ConnectBranchLogic {
    /// Cheap post-disconnect guard: refuse connecting a *different* TeamUp account
    /// on an install that has already connected before.
    ///
    /// Device-swap after disconnect (reconnecting a DIFFERENT TeamUp account on a
    /// device that previously connected as someone else) is a known unhandled case.
    /// Accepted because Wolf's member population does not share devices. If that
    /// assumption ever changes, the identity model needs the fuller fix (stable
    /// device id separate from adopted member id) before this scenario is safe.
    static func shouldBlockDifferentAccount(
        hasEverConnected: Bool,
        lastConnectedMemberId: UUID?,
        persistedMemberId: UUID,
        jwtMemberId: UUID
    ) -> Bool {
        guard hasEverConnected else { return false }
        if jwtMemberId == persistedMemberId { return false }
        if let lastConnectedMemberId, jwtMemberId == lastConnectedMemberId {
            return false
        }
        // hasEverConnected with no recorded last id (shouldn't happen after migrate):
        // still block when JWT ≠ persisted — visible refusal over silent retag.
        return true
    }

    static func postAuthBranch(
        adopted: Bool,
        hasLocal: Bool,
        hasCloud: Bool
    ) -> ConnectPostAuthBranch {
        if adopted && hasLocal && hasCloud {
            return .discardCloudWinsChoice
        }
        return .proceedToUpload
    }

    static func shouldSkipManualPBPopulation(adopted: Bool, hasCloud: Bool) -> Bool {
        adopted && hasCloud
    }

    static let blockedDifferentAccountMessage = """
        This device was previously connected to a different account. Contact \
        privacy@lbconsulting.tech before connecting a different account on this device.
        """
}

/// Orchestrates authenticate → post-auth branch → connect sync (#31).
@MainActor
final class ConnectFlowService {
    private let modelContext: ModelContext
    private let performanceDataAccess: PerformanceDataAccess
    private let authClient: ConnectAuthClient
    private let deviceMemberId: UUID
    private let syncCycleRunner: @MainActor (BrokerSession) async -> SyncCycleResult

    init(
        modelContext: ModelContext,
        performanceDataAccess: PerformanceDataAccess,
        authClient: ConnectAuthClient,
        deviceMemberId: UUID = AccessControl.persistedMemberId(),
        syncCycleRunner: (@MainActor (BrokerSession) async -> SyncCycleResult)? = nil
    ) throws {
        self.modelContext = modelContext
        self.performanceDataAccess = performanceDataAccess
        self.authClient = authClient
        self.deviceMemberId = deviceMemberId
        if let syncCycleRunner {
            self.syncCycleRunner = syncCycleRunner
        } else {
            self.syncCycleRunner = { session in
                do {
                    let manager = try SyncManager.makeFromCloudConfig(modelContext: modelContext)
                    return await manager.runFullSyncCycle(brokerSession: session)
                } catch {
                    return SyncCycleResult(
                        pull: .interrupted(
                            mergeCounts: SyncMergeCounts(),
                            highWaterSyncedAt: nil,
                            error: error
                        ),
                        push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
                    )
                }
            }
        }
        try AdoptLocalHistoryRetag.completePendingAdoptIfNeeded(
            in: modelContext,
            performanceDataAccess: performanceDataAccess
        )
    }

    static func makeFromCloudConfig(
        modelContext: ModelContext,
        performanceDataAccess: PerformanceDataAccess
    ) throws -> ConnectFlowService {
        guard let brokerURL = GymPerfCloudConfig.tokenBrokerURL,
              let publishableKey = GymPerfCloudConfig.publishableKey else {
            throw SyncError.cloudNotConfigured
        }
        #if DEBUG
        let authClient: ConnectAuthClient = if GymPerfCloudConfig.useRealOAuth {
            OAuthConnectAuthClient(
                brokerAuthorizeBaseURL: brokerURL,
                publishableKey: publishableKey
            )
        } else {
            StubConnectAuthClient(
                brokerURL: brokerURL,
                publishableKey: publishableKey
            )
        }
        #else
        let authClient = OAuthConnectAuthClient(
            brokerAuthorizeBaseURL: brokerURL,
            publishableKey: publishableKey
        )
        #endif
        return try ConnectFlowService(
            modelContext: modelContext,
            performanceDataAccess: performanceDataAccess,
            authClient: authClient,
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
    ) async throws -> ConnectBranchAssessment {
        MemberConnectionStore.migrateEverConnectedFlagsIfNeeded()

        if ConnectBranchLogic.shouldBlockDifferentAccount(
            hasEverConnected: MemberConnectionStore.hasEverConnected,
            lastConnectedMemberId: MemberConnectionStore.lastConnectedMemberId,
            persistedMemberId: deviceMemberId,
            jwtMemberId: claims.memberId
        ) {
            return ConnectBranchAssessment(
                adopted: claims.memberId != deviceMemberId,
                hasLocal: false,
                hasCloud: false,
                postAuthBranch: .blockedDifferentAccount
            )
        }

        let adopted = claims.memberId != deviceMemberId
        let hasLocal = try LocalMemberHistoryProbe.hasLocalHistory(
            memberId: deviceMemberId,
            in: modelContext,
            performanceDataAccess: performanceDataAccess
        )
        // Probe cloud whenever adopted — needed both for #33 discard and for
        // first-launch skip-populate (adopted + cloud, often with empty local).
        let hasCloud: Bool
        if adopted {
            hasCloud = try await cloudHasHistory(session: session, claims: claims)
        } else {
            hasCloud = false
        }

        return ConnectBranchAssessment(
            adopted: adopted,
            hasLocal: hasLocal,
            hasCloud: hasCloud,
            postAuthBranch: ConnectBranchLogic.postAuthBranch(
                adopted: adopted,
                hasLocal: hasLocal,
                hasCloud: hasCloud
            )
        )
    }

    /// Retag/adopt BEFORE pull-merge-push, then run a full sync cycle.
    func syncAfterConnect(session: BrokerSession) async -> SyncCycleResult {
        do {
            let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: session.token)
            if claims.memberId != deviceMemberId {
                try AdoptLocalHistoryRetag.retagAndAdopt(
                    anonymousMemberId: deviceMemberId,
                    canonicalMemberId: claims.memberId,
                    in: modelContext,
                    performanceDataAccess: performanceDataAccess
                )
            }
        } catch {
            return SyncCycleResult(
                pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: error),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
        return await syncCycleRunner(session)
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
