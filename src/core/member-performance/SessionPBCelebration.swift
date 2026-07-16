import Foundation

/// Whether a logged session set earned a PB celebration (strict improvement only).
enum SessionPBCelebration {
    /// Post-save derived current must be a session set that strictly beats pre-save current.
    static func earnedNewPB(
        exercise: ExerciseModel,
        before: PBReadDerivation.ExerciseResult?,
        after: PBReadDerivation.ExerciseResult,
        sessionSetIds: Set<UUID>,
        sessionSets: [ModelSet]
    ) -> PersonalBestModel? {
        guard let rule = exercise.pbRule,
              let current = after.currentPB,
              let setId = current.setId,
              sessionSetIds.contains(setId),
              let winningSet = sessionSets.first(where: { $0.id == setId }) else {
            return nil
        }

        guard PBRuleEvaluator.isPB(
            rule: rule,
            current: before?.currentPB.map(PBRuleEvaluator.Measurement.init(personalBest:)),
            newSet: PBRuleEvaluator.Measurement(set: winningSet)
        ) else {
            return nil
        }

        return current
    }
}
