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
        return PBRuleEvaluator.isPB(
            rule: pbRule,
            current: currentPB.map(PBRuleEvaluator.Measurement.init(personalBest:)),
            newSet: PBRuleEvaluator.Measurement(set: set)
        )
    }
}
