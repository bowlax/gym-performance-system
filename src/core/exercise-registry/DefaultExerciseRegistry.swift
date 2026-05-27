import Foundation

final class DefaultExerciseRegistry: ExerciseRegistry {
    private let configurationDataAccess: ConfigurationDataAccess

    init(configurationDataAccess: ConfigurationDataAccess) {
        self.configurationDataAccess = configurationDataAccess
    }

    func allExercises() throws -> [ExerciseModel] {
        try configurationDataAccess.fetchExercises()
    }

    func pbExercises() throws -> [ExerciseModel] {
        try configurationDataAccess.fetchExercises(category: .pbExercise)
    }

    func exercise(id: UUID) throws -> ExerciseModel? {
        try configurationDataAccess.fetchExercise(id: id)
    }

    func seedIfNeeded() throws {
        let exercises = try configurationDataAccess.fetchExercises()
        guard exercises.isEmpty else { return }

        try configurationDataAccess.seedExercises(ExerciseModel.seedData)
    }

    func isPB(set: ModelSet, exercise: ExerciseModel, currentPB: PersonalBestModel?) -> Bool {
        guard let pbRule = exercise.pbRule else { return false }

        switch pbRule {
        case .heaviestWeightAtReps:
            return isHeaviestWeightAtRepsPB(set: set, exercise: exercise, currentPB: currentPB)
        case .heaviestWeight:
            return isHeaviestWeightPB(set: set, currentPB: currentPB)
        case .bestWeightAndReps:
            return isBestWeightAndRepsPB(set: set, exercise: exercise, currentPB: currentPB)
        case .fastestTime:
            return isFastestTimePB(set: set, currentPB: currentPB)
        case .longestDistance:
            return isLongestDistancePB(set: set, currentPB: currentPB)
        case .mostReps:
            return isMostRepsPB(set: set, currentPB: currentPB)
        }
    }

    private func isHeaviestWeightAtRepsPB(
        set: ModelSet,
        exercise: ExerciseModel,
        currentPB: PersonalBestModel?
    ) -> Bool {
        guard let setReps = set.reps, setReps == exercise.targetReps else { return false }
        guard let setWeight = set.weight else { return false }

        guard let currentPB else { return true }

        guard let currentWeight = currentPB.weight else { return true }
        return setWeight > currentWeight
    }

    private func isHeaviestWeightPB(set: ModelSet, currentPB: PersonalBestModel?) -> Bool {
        guard let setWeight = set.weight else { return false }
        guard let currentPB else { return true }
        guard let currentWeight = currentPB.weight else { return true }
        return setWeight > currentWeight
    }

    private func isBestWeightAndRepsPB(
        set: ModelSet,
        exercise: ExerciseModel,
        currentPB: PersonalBestModel?
    ) -> Bool {
        guard let minimumReps = exercise.minimumReps else { return false }
        guard let setReps = set.reps, setReps >= minimumReps else { return false }
        guard let setWeight = set.weight else { return false }

        guard let currentPB else { return true }

        guard let currentWeight = currentPB.weight else {
            return setReps >= minimumReps
        }

        if setWeight < currentWeight {
            return false
        }

        if setWeight > currentWeight, setReps >= minimumReps {
            return true
        }

        guard let currentReps = currentPB.reps else { return false }
        return setReps > currentReps && setWeight >= currentWeight && setReps >= minimumReps
    }

    private func isFastestTimePB(set: ModelSet, currentPB: PersonalBestModel?) -> Bool {
        guard let setTime = set.time else { return false }
        guard let currentPB else { return true }
        guard let currentTime = currentPB.time else { return true }
        return setTime < currentTime
    }

    private func isLongestDistancePB(set: ModelSet, currentPB: PersonalBestModel?) -> Bool {
        guard let setDistance = set.distance else { return false }
        guard let currentPB else { return true }
        guard let currentDistance = currentPB.distance else { return true }
        return setDistance > currentDistance
    }

    private func isMostRepsPB(set: ModelSet, currentPB: PersonalBestModel?) -> Bool {
        guard let setReps = set.reps else { return false }
        guard let currentPB else { return true }
        guard let currentReps = currentPB.reps else { return true }
        return setReps > currentReps
    }
}
