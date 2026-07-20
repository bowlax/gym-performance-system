import Foundation

/// Pure personal-best rule evaluation.
///
/// Single Swift implementation of the PB rules. Called by
/// `DefaultExerciseRegistry.isPB`, `PBDerivation.beats`, and session
/// ranking (`DefaultMemberPerformance.bestSet`).
/// Must stay in sync with `supabase/functions/_shared/pb-evaluation.ts`.
enum PBRuleEvaluator {
    struct Measurement: Equatable {
        var weight: Double?
        var reps: Int?
        var time: Double?
        var distance: Double?

        init(
            weight: Double? = nil,
            reps: Int? = nil,
            time: Double? = nil,
            distance: Double? = nil
        ) {
            self.weight = weight
            self.reps = reps
            self.time = time
            self.distance = distance
        }

        init(set: ModelSet) {
            self.init(weight: set.weight, reps: set.reps, time: set.time, distance: set.distance)
        }

        init(personalBest: PersonalBestModel) {
            self.init(
                weight: personalBest.weight,
                reps: personalBest.reps,
                time: personalBest.time,
                distance: personalBest.distance
            )
        }
    }

    /// Whether `newSet` strictly beats `current` under `rule`.
    static func isPB(
        rule: PBRule,
        current: Measurement?,
        newSet: Measurement
    ) -> Bool {
        switch rule {
        case .heaviestWeightAtReps, .bestWeightAndReps:
            return isBestWeightAndRepsPB(newSet: newSet, current: current)
        case .heaviestWeight:
            return isHeaviestWeightPB(newSet: newSet, current: current)
        case .heaviestWeightThenLongestTime:
            return isHeaviestWeightThenLongestTimePB(newSet: newSet, current: current)
        case .fastestTime:
            return isFastestTimePB(newSet: newSet, current: current)
        case .longestDistance:
            return isLongestDistancePB(newSet: newSet, current: current)
        case .mostReps:
            return isMostRepsPB(newSet: newSet, current: current)
        }
    }

    /// Tournament-select the best set under `rule` (session ranking / progression).
    /// First set wins on ties (strict improvement only). Same contract as web `bestSetFromSets`.
    static func bestSet(among sets: [ModelSet], rule: PBRule) -> ModelSet? {
        var best: ModelSet?
        for candidate in sets {
            if isPB(
                rule: rule,
                current: best.map(Measurement.init(set:)),
                newSet: Measurement(set: candidate)
            ) {
                best = candidate
            }
        }
        return best
    }

    private static func isBestWeightAndRepsPB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setReps = newSet.reps, setReps > 0 else { return false }
        guard let setWeight = newSet.weight else { return false }
        guard let current else { return true }
        guard let currentWeight = current.weight else { return true }
        if setWeight < currentWeight { return false }
        if setWeight > currentWeight { return true }
        guard let currentReps = current.reps else { return false }
        return setReps > currentReps
    }

    private static func isHeaviestWeightPB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setWeight = newSet.weight else { return false }
        guard let current else { return true }
        guard let currentWeight = current.weight else { return true }
        return setWeight > currentWeight
    }

    private static func isHeaviestWeightThenLongestTimePB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setWeight = newSet.weight else { return false }
        guard let setTime = newSet.time else { return false }
        guard let current else { return true }
        guard let currentWeight = current.weight else { return true }
        if setWeight < currentWeight { return false }
        if setWeight > currentWeight { return true }
        guard let currentTime = current.time else { return false }
        return setTime > currentTime
    }

    private static func isFastestTimePB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setTime = newSet.time else { return false }
        guard let current else { return true }
        guard let currentTime = current.time else { return true }
        return setTime < currentTime
    }

    private static func isLongestDistancePB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setDistance = newSet.distance else { return false }
        guard let current else { return true }
        guard let currentDistance = current.distance else { return true }
        return setDistance > currentDistance
    }

    private static func isMostRepsPB(
        newSet: Measurement,
        current: Measurement?
    ) -> Bool {
        guard let setReps = newSet.reps else { return false }
        guard let current else { return true }
        guard let currentReps = current.reps else { return true }
        return setReps > currentReps
    }
}
