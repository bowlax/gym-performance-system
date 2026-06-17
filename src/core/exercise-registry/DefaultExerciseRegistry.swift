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
        if exercises.isEmpty {
            try configurationDataAccess.seedExercises(ExerciseModel.seedData)
        } else {
            try configurationDataAccess.syncExerciseDefinitions(with: ExerciseModel.seedData)
        }
    }

    func isPB(set: ModelSet, exercise: ExerciseModel, currentPB: PersonalBestModel?) -> Bool {
        guard let pbRule = exercise.pbRule else { return false }

        switch pbRule {
        case .heaviestWeightAtReps, .bestWeightAndReps:
            return isBestWeightAndRepsPB(set: set, currentPB: currentPB)
        case .heaviestWeight:
            return isHeaviestWeightPB(set: set, currentPB: currentPB)
        case .fastestTime:
            return isFastestTimePB(set: set, currentPB: currentPB)
        case .longestDistance:
            return isLongestDistancePB(set: set, currentPB: currentPB)
        case .mostReps:
            return isMostRepsPB(set: set, currentPB: currentPB)
        }
    }

    private func isBestWeightAndRepsPB(
        set: ModelSet,
        currentPB: PersonalBestModel?
    ) -> Bool {
        guard let setReps = set.reps, setReps > 0 else { return false }
        guard let setWeight = set.weight else { return false }

        guard let currentPB else { return true }

        guard let currentWeight = currentPB.weight else { return true }

        if setWeight < currentWeight {
            return false
        }

        if setWeight > currentWeight {
            return true
        }

        guard let currentReps = currentPB.reps else { return false }
        return setReps > currentReps
    }

    private func isHeaviestWeightPB(set: ModelSet, currentPB: PersonalBestModel?) -> Bool {
        guard let setWeight = set.weight else { return false }
        guard let currentPB else { return true }
        guard let currentWeight = currentPB.weight else { return true }
        return setWeight > currentWeight
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
