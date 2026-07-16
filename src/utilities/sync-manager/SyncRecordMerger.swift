import Foundation

enum SyncMergeOutcome: Equatable, Sendable {
    case inserted
    case cloudWon
    case localWon
}

struct SyncMergeCounts: Equatable, Sendable {
    var inserted: Int = 0
    var cloudWon: Int = 0
    var localWon: Int = 0

    var total: Int { inserted + cloudWon + localWon }

    mutating func record(_ outcome: SyncMergeOutcome) {
        switch outcome {
        case .inserted: inserted += 1
        case .cloudWon: cloudWon += 1
        case .localWon: localWon += 1
        }
    }
}

/// Last-write-wins merge on device-set `updated_at`, with synced marker discipline for cloud wins.
enum SyncRecordMerger {
    static func cloudWins(localUpdatedAt: Date, cloudUpdatedAt: Date) -> Bool {
        cloudUpdatedAt > localUpdatedAt
    }

    /// Mark applied cloud-originated local state as synced so push does not echo it back.
    static func syncedAtForCloudApplied(cloudSyncedAt: Date?, cloudUpdatedAt: Date) -> Date {
        if let cloudSyncedAt {
            return max(cloudSyncedAt, cloudUpdatedAt)
        }
        return cloudUpdatedAt
    }

    @discardableResult
    static func mergeSession(
        _ remote: CloudSessionRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        if let local = try localDataAccess.session(id: remote.id) {
            if cloudWins(localUpdatedAt: local.updatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = SessionModel(
            id: remote.id,
            memberId: remote.memberId,
            date: remote.date,
            notes: remote.notes,
            caloriesBurned: remote.caloriesBurned,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            ),
            deletedAt: remote.deletedAt
        )
        try localDataAccess.insertSession(inserted)
        try localDataAccess.save()
        return .inserted
    }

    @discardableResult
    static func mergeExerciseEntry(
        _ remote: CloudExerciseEntryRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        if let local = try localDataAccess.exerciseEntry(id: remote.id) {
            if cloudWins(localUpdatedAt: local.updatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = ExerciseEntryModel(
            id: remote.id,
            sessionId: remote.sessionId,
            exerciseId: remote.exerciseId,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            ),
            deletedAt: remote.deletedAt
        )
        try localDataAccess.insertExerciseEntry(inserted)
        try localDataAccess.save()
        return .inserted
    }

    @discardableResult
    static func mergeSet(
        _ remote: CloudSetRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        if let local = try localDataAccess.set(id: remote.id) {
            if cloudWins(localUpdatedAt: local.updatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = ModelSet(
            id: remote.id,
            exerciseEntryId: remote.exerciseEntryId,
            weight: remote.weight,
            reps: remote.reps,
            time: remote.timeSeconds,
            distance: remote.distance,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            ),
            deletedAt: remote.deletedAt
        )
        try localDataAccess.insertSet(inserted)
        try localDataAccess.save()
        return .inserted
    }

    @discardableResult
    static func mergePersonalBest(
        _ remote: CloudPersonalBestRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        let entryType = PBEntryType(rawValue: remote.entryType) ?? .sessionDerived

        if let local = try localDataAccess.personalBest(id: remote.id) {
            if cloudWins(localUpdatedAt: local.effectiveUpdatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local, entryType: entryType)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = PersonalBestModel(
            id: remote.id,
            memberId: remote.memberId,
            exerciseId: remote.exerciseId,
            setId: remote.setId,
            weight: remote.weight,
            reps: remote.reps,
            time: remote.timeSeconds,
            distance: remote.distance,
            achievedAt: remote.achievedAt,
            entryType: entryType,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            ),
            deletedAt: remote.deletedAt
        )
        try localDataAccess.insertPersonalBest(inserted)
        try localDataAccess.save()
        return .inserted
    }

    @discardableResult
    static func mergeMember(
        _ remote: CloudMemberRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        let unit = StalenessPeriodUnit(rawValue: remote.stalenessUnit) ?? .quarter

        if let local = try localDataAccess.member(id: remote.id) {
            if cloudWins(localUpdatedAt: local.updatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local, unit: unit)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = UserIdentityModel(
            id: remote.id,
            role: .member,
            displayName: remote.displayName,
            createdAt: remote.createdAt,
            stalenessEnabled: remote.stalenessEnabled,
            stalenessPeriods: remote.stalenessPeriods,
            stalenessUnit: unit,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            )
        )
        try localDataAccess.insertMember(inserted)
        try localDataAccess.save()
        return .inserted
    }

    @discardableResult
    static func mergeExerciseReset(
        _ remote: CloudExerciseResetRow,
        localDataAccess: SyncLocalDataAccess
    ) throws -> SyncMergeOutcome {
        if let local = try localDataAccess.exerciseReset(id: remote.id) {
            if cloudWins(localUpdatedAt: local.updatedAt, cloudUpdatedAt: remote.updatedAt) {
                apply(remote, to: local)
                try localDataAccess.save()
                return .cloudWon
            }
            return .localWon
        }

        let inserted = ExerciseResetModel(
            id: remote.id,
            memberId: remote.memberId,
            exerciseId: remote.exerciseId,
            resetAt: remote.resetAt,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            syncedAt: syncedAtForCloudApplied(
                cloudSyncedAt: remote.syncedAt,
                cloudUpdatedAt: remote.updatedAt
            ),
            deletedAt: remote.deletedAt
        )
        try localDataAccess.insertExerciseReset(inserted)
        try localDataAccess.save()
        return .inserted
    }

    private static func apply(_ remote: CloudSessionRow, to local: SessionModel) {
        local.memberId = remote.memberId
        local.date = remote.date
        local.notes = remote.notes
        local.caloriesBurned = remote.caloriesBurned
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.deletedAt = remote.deletedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }

    private static func apply(_ remote: CloudExerciseEntryRow, to local: ExerciseEntryModel) {
        local.sessionId = remote.sessionId
        local.exerciseId = remote.exerciseId
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.deletedAt = remote.deletedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }

    private static func apply(_ remote: CloudSetRow, to local: ModelSet) {
        local.exerciseEntryId = remote.exerciseEntryId
        local.weight = remote.weight
        local.reps = remote.reps
        local.time = remote.timeSeconds
        local.distance = remote.distance
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.deletedAt = remote.deletedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }

    private static func apply(
        _ remote: CloudPersonalBestRow,
        to local: PersonalBestModel,
        entryType: PBEntryType
    ) {
        local.memberId = remote.memberId
        local.exerciseId = remote.exerciseId
        local.setId = remote.setId
        local.weight = remote.weight
        local.reps = remote.reps
        local.time = remote.timeSeconds
        local.distance = remote.distance
        local.achievedAt = remote.achievedAt
        local.entryType = entryType
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.deletedAt = remote.deletedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }

    private static func apply(
        _ remote: CloudMemberRow,
        to local: UserIdentityModel,
        unit: StalenessPeriodUnit
    ) {
        local.displayName = remote.displayName
        local.stalenessEnabled = remote.stalenessEnabled
        local.stalenessPeriods = remote.stalenessPeriods
        local.stalenessUnit = unit
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }

    private static func apply(_ remote: CloudExerciseResetRow, to local: ExerciseResetModel) {
        local.memberId = remote.memberId
        local.exerciseId = remote.exerciseId
        local.resetAt = remote.resetAt
        local.createdAt = remote.createdAt
        local.updatedAt = remote.updatedAt
        local.deletedAt = remote.deletedAt
        local.syncedAt = syncedAtForCloudApplied(
            cloudSyncedAt: remote.syncedAt,
            cloudUpdatedAt: remote.updatedAt
        )
    }
}
