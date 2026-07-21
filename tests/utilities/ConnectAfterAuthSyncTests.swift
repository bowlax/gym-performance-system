#if canImport(Testing)
import Foundation
import SwiftData
import Testing
@testable import GymPerformance

// MARK: - Test doubles

private final class ConfigurableMockSyncServiceAccess: SyncServiceAccess, @unchecked Sendable {
    var cloudSessions: [CloudSessionRow] = []
    var cloudEntries: [CloudExerciseEntryRow] = []
    var cloudSets: [CloudSetRow] = []
    var cloudPersonalBests: [CloudPersonalBestRow] = []
    var cloudMembers: [CloudMemberRow] = []
    var cloudResets: [CloudExerciseResetRow] = []
    var failPullTable: String?
    var failOnTable: String?

    private(set) var sessionBatches: [[[String: Any]]] = []

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
        _ = rows
    }

    func upsertSets(_ rows: [[String: Any]]) async throws {
        if failOnTable == "sets" {
            throw SyncError.uploadFailed(table: "sets", statusCode: 500, detail: "injected")
        }
        _ = rows
    }

    func upsertPersonalBests(_ rows: [[String: Any]]) async throws {
        if failOnTable == "personal_bests" {
            throw SyncError.uploadFailed(table: "personal_bests", statusCode: 500, detail: "injected")
        }
        _ = rows
    }

    func upsertExerciseResets(_ rows: [[String: Any]]) async throws {
        if failOnTable == "exercise_resets" {
            throw SyncError.uploadFailed(table: "exercise_resets", statusCode: 500, detail: "injected")
        }
        _ = rows
    }

    func patchMemberSettings(memberId: UUID, fields: [String: Any]) async throws -> Bool {
        _ = memberId
        _ = fields
        return true
    }

    func pullSessions(since: Date?) async throws -> [CloudSessionRow] {
        if failPullTable == "sessions" {
            throw SyncError.pullFailed(table: "sessions", statusCode: 500, detail: "injected pull")
        }
        return cloudSessions
    }

    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow] {
        if failPullTable == "exercise_entries" {
            throw SyncError.pullFailed(table: "exercise_entries", statusCode: 500, detail: "injected pull")
        }
        return cloudEntries
    }

    func pullSets(since: Date?) async throws -> [CloudSetRow] {
        if failPullTable == "sets" {
            throw SyncError.pullFailed(table: "sets", statusCode: 500, detail: "injected pull")
        }
        return cloudSets
    }

    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow] {
        if failPullTable == "personal_bests" {
            throw SyncError.pullFailed(table: "personal_bests", statusCode: 500, detail: "injected pull")
        }
        return cloudPersonalBests
    }

    func pullMembers(since: Date?) async throws -> [CloudMemberRow] {
        if failPullTable == "members" {
            throw SyncError.pullFailed(table: "members", statusCode: 500, detail: "injected pull")
        }
        return cloudMembers
    }

    func pullExerciseResets(since: Date?) async throws -> [CloudExerciseResetRow] {
        if failPullTable == "exercise_resets" {
            throw SyncError.pullFailed(table: "exercise_resets", statusCode: 500, detail: "injected pull")
        }
        return cloudResets
    }
}

private struct StubConnectAuthClient: ConnectAuthClient {
    let session: BrokerSession

    func authenticate(deviceMemberId: UUID) async throws -> BrokerSession {
        _ = deviceMemberId
        return session
    }
}

// MARK: - Helpers

private enum ConnectAfterAuthSyncTestSupport {
    static let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!

    static func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "ConnectAfterAuthSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    static func testJWT(memberId: UUID, gymId: UUID = gymId) -> String {
        let payload = """
        {"member_id":"\(memberId.uuidString)","gym_id":"\(gymId.uuidString)"}
        """
        var base64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while base64.hasSuffix("=") {
            base64.removeLast()
        }
        return "header.\(base64).signature"
    }

    static func brokerSession(canonicalMemberId: UUID) -> BrokerSession {
        BrokerSession(token: testJWT(memberId: canonicalMemberId))
    }

    @MainActor
    static func makeService(
        context: ModelContext,
        dataAccess: SwiftDataPerformanceDataAccess,
        anonymousDeviceId: UUID,
        canonicalMemberId: UUID,
        cloud: ConfigurableMockSyncServiceAccess
    ) throws -> ConnectFlowService {
        let session = brokerSession(canonicalMemberId: canonicalMemberId)
        return try ConnectFlowService(
            modelContext: context,
            performanceDataAccess: dataAccess,
            authClient: StubConnectAuthClient(session: session),
            deviceMemberId: anonymousDeviceId,
            syncCycleRunner: { brokerSession in
                let manager = SyncManager(
                    modelContext: context,
                    tokenBroker: ReleaseBlockedTokenBroker(),
                    deviceMemberId: anonymousDeviceId
                )
                return await manager.runFullSyncCycle(
                    brokerSession: brokerSession,
                    syncServiceAccess: cloud
                )
            }
        )
    }

    static func seedCloudSession(
        memberId: UUID,
        sessionId: UUID = UUID(),
        exerciseId: UUID = UUID()
    ) -> (CloudSessionRow, CloudExerciseEntryRow, CloudSetRow) {
        let now = Date()
        let session = CloudSessionRow(
            id: sessionId,
            gymId: gymId,
            memberId: memberId,
            date: now,
            notes: nil,
            caloriesBurned: nil,
            createdAt: now,
            updatedAt: now,
            syncedAt: now,
            deletedAt: nil,
            sourceDeviceId: UUID()
        )
        let entry = CloudExerciseEntryRow(
            id: UUID(),
            gymId: gymId,
            sessionId: sessionId,
            exerciseId: exerciseId,
            createdAt: now,
            updatedAt: now,
            syncedAt: now,
            deletedAt: nil,
            sourceDeviceId: UUID()
        )
        let set = CloudSetRow(
            id: UUID(),
            gymId: gymId,
            exerciseEntryId: entry.id,
            weight: 100,
            reps: 5,
            timeSeconds: nil,
            distance: nil,
            createdAt: now,
            updatedAt: now,
            syncedAt: now,
            deletedAt: nil,
            sourceDeviceId: UUID()
        )
        return (session, entry, set)
    }
}

@Suite
struct ConnectSyncProgressCopyTests {
    @Test
    func completedMessagesCoverFourCases() {
        #expect(ConnectSyncProgressCopy.completedMessage(pulled: 0, pushed: 0) == "You’re connected.")
        #expect(
            ConnectSyncProgressCopy.completedMessage(pulled: 0, pushed: 96)
                == "Uploaded 96 records from this device. You’re set."
        )
        #expect(
            ConnectSyncProgressCopy.completedMessage(pulled: 96, pushed: 0)
                == "Downloaded your training history. You’re connected."
        )
        #expect(
            ConnectSyncProgressCopy.completedMessage(pulled: 10, pushed: 5)
                == "Synced with your account — downloaded 10 and uploaded 5 records."
        )
    }
}

@Suite(.serialized)
struct ConnectAfterAuthSyncTests {
    @Test
    @MainActor
    func secondDevicePullsCloudHistoryWhenLocalEmpty() async throws {
        let (defaults, suite) = ConnectAfterAuthSyncTestSupport.makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        SyncStatusStore.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            SyncStatusStore.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()
        #expect(anonymous != canonical)

        let cloud = ConfigurableMockSyncServiceAccess()
        let (sessionRow, entryRow, setRow) = ConnectAfterAuthSyncTestSupport.seedCloudSession(
            memberId: canonical
        )
        cloud.cloudSessions = [sessionRow]
        cloud.cloudEntries = [entryRow]
        cloud.cloudSets = [setRow]

        let service = try ConnectAfterAuthSyncTestSupport.makeService(
            context: context,
            dataAccess: dataAccess,
            anonymousDeviceId: anonymous,
            canonicalMemberId: canonical,
            cloud: cloud
        )
        let brokerSession = ConnectAfterAuthSyncTestSupport.brokerSession(canonicalMemberId: canonical)
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token)

        service.persistConnected(session: brokerSession, claims: claims)
        #expect(MemberConnectionStore.isConnected)

        let result = await service.syncAfterConnect(session: brokerSession)

        #expect(result.completed)
        #expect(result.pull.mergeCounts.total == 3)
        #expect(result.push.counts.total == 0)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 1)
        #expect(AccessControl.persistedMemberId() == canonical)
    }

    @Test
    @MainActor
    func firstPhoneRetagsThenUploadsWhenCloudEmpty() async throws {
        let (defaults, suite) = ConnectAfterAuthSyncTestSupport.makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: anonymous, date: Date()))

        let cloud = ConfigurableMockSyncServiceAccess()
        let service = try ConnectAfterAuthSyncTestSupport.makeService(
            context: context,
            dataAccess: dataAccess,
            anonymousDeviceId: anonymous,
            canonicalMemberId: canonical,
            cloud: cloud
        )
        let brokerSession = ConnectAfterAuthSyncTestSupport.brokerSession(canonicalMemberId: canonical)

        let result = await service.syncAfterConnect(session: brokerSession)

        #expect(result.completed)
        #expect(result.pull.mergeCounts.total == 0)
        #expect(result.push.counts.total == 1)
        #expect(cloud.sessionBatches.count == 1)
        #expect(cloud.sessionBatches.first?.first?["member_id"] as? String == canonical.uuidString)
        #expect(try dataAccess.fetchSessions(memberId: anonymous).isEmpty)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 1)
    }

    @Test
    @MainActor
    func emptyGenuineConnectCompletesWithoutError() async throws {
        let (defaults, suite) = ConnectAfterAuthSyncTestSupport.makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        let cloud = ConfigurableMockSyncServiceAccess()
        let service = try ConnectAfterAuthSyncTestSupport.makeService(
            context: context,
            dataAccess: dataAccess,
            anonymousDeviceId: anonymous,
            canonicalMemberId: canonical,
            cloud: cloud
        )
        let brokerSession = ConnectAfterAuthSyncTestSupport.brokerSession(canonicalMemberId: canonical)

        let result = await service.syncAfterConnect(session: brokerSession)

        #expect(result.completed)
        #expect(result.pull.mergeCounts.total == 0)
        #expect(result.push.counts.total == 0)
        #expect(
            ConnectSyncProgressCopy.completedMessage(
                pulled: result.pull.mergeCounts.total,
                pushed: result.push.counts.total
            ) == "You’re connected."
        )
    }

    @Test
    @MainActor
    func successTimestampRecordedOnlyAfterFullCycle() async throws {
        let (defaults, suite) = ConnectAfterAuthSyncTestSupport.makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        SyncStatusStore.userDefaults = defaults
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            SyncStatusStore.userDefaults = .standard
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        let cloud = ConfigurableMockSyncServiceAccess()
        let (sessionRow, entryRow, setRow) = ConnectAfterAuthSyncTestSupport.seedCloudSession(
            memberId: canonical
        )
        cloud.cloudSessions = [sessionRow]
        cloud.cloudEntries = [entryRow]
        cloud.cloudSets = [setRow]

        let service = try ConnectAfterAuthSyncTestSupport.makeService(
            context: context,
            dataAccess: dataAccess,
            anonymousDeviceId: anonymous,
            canonicalMemberId: canonical,
            cloud: cloud
        )
        let brokerSession = ConnectAfterAuthSyncTestSupport.brokerSession(canonicalMemberId: canonical)

        #expect(SyncStatusStore.lastSuccessfulCycleAt(memberId: canonical) == nil)

        let result = await service.syncAfterConnect(session: brokerSession)
        if result.completed {
            SyncStatusStore.recordSuccess(memberId: canonical)
        } else {
            SyncStatusStore.recordFailure(
                memberId: canonical,
                message: result.errorMessage ?? "Sync failed"
            )
        }

        #expect(result.completed)
        #expect(SyncStatusStore.lastSuccessfulCycleAt(memberId: canonical) != nil)
        #expect(SyncStatusStore.shouldRunForegroundSync(memberId: canonical) == false)
    }

    @Test
    @MainActor
    func partialFailureRecordsFailureNotSuccess() async throws {
        let (defaults, suite) = ConnectAfterAuthSyncTestSupport.makeIsolatedDefaults()
        AccessControl.userDefaults = defaults
        SyncStatusStore.userDefaults = defaults
        MemberConnectionStore.userDefaults = defaults
        let previousKeychain = KeychainTokenStore.testStore
        KeychainTokenStore.testStore = InMemoryTokenStore()
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccessControl.userDefaults = .standard
            SyncStatusStore.userDefaults = .standard
            MemberConnectionStore.userDefaults = .standard
            KeychainTokenStore.testStore = previousKeychain
        }

        let context = try TestHelpers.makeInMemoryContext()
        let dataAccess = SwiftDataPerformanceDataAccess(context: context)
        let anonymous = AccessControl.persistedMemberId()
        let canonical = UUID()

        try dataAccess.saveSession(SessionModel(memberId: anonymous, date: Date()))

        let cloud = ConfigurableMockSyncServiceAccess()
        let (sessionRow, entryRow, setRow) = ConnectAfterAuthSyncTestSupport.seedCloudSession(
            memberId: canonical
        )
        cloud.cloudSessions = [sessionRow]
        cloud.cloudEntries = [entryRow]
        cloud.cloudSets = [setRow]
        cloud.failOnTable = "sessions"

        let service = try ConnectAfterAuthSyncTestSupport.makeService(
            context: context,
            dataAccess: dataAccess,
            anonymousDeviceId: anonymous,
            canonicalMemberId: canonical,
            cloud: cloud
        )
        let brokerSession = ConnectAfterAuthSyncTestSupport.brokerSession(canonicalMemberId: canonical)
        let claims = try JWTClaimsDecoder.decodeMemberAndGym(from: brokerSession.token)

        service.persistConnected(session: brokerSession, claims: claims)
        #expect(MemberConnectionStore.isConnected)

        let result = await service.syncAfterConnect(session: brokerSession)
        if result.completed {
            SyncStatusStore.recordSuccess(memberId: canonical)
        } else {
            SyncStatusStore.recordFailure(
                memberId: canonical,
                message: result.errorMessage ?? "Sync failed"
            )
        }

        #expect(result.pull.completed)
        #expect(result.push.completed == false)
        #expect(result.completed == false)
        #expect(result.pull.mergeCounts.total == 3)
        #expect(result.push.counts.sessions == 0)
        #expect(try dataAccess.fetchSessions(memberId: canonical).count == 2)
        #expect(MemberConnectionStore.isConnected)
        #expect(SyncStatusStore.lastSuccessfulCycleAt(memberId: canonical) == nil)
        #expect(SyncStatusStore.unrecoveredFailureMessage(memberId: canonical) != nil)
    }
}
#endif
