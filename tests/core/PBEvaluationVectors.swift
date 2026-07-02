import Foundation
@testable import GymPerformance

struct PBEvaluationSetState: Codable, Sendable {
    let weight: Double?
    let reps: Int?
    let time: Double?
    let distance: Double?
}

struct PBEvaluationVector: Codable, Sendable {
    let id: String
    let description: String
    let rule: String
    let exerciseName: String
    let targetReps: Int?
    let minimumReps: Int?
    let currentPB: PBEvaluationSetState?
    let newSet: PBEvaluationSetState
    let expectedResult: String

    var expectsIsPB: Bool {
        expectedResult == "isPB"
    }
}

private struct PBEvaluationVectorFile: Codable {
    let schemaVersion: Int
    let vectors: [PBEvaluationVector]
}

enum PBEvaluationVectorLoader {
    static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("vectors/pb-evaluation-vectors.json")

    static func load() throws -> [PBEvaluationVector] {
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(PBEvaluationVectorFile.self, from: data)
        return file.vectors
    }
}

enum PBEvaluationVectorRunner {
    static func evaluate(
        _ vector: PBEvaluationVector,
        registry: DefaultExerciseRegistry
    ) -> Bool {
        let exercise = exercise(named: vector.exerciseName)
        let set = makeSet(from: vector.newSet)
        let currentPB = makeCurrentPB(
            exerciseId: exercise.id,
            from: vector.currentPB
        )
        return registry.isPB(set: set, exercise: exercise, currentPB: currentPB)
    }

    private static func exercise(named name: String) -> ExerciseModel {
        guard let exercise = ExerciseModel.seedData.first(where: { $0.name == name }) else {
            fatalError("Missing seed exercise for vector: \(name)")
        }
        return exercise
    }

    private static func makeSet(from state: PBEvaluationSetState) -> ModelSet {
        ModelSet(
            exerciseEntryId: UUID(),
            weight: state.weight,
            reps: state.reps,
            time: state.time,
            distance: state.distance
        )
    }

    private static func makeCurrentPB(
        exerciseId: UUID,
        from state: PBEvaluationSetState?
    ) -> PersonalBestModel? {
        guard let state else { return nil }
        return PersonalBestModel(
            memberId: UUID(),
            exerciseId: exerciseId,
            setId: UUID(),
            weight: state.weight,
            reps: state.reps,
            time: state.time,
            distance: state.distance,
            achievedAt: Date()
        )
    }
}
