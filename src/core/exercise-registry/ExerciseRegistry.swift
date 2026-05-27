import Foundation

protocol ExerciseRegistry {

    /// Returns all active exercises ordered by displayOrder
    func allExercises() throws -> [ExerciseModel]

    /// Returns all PB exercises (category == .pbExercise) ordered by displayOrder
    func pbExercises() throws -> [ExerciseModel]

    /// Returns a single exercise by id
    func exercise(id: UUID) throws -> ExerciseModel?

    /// Evaluates whether a new set constitutes a PB for a given exercise.
    /// Returns true if the set is a new PB, false otherwise.
    func isPB(set: ModelSet, exercise: ExerciseModel, currentPB: PersonalBestModel?) -> Bool

    /// Seeds exercises on first launch if none exist
    func seedIfNeeded() throws
}
