import Foundation
import SwiftData

final class SwiftDataPerformanceDataAccess: PerformanceDataAccess {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: -- Sessions

    func saveSession(_ session: SessionModel) throws {
        context.insert(session)
        try context.save()
    }

    func fetchSessions(memberId: UUID) throws -> [SessionModel] {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.memberId == memberId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchSession(id: UUID) throws -> SessionModel? {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func updateSession(_ session: SessionModel) throws {
        _ = session
        try context.save()
    }

    // MARK: -- Exercise Entries

    func saveExerciseEntry(_ entry: ExerciseEntryModel) throws {
        context.insert(entry)
        try context.save()
    }

    func fetchExerciseEntries(sessionId: UUID) throws -> [ExerciseEntryModel] {
        let descriptor = FetchDescriptor<ExerciseEntryModel>(
            predicate: #Predicate { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func updateExerciseEntry(_ entry: ExerciseEntryModel) throws {
        _ = entry
        try context.save()
    }

    // MARK: -- Sets

    func saveSet(_ set: ModelSet) throws {
        context.insert(set)
        try context.save()
    }

    func fetchSets(exerciseEntryId: UUID) throws -> [ModelSet] {
        let descriptor = FetchDescriptor<ModelSet>(
            predicate: #Predicate { $0.exerciseEntryId == exerciseEntryId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func updateSet(_ set: ModelSet) throws {
        _ = set
        try context.save()
    }

    // MARK: -- Personal Bests

    func savePersonalBest(_ pb: PersonalBestModel) throws {
        context.insert(pb)
        try context.save()
    }

    func fetchAllPBs(memberId: UUID, exerciseId: UUID) throws -> [PersonalBestModel] {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == memberId && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func removeSession(_ session: SessionModel) throws {
        context.delete(session)
        try context.save()
    }

    func removeExerciseEntry(_ entry: ExerciseEntryModel) throws {
        context.delete(entry)
        try context.save()
    }

    func removeSet(_ set: ModelSet) throws {
        context.delete(set)
        try context.save()
    }

    func removePersonalBest(_ pb: PersonalBestModel) throws {
        context.delete(pb)
        try context.save()
    }

    // MARK: -- Exercise resets

    func fetchExerciseReset(memberId: UUID, exerciseId: UUID) throws -> ExerciseResetModel? {
        let descriptor = FetchDescriptor<ExerciseResetModel>(
            predicate: #Predicate {
                $0.memberId == memberId && $0.exerciseId == exerciseId
            }
        )
        return try context.fetch(descriptor).first
    }

    func upsertExerciseReset(
        memberId: UUID,
        exerciseId: UUID,
        resetAt: Date
    ) throws -> ExerciseResetModel {
        let resetDay = PBDerivation.parseISODate(PBDerivation.formatISODate(resetAt))

        if let existing = try fetchExerciseReset(memberId: memberId, exerciseId: exerciseId) {
            let existingDay = PBDerivation.parseISODate(PBDerivation.formatISODate(existing.resetAt))
            existing.resetAt = resetDay > existingDay ? resetDay : existingDay
            existing.deletedAt = nil
            existing.updatedAt = Date()
            try context.save()
            return existing
        }

        let reset = ExerciseResetModel(
            memberId: memberId,
            exerciseId: exerciseId,
            resetAt: resetDay
        )
        context.insert(reset)
        try context.save()
        return reset
    }

    func undoExerciseReset(memberId: UUID, exerciseId: UUID) throws {
        guard let existing = try fetchExerciseReset(memberId: memberId, exerciseId: exerciseId) else {
            return
        }
        existing.deletedAt = Date()
        existing.updatedAt = Date()
        try context.save()
    }
}
