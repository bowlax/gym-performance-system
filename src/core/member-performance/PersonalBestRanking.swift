import Foundation

enum PersonalBestRanking {
    static func bestRestorable(
        from personalBests: [PersonalBestModel],
        exercise: ExerciseModel,
        excludingIds: Set<UUID> = [],
        excludingSetIds: Set<UUID> = []
    ) -> PersonalBestModel? {
        let candidates = personalBests.filter { pb in
            !pb.wasReset
                && !excludingIds.contains(pb.id)
                && !(pb.setId.map { excludingSetIds.contains($0) } ?? false)
        }
        return best(from: candidates, exercise: exercise)
    }

    static func best(
        from personalBests: [PersonalBestModel],
        exercise: ExerciseModel
    ) -> PersonalBestModel? {
        guard let pbRule = exercise.pbRule else { return nil }

        switch pbRule {
        case .heaviestWeightAtReps, .bestWeightAndReps:
            return personalBests.max { lhs, rhs in
                let leftWeight = lhs.weight ?? 0
                let rightWeight = rhs.weight ?? 0
                if leftWeight != rightWeight {
                    return leftWeight < rightWeight
                }
                return (lhs.reps ?? 0) < (rhs.reps ?? 0)
            }

        case .heaviestWeight:
            return personalBests.max { ($0.weight ?? 0) < ($1.weight ?? 0) }

        case .fastestTime:
            return personalBests.min { ($0.time ?? .infinity) < ($1.time ?? .infinity) }

        case .longestDistance:
            return personalBests.max { ($0.distance ?? 0) < ($1.distance ?? 0) }

        case .mostReps:
            return personalBests.max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        }
    }
}
