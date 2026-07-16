import Foundation

struct SyncPullResult: Equatable, Sendable {
    let mergeCounts: SyncMergeCounts
    let highWaterSyncedAt: Date?
    let completed: Bool
    let errorMessage: String?

    static func completed(mergeCounts: SyncMergeCounts, highWaterSyncedAt: Date?) -> SyncPullResult {
        SyncPullResult(
            mergeCounts: mergeCounts,
            highWaterSyncedAt: highWaterSyncedAt,
            completed: true,
            errorMessage: nil
        )
    }

    static func interrupted(
        mergeCounts: SyncMergeCounts,
        highWaterSyncedAt: Date?,
        error: Error
    ) -> SyncPullResult {
        SyncPullResult(
            mergeCounts: mergeCounts,
            highWaterSyncedAt: highWaterSyncedAt,
            completed: false,
            errorMessage: error.localizedDescription
        )
    }
}

/// Pulls cloud rows changed since the last-pull marker and merges them with LWW.
struct SyncPuller {
    private let localDataAccess: SyncLocalDataAccess
    private let syncServiceAccess: SyncServiceAccess
    private let memberId: UUID

    init(
        localDataAccess: SyncLocalDataAccess,
        syncServiceAccess: SyncServiceAccess,
        memberId: UUID
    ) {
        self.localDataAccess = localDataAccess
        self.syncServiceAccess = syncServiceAccess
        self.memberId = memberId
    }

    func pullAndMerge() async -> SyncPullResult {
        var counts = SyncMergeCounts()
        var highWater: Date?
        let since = SyncLastPullMarker.lastPullSyncedAt(memberId: memberId)

        do {
            let members = try await syncServiceAccess.pullMembers(since: since)
            for row in members {
                counts.record(try SyncRecordMerger.mergeMember(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            let sessions = try await syncServiceAccess.pullSessions(since: since)
            for row in sessions {
                counts.record(try SyncRecordMerger.mergeSession(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            let entries = try await syncServiceAccess.pullExerciseEntries(since: since)
            for row in entries {
                counts.record(try SyncRecordMerger.mergeExerciseEntry(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            let sets = try await syncServiceAccess.pullSets(since: since)
            for row in sets {
                counts.record(try SyncRecordMerger.mergeSet(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            let personalBests = try await syncServiceAccess.pullPersonalBests(since: since)
            for row in personalBests {
                counts.record(try SyncRecordMerger.mergePersonalBest(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            let exerciseResets = try await syncServiceAccess.pullExerciseResets(since: since)
            for row in exerciseResets {
                counts.record(try SyncRecordMerger.mergeExerciseReset(row, localDataAccess: localDataAccess))
                highWater = maxDate(highWater, row.syncedAt)
            }

            if let highWater {
                SyncLastPullMarker.setLastPullSyncedAt(highWater, memberId: memberId)
            }

            return .completed(mergeCounts: counts, highWaterSyncedAt: highWater)
        } catch {
            // Do not advance the last-pull marker on partial failure.
            return .interrupted(mergeCounts: counts, highWaterSyncedAt: nil, error: error)
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }
}
