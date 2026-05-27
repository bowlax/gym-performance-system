import Foundation

protocol ConfigurationDataAccess {

    /// Retrieve all active exercises, ordered by displayOrder
    func fetchExercises() throws -> [ExerciseModel]

    /// Retrieve a single exercise by id
    func fetchExercise(id: UUID) throws -> ExerciseModel?

    /// Retrieve all exercises of a specific category
    func fetchExercises(category: ExerciseCategory) throws -> [ExerciseModel]

    /// Seed initial exercise definitions on first launch.
    /// Only called if no exercises exist in the store.
    func seedExercises(_ exercises: [ExerciseModel]) throws
}

