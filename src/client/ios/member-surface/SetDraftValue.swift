import Foundation

struct SetDraftValue: Hashable {
    var weight: Double?
    var reps: Int?
    var timeSeconds: Int?
    var distance: Int?

    static let empty = SetDraftValue()

    init(
        weight: Double? = nil,
        reps: Int? = nil,
        timeSeconds: Int? = nil,
        distance: Int? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.timeSeconds = timeSeconds
        self.distance = distance
    }

    static func initial(for exercise: ExerciseModel) -> SetDraftValue {
        if exercise.pbRule == .heaviestWeightAtReps, let targetReps = exercise.targetReps {
            return SetDraftValue(reps: targetReps)
        }
        return .empty
    }

    func isEmpty(for exercise: ExerciseModel) -> Bool {
        switch exercise.measurementType {
        case .weightAndReps:
            return weight == nil
        case .weightAndTime:
            return weight == nil && timeSeconds == nil
        case .timeOnly:
            return timeSeconds == nil
        case .distanceOnly:
            return distance == nil
        case .repsOnly:
            return reps == nil
        case .weightAndDistance:
            return weight == nil && distance == nil
        }
    }

    func manualPBValues(for exercise: ExerciseModel) -> (
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?
    )? {
        guard !isEmpty(for: exercise) else { return nil }

        let resolvedReps = exercise.pbRule == .heaviestWeightAtReps
            ? (reps ?? exercise.targetReps)
            : reps

        switch exercise.measurementType {
        case .weightAndReps:
            return (weight, resolvedReps, nil, nil)
        case .weightAndTime:
            return (weight, nil, timeSeconds.map(Double.init), nil)
        case .timeOnly:
            return (nil, nil, timeSeconds.map(Double.init), nil)
        case .distanceOnly:
            return (nil, nil, nil, distance.map(Double.init))
        case .repsOnly:
            return (nil, reps, nil, nil)
        case .weightAndDistance:
            return (weight, nil, nil, distance.map(Double.init))
        }
    }

    func toModelSet(exerciseEntryId: UUID, exercise: ExerciseModel) -> ModelSet? {
        guard !isEmpty(for: exercise) else { return nil }

        let resolvedReps = exercise.pbRule == .heaviestWeightAtReps
            ? (reps ?? exercise.targetReps)
            : reps

        switch exercise.measurementType {
        case .weightAndReps:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                weight: weight,
                reps: resolvedReps
            )
        case .weightAndTime:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                weight: weight,
                time: timeSeconds.map(Double.init)
            )
        case .timeOnly:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                time: timeSeconds.map(Double.init)
            )
        case .distanceOnly:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                distance: distance.map(Double.init)
            )
        case .repsOnly:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                reps: reps
            )
        case .weightAndDistance:
            return ModelSet(
                exerciseEntryId: exerciseEntryId,
                weight: weight,
                distance: distance.map(Double.init)
            )
        }
    }
}

struct DraftExercise: Identifiable {
    let id = UUID()
    let exercise: ExerciseModel
    var sets: [SetDraftValue]

    init(exercise: ExerciseModel) {
        self.exercise = exercise
        self.sets = [SetDraftValue.initial(for: exercise)]
    }
}

struct CelebrationPB: Identifiable {
    let id: UUID
    let exerciseName: String
    let formattedValue: String

    var displayLine: String {
        "\(exerciseName): \(formattedValue)"
    }
}

struct ProgressionEntry: Identifiable {
    let id: UUID
    let date: Date
    let formattedValue: String
    let chartValue: Double
    let isPB: Bool
}
