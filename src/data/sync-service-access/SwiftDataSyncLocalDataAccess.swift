import Foundation
import SwiftData

final class SwiftDataSyncLocalDataAccess: SyncLocalDataAccess {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchDirtySessions(memberId: UUID) throws -> [SessionModel] {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.memberId == memberId },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try context.fetch(descriptor).filter {
            SyncDirtiness.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt)
        }
    }

    func fetchDirtyExerciseEntries(memberId: UUID) throws -> [ExerciseEntryModel] {
        let memberSessionIds = try memberSessionIds(for: memberId)
        guard !memberSessionIds.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ExerciseEntryModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter {
            memberSessionIds.contains($0.sessionId)
                && SyncDirtiness.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt)
        }
    }

    func fetchDirtySets(memberId: UUID) throws -> [ModelSet] {
        let memberEntryIds = try memberExerciseEntryIds(for: memberId)
        guard !memberEntryIds.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ModelSet>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter {
            memberEntryIds.contains($0.exerciseEntryId)
                && SyncDirtiness.isDirty(updatedAt: $0.updatedAt, syncedAt: $0.syncedAt)
        }
    }

    func fetchDirtyPersonalBests(memberId: UUID) throws -> [PersonalBestModel] {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == memberId },
            sortBy: [SortDescriptor(\.achievedAt, order: .forward)]
        )
        return try context.fetch(descriptor).filter {
            SyncDirtiness.isDirty(updatedAt: $0.effectiveUpdatedAt, syncedAt: $0.syncedAt)
        }
    }

    func session(id: UUID) throws -> SessionModel? {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func exerciseEntry(id: UUID) throws -> ExerciseEntryModel? {
        let descriptor = FetchDescriptor<ExerciseEntryModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func set(id: UUID) throws -> ModelSet? {
        let descriptor = FetchDescriptor<ModelSet>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func personalBest(id: UUID) throws -> PersonalBestModel? {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func insertSession(_ session: SessionModel) throws {
        context.insert(session)
    }

    func insertExerciseEntry(_ entry: ExerciseEntryModel) throws {
        context.insert(entry)
    }

    func insertSet(_ set: ModelSet) throws {
        context.insert(set)
    }

    func insertPersonalBest(_ personalBest: PersonalBestModel) throws {
        context.insert(personalBest)
    }

    func markSessionsSynced(_ sessions: [SessionModel], at date: Date) throws {
        for session in sessions {
            session.syncedAt = date
        }
        try context.save()
    }

    func markExerciseEntriesSynced(_ entries: [ExerciseEntryModel], at date: Date) throws {
        for entry in entries {
            entry.syncedAt = date
        }
        try context.save()
    }

    func markSetsSynced(_ sets: [ModelSet], at date: Date) throws {
        for set in sets {
            set.syncedAt = date
        }
        try context.save()
    }

    func markPersonalBestsSynced(_ personalBests: [PersonalBestModel], at date: Date) throws {
        for pb in personalBests {
            pb.syncedAt = date
        }
        try context.save()
    }

    func save() throws {
        try context.save()
    }

    private func memberSessionIds(for memberId: UUID) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.memberId == memberId }
        )
        return Set(try context.fetch(descriptor).map(\.id))
    }

    private func memberExerciseEntryIds(for memberId: UUID) throws -> Set<UUID> {
        let sessionIds = try memberSessionIds(for: memberId)
        guard !sessionIds.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ExerciseEntryModel>()
        let entries = try context.fetch(descriptor)
        return Set(entries.filter { sessionIds.contains($0.sessionId) }.map(\.id))
    }
}
