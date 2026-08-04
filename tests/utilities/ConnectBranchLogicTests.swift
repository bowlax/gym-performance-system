#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

@Suite
struct ConnectBranchLogicTests {

    @Test
    func declineAndNewMemberStillPopulate() {
        // Not a ConnectBranchLogic input — documents Path A / empty-cloud Path B:
        // skip only when adopted && hasCloud.
        #expect(
            !ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: false, hasCloud: false)
        )
        #expect(
            !ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: false, hasCloud: true)
        )
        #expect(
            !ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: true, hasCloud: false)
        )
    }

    @Test
    func adoptedWithCloudSkipsPopulateEvenWithoutLocalHistory() {
        // First-launch connect: empty device, adopted member, cloud has PBs.
        #expect(
            ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: true, hasCloud: true)
        )
        #expect(
            ConnectBranchLogic.postAuthBranch(
                adopted: true,
                hasLocal: false,
                hasCloud: true
            ) == .proceedToUpload
        )
    }

    @Test
    func discardCloudWinsAlsoSkipsPopulate() {
        // Same adopted+cloud signal; post-auth branch is discard when hasLocal too.
        #expect(
            ConnectBranchLogic.postAuthBranch(
                adopted: true,
                hasLocal: true,
                hasCloud: true
            ) == .discardCloudWinsChoice
        )
        #expect(
            ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: true, hasCloud: true)
        )
    }

    @Test
    func assessmentMirrorsLogic() {
        let skip = ConnectBranchAssessment(
            adopted: true,
            hasLocal: false,
            hasCloud: true,
            postAuthBranch: .proceedToUpload
        )
        #expect(skip.shouldSkipManualPBPopulation)

        let populate = ConnectBranchAssessment(
            adopted: true,
            hasLocal: false,
            hasCloud: false,
            postAuthBranch: .proceedToUpload
        )
        #expect(!populate.shouldSkipManualPBPopulation)

        let declineAnalog = ConnectBranchAssessment(
            adopted: false,
            hasLocal: false,
            hasCloud: false,
            postAuthBranch: .proceedToUpload
        )
        #expect(!declineAnalog.shouldSkipManualPBPopulation)
    }

    @Test
    func newMemberEmptyCloudProceedsToUploadAndPopulates() {
        #expect(
            ConnectBranchLogic.postAuthBranch(
                adopted: false,
                hasLocal: false,
                hasCloud: false
            ) == .proceedToUpload
        )
        #expect(
            !ConnectBranchLogic.shouldSkipManualPBPopulation(adopted: false, hasCloud: false)
        )
    }

    @Test
    func differentAccountGuardBlocksWhenJwtDiffersFromPersistedAndLastConnected() {
        let previous = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let other = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!

        #expect(
            ConnectBranchLogic.shouldBlockDifferentAccount(
                hasEverConnected: true,
                lastConnectedMemberId: previous,
                persistedMemberId: previous,
                jwtMemberId: other
            )
        )
        // Same-account reconnect after disconnect — must NOT block.
        #expect(
            !ConnectBranchLogic.shouldBlockDifferentAccount(
                hasEverConnected: true,
                lastConnectedMemberId: previous,
                persistedMemberId: previous,
                jwtMemberId: previous
            )
        )
        // First-ever connect on a virgin install — must NOT block.
        #expect(
            !ConnectBranchLogic.shouldBlockDifferentAccount(
                hasEverConnected: false,
                lastConnectedMemberId: nil,
                persistedMemberId: UUID(),
                jwtMemberId: other
            )
        )
    }

    @Test
    @MainActor
    func assessBranchReturnsBlockedWithoutDiscardOrUpload() async throws {
        let defaults = UserDefaults(
            suiteName: "ConnectBranchLogicTests.blockedAssess.\(UUID().uuidString)"
        )!
        let memory = InMemoryTokenStore()
        let previousDefaults = MemberConnectionStore.userDefaults
        let previousKeychain = KeychainTokenStore.testStore
        let previousAccess = AccessControl.userDefaults
        MemberConnectionStore.userDefaults = defaults
        KeychainTokenStore.testStore = memory
        AccessControl.userDefaults = defaults
        defer {
            MemberConnectionStore.userDefaults = previousDefaults
            KeychainTokenStore.testStore = previousKeychain
            AccessControl.userDefaults = previousAccess
        }

        let previousMember = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let otherMember = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!
        let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!
        AccessControl.adoptCanonicalMemberId(previousMember)
        MemberConnectionStore.hasEverConnected = true
        MemberConnectionStore.lastConnectedMemberId = previousMember

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        // Local history under previous member — would have triggered discard without the guard.
        try dataAccess.saveSession(SessionModel(memberId: previousMember, date: Date()))

        let service = try ConnectFlowService(
            modelContext: context,
            performanceDataAccess: dataAccess,
            authClient: BlockingGuardAuthClient(),
            deviceMemberId: previousMember,
            syncCycleRunner: { _ in
                Issue.record("Sync must not run when different-account is blocked")
                return SyncCycleResult(
                    pull: .interrupted(mergeCounts: SyncMergeCounts(), highWaterSyncedAt: nil, error: SyncError.cloudNotConfigured),
                    push: .interrupted(counts: FirstConnectUploadCounts(), error: SyncError.cloudNotConfigured)
                )
            }
        )

        let session = BrokerSession(token: "aaa.bbb.ccc", expiresAt: Date().addingTimeInterval(3600))
        let claims = JWTClaimsDecoder.Claims(memberId: otherMember, gymId: gymId)
        let assessment = try await service.assessBranch(session: session, claims: claims)

        #expect(assessment.postAuthBranch == .blockedDifferentAccount)
        #expect(MemberConnectionStore.isConnected == false)
        // Local row still under previous member — not discarded.
        #expect(try dataAccess.fetchSessions(memberId: previousMember).count == 1)
        #expect(AccessControl.persistedMemberId() == previousMember)
    }
}

private struct BlockingGuardAuthClient: ConnectAuthClient {
    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession {
        _ = deviceMemberId
        return BrokerSession(token: "aaa.bbb.ccc", expiresAt: Date().addingTimeInterval(3600))
    }
}
#endif
