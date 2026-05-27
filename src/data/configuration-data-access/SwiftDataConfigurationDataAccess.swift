import Foundation
import SwiftData

final class SwiftDataConfigurationDataAccess: ConfigurationDataAccess {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchExercises() throws -> [ExerciseModel] {
        let descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.displayOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchExercise(id: UUID) throws -> ExerciseModel? {
        let descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchExercises(category: ExerciseCategory) throws -> [ExerciseModel] {
        // SwiftData #Predicate does not support captured enum values.
        // Reuse fetchExercises() and filter in memory to preserve displayOrder sorting.
        try fetchExercises().filter { $0.category == category }
    }

    func seedExercises(_ exercises: [ExerciseModel]) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<ExerciseModel>())
        guard existingCount == 0 else { return }

        for exercise in exercises {
            context.insert(exercise)
        }

        try context.save()
    }
}

