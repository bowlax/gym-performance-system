#if canImport(Testing)
import Foundation
import Testing
@testable import GymPerformance

/// Session-ranking characterization: `PBRuleEvaluator.bestSet` must match the
/// pre-fold filter+max/min tournament for realistic sets.
@Suite
struct PBRuleEvaluatorBestSetTests {
    private let entryId = UUID()

    @Test
    func bestWeightAndReps_prefersHeavierThenMoreReps() {
        let weaker = ModelSet(exerciseEntryId: entryId, weight: 100, reps: 8)
        let heavier = ModelSet(exerciseEntryId: entryId, weight: 110, reps: 3)
        let sameWeightMoreReps = ModelSet(exerciseEntryId: entryId, weight: 110, reps: 5)
        let sets = [weaker, heavier, sameWeightMoreReps]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .bestWeightAndReps)
        let legacy = legacyBestSet(among: sets, rule: .bestWeightAndReps)

        #expect(folded?.id == sameWeightMoreReps.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func heaviestWeight_prefersMaxWeight() {
        let light = ModelSet(exerciseEntryId: entryId, weight: 90, reps: nil)
        let heavy = ModelSet(exerciseEntryId: entryId, weight: 120, reps: nil)
        let sets = [light, heavy]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .heaviestWeight)
        let legacy = legacyBestSet(among: sets, rule: .heaviestWeight)

        #expect(folded?.id == heavy.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func fastestTime_prefersMinimumTime() {
        let slow = ModelSet(exerciseEntryId: entryId, time: 60)
        let fast = ModelSet(exerciseEntryId: entryId, time: 45)
        let sets = [slow, fast]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .fastestTime)
        let legacy = legacyBestSet(among: sets, rule: .fastestTime)

        #expect(folded?.id == fast.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func longestDistance_prefersMaxDistance() {
        let near = ModelSet(exerciseEntryId: entryId, distance: 1000)
        let far = ModelSet(exerciseEntryId: entryId, distance: 5000)
        let sets = [near, far]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .longestDistance)
        let legacy = legacyBestSet(among: sets, rule: .longestDistance)

        #expect(folded?.id == far.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func mostReps_prefersMaxReps() {
        let few = ModelSet(exerciseEntryId: entryId, reps: 8)
        let many = ModelSet(exerciseEntryId: entryId, reps: 15)
        let sets = [few, many]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .mostReps)
        let legacy = legacyBestSet(among: sets, rule: .mostReps)

        #expect(folded?.id == many.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func ties_keepFirstOccurrence() {
        let first = ModelSet(exerciseEntryId: entryId, weight: 100, reps: 5)
        let second = ModelSet(exerciseEntryId: entryId, weight: 100, reps: 5)
        let sets = [first, second]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .bestWeightAndReps)
        let legacy = legacyBestSet(among: sets, rule: .bestWeightAndReps)

        #expect(folded?.id == first.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func ignoresIncompleteSets() {
        let incomplete = ModelSet(exerciseEntryId: entryId, weight: 200, reps: nil)
        let complete = ModelSet(exerciseEntryId: entryId, weight: 100, reps: 5)
        let sets = [incomplete, complete]

        let folded = PBRuleEvaluator.bestSet(among: sets, rule: .bestWeightAndReps)
        let legacy = legacyBestSet(among: sets, rule: .bestWeightAndReps)

        #expect(folded?.id == complete.id)
        #expect(folded?.id == legacy?.id)
    }

    @Test
    func emptyReturnsNil() {
        #expect(PBRuleEvaluator.bestSet(among: [], rule: .heaviestWeight) == nil)
        #expect(legacyBestSet(among: [], rule: .heaviestWeight) == nil)
    }

    /// Pre-fold filter+max/min algorithm (kept only to pin session-ranking parity).
    private func legacyBestSet(among sets: [ModelSet], rule: PBRule) -> ModelSet? {
        switch rule {
        case .heaviestWeightAtReps, .bestWeightAndReps:
            return sets
                .filter { $0.weight != nil && $0.reps != nil }
                .max {
                    let leftWeight = $0.weight ?? 0
                    let rightWeight = $1.weight ?? 0
                    if leftWeight != rightWeight {
                        return leftWeight < rightWeight
                    }
                    return ($0.reps ?? 0) < ($1.reps ?? 0)
                }
        case .heaviestWeight:
            return sets
                .filter { $0.weight != nil }
                .max { ($0.weight ?? 0) < ($1.weight ?? 0) }
        case .fastestTime:
            return sets
                .filter { $0.time != nil }
                .min { ($0.time ?? .infinity) < ($1.time ?? .infinity) }
        case .longestDistance:
            return sets
                .filter { $0.distance != nil }
                .max { ($0.distance ?? 0) < ($1.distance ?? 0) }
        case .mostReps:
            return sets
                .filter { $0.reps != nil }
                .max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        }
    }
}
#endif
