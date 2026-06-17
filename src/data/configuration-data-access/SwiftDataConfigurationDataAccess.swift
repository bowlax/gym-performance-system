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

    func syncExerciseDefinitions(with seedData: [ExerciseModel]) throws {
        let seedById = Dictionary(uniqueKeysWithValues: seedData.map { ($0.id, $0) })
        let existing = try fetchExercises()
        var changed = false

        for exercise in existing {
            guard let seed = seedById[exercise.id] else { continue }

            if exercise.minimumReps != seed.minimumReps {
                exercise.minimumReps = seed.minimumReps
                changed = true
            }
        }

        if changed {
            try context.save()
        }
    }
}

