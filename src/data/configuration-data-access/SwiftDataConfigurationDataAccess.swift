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
        // Include inactive rows so catalog fields (order, name, …) heal even if
        // a prior install flipped isActive.
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var changed = false

        for exercise in existing {
            guard let seed = seedById[exercise.id] else { continue }

            if exercise.name != seed.name {
                exercise.name = seed.name
                changed = true
            }
            if exercise.category != seed.category {
                exercise.category = seed.category
                changed = true
            }
            if exercise.measurementType != seed.measurementType {
                exercise.measurementType = seed.measurementType
                changed = true
            }
            if exercise.pbRule != seed.pbRule {
                exercise.pbRule = seed.pbRule
                changed = true
            }
            if exercise.targetReps != seed.targetReps {
                exercise.targetReps = seed.targetReps
                changed = true
            }
            if exercise.minimumReps != seed.minimumReps {
                exercise.minimumReps = seed.minimumReps
                changed = true
            }
            if exercise.parentExerciseId != seed.parentExerciseId {
                exercise.parentExerciseId = seed.parentExerciseId
                changed = true
            }
            if exercise.displayOrder != seed.displayOrder {
                exercise.displayOrder = seed.displayOrder
                changed = true
            }
            if exercise.isActive != seed.isActive {
                exercise.isActive = seed.isActive
                changed = true
            }
        }

        if changed {
            try context.save()
        }
    }
}

