import Foundation
import SwiftData
import Testing
@testable import GymPerformance

struct SyncRecordMergerTests {
    private let memberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000010")!
    private let gymId = UUID(uuidString: "0abc9301-b048-40f5-8bdc-9bb389916b59")!

    @Test
    @MainActor
    func insertNewFromCloudMarksSynced() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let remote = makeRemoteSession(
            id: UUID(),
            updatedAt: Date(timeIntervalSince1970: 200),
            syncedAt: Date(timeIntervalSince1970: 250),
            notes: "from cloud"
        )

        let outcome = try SyncRecordMerger.mergeSession(remote, localDataAccess: local)
        #expect(outcome == .inserted)

        let stored = try local.session(id: remote.id)
        #expect(stored?.notes == "from cloud")
        #expect(stored?.syncedAt != nil)
        #expect(SyncDirtiness.isDirty(updatedAt: stored!.updatedAt, syncedAt: stored!.syncedAt) == false)
    }

    @Test
    @MainActor
    func cloudWinsOverwritesAndMarksSynced() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let id = UUID()

        let existing = SessionModel(
            id: id,
            memberId: memberId,
            date: Date(timeIntervalSince1970: 100),
            notes: "local older",
            updatedAt: Date(timeIntervalSince1970: 100),
            syncedAt: nil
        )
        context.insert(existing)
        try context.save()

        let remote = makeRemoteSession(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 300),
            syncedAt: Date(timeIntervalSince1970: 350),
            notes: "cloud newer"
        )

        let outcome = try SyncRecordMerger.mergeSession(remote, localDataAccess: local)
        #expect(outcome == .cloudWon)
        #expect(existing.notes == "cloud newer")
        #expect(existing.syncedAt != nil)
        #expect(SyncDirtiness.isDirty(updatedAt: existing.updatedAt, syncedAt: existing.syncedAt) == false)
    }

    @Test
    @MainActor
    func localWinsKeepsLocalAndLeavesUnsynced() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let id = UUID()

        let existing = SessionModel(
            id: id,
            memberId: memberId,
            date: Date(timeIntervalSince1970: 100),
            notes: "local newer",
            updatedAt: Date(timeIntervalSince1970: 400),
            syncedAt: nil
        )
        context.insert(existing)
        try context.save()

        let remote = makeRemoteSession(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 200),
            syncedAt: Date(timeIntervalSince1970: 250),
            notes: "cloud older"
        )

        let outcome = try SyncRecordMerger.mergeSession(remote, localDataAccess: local)
        #expect(outcome == .localWon)
        #expect(existing.notes == "local newer")
        #expect(existing.syncedAt == nil)
        #expect(SyncDirtiness.isDirty(updatedAt: existing.updatedAt, syncedAt: existing.syncedAt) == true)
    }

    @Test
    @MainActor
    func softDeleteWinsAppliesDeletedAt() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)
        let id = UUID()

        let existing = SessionModel(
            id: id,
            memberId: memberId,
            date: Date(timeIntervalSince1970: 100),
            notes: "alive",
            updatedAt: Date(timeIntervalSince1970: 100),
            syncedAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(existing)
        try context.save()

        let deletedAt = Date(timeIntervalSince1970: 500)
        let remote = makeRemoteSession(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 500),
            syncedAt: Date(timeIntervalSince1970: 510),
            notes: "deleted",
            deletedAt: deletedAt
        )

        let outcome = try SyncRecordMerger.mergeSession(remote, localDataAccess: local)
        #expect(outcome == .cloudWon)
        #expect(existing.deletedAt == deletedAt)
        #expect(existing.syncedAt != nil)
        #expect(SyncDirtiness.isDirty(updatedAt: existing.updatedAt, syncedAt: existing.syncedAt) == false)
    }

    @Test
    @MainActor
    func dirtyCriterionIncludesLocalEditsAfterSync() throws {
        let context = try TestHelpers.makeInMemoryContext()
        let local = SwiftDataSyncLocalDataAccess(context: context)

        let synced = SessionModel(
            memberId: memberId,
            date: Date(),
            notes: "synced",
            updatedAt: Date(timeIntervalSince1970: 100),
            syncedAt: Date(timeIntervalSince1970: 200)
        )
        let dirty = SessionModel(
            memberId: memberId,
            date: Date(),
            notes: "edited",
            updatedAt: Date(timeIntervalSince1970: 300),
            syncedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(synced)
        context.insert(dirty)
        try context.save()

        let dirtySessions = try local.fetchDirtySessions(memberId: memberId)
        #expect(dirtySessions.map(\.id) == [dirty.id])
    }

    private func makeRemoteSession(
        id: UUID,
        updatedAt: Date,
        syncedAt: Date?,
        notes: String,
        deletedAt: Date? = nil
    ) -> CloudSessionRow {
        CloudSessionRow(
            id: id,
            gymId: gymId,
            memberId: memberId,
            date: Date(timeIntervalSince1970: 0),
            notes: notes,
            caloriesBurned: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt,
            syncedAt: syncedAt,
            deletedAt: deletedAt,
            sourceDeviceId: nil
        )
    }
}
