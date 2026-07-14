import Foundation

/// Reads/writes local SwiftData records for sync pull, merge, and push.
protocol SyncLocalDataAccess: AnyObject {
    func fetchDirtySessions(memberId: UUID) throws -> [SessionModel]
    func fetchDirtyExerciseEntries(memberId: UUID) throws -> [ExerciseEntryModel]
    func fetchDirtySets(memberId: UUID) throws -> [ModelSet]
    func fetchDirtyPersonalBests(memberId: UUID) throws -> [PersonalBestModel]

    func session(id: UUID) throws -> SessionModel?
    func exerciseEntry(id: UUID) throws -> ExerciseEntryModel?
    func set(id: UUID) throws -> ModelSet?
    func personalBest(id: UUID) throws -> PersonalBestModel?

    func insertSession(_ session: SessionModel) throws
    func insertExerciseEntry(_ entry: ExerciseEntryModel) throws
    func insertSet(_ set: ModelSet) throws
    func insertPersonalBest(_ personalBest: PersonalBestModel) throws

    func markSessionsSynced(_ sessions: [SessionModel], at date: Date) throws
    func markExerciseEntriesSynced(_ entries: [ExerciseEntryModel], at date: Date) throws
    func markSetsSynced(_ sets: [ModelSet], at date: Date) throws
    func markPersonalBestsSynced(_ personalBests: [PersonalBestModel], at date: Date) throws

    func save() throws
}

extension SyncLocalDataAccess {
    /// Back-compat alias used by first-connect tests (dirty includes never-synced).
    func fetchUnsyncedSessions(memberId: UUID) throws -> [SessionModel] {
        try fetchDirtySessions(memberId: memberId)
    }

    func fetchUnsyncedExerciseEntries(memberId: UUID) throws -> [ExerciseEntryModel] {
        try fetchDirtyExerciseEntries(memberId: memberId)
    }

    func fetchUnsyncedSets(memberId: UUID) throws -> [ModelSet] {
        try fetchDirtySets(memberId: memberId)
    }

    func fetchUnsyncedPersonalBests(memberId: UUID) throws -> [PersonalBestModel] {
        try fetchDirtyPersonalBests(memberId: memberId)
    }
}

enum SyncDirtiness {
    static func isDirty(updatedAt: Date, syncedAt: Date?) -> Bool {
        guard let syncedAt else { return true }
        return updatedAt > syncedAt
    }
}
