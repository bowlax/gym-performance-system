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
        // SwiftData tracks changes on managed models. Saving persists edits.
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

    func fetchCurrentPB(memberId: UUID, exerciseId: UUID) throws -> PersonalBestModel? {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate {
                $0.memberId == memberId && $0.exerciseId == exerciseId && $0.isCurrent == true
            }
        )
        return try context.fetch(descriptor).first
    }

    func fetchAllPBs(memberId: UUID, exerciseId: UUID) throws -> [PersonalBestModel] {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == memberId && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchCurrentPBs(memberId: UUID) throws -> [PersonalBestModel] {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.memberId == memberId && $0.isCurrent == true },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func markPBAsSuperseded(id: UUID) throws {
        let descriptor = FetchDescriptor<PersonalBestModel>(
            predicate: #Predicate { $0.id == id }
        )

        if let pb = try context.fetch(descriptor).first {
            pb.isCurrent = false
            try context.save()
        }
    }
}

