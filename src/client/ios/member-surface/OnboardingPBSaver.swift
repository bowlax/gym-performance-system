import Foundation

enum OnboardingPBSaver {
    /// Saves any complete PB drafts from onboarding. Incomplete or invalid entries are skipped.
    /// - Returns: The number of PBs successfully recorded.
    @discardableResult
    static func saveDraftPBs(
        exercises: [ExerciseModel],
        drafts: [UUID: SetDraftValue],
        memberPerformance: MemberPerformance,
        memberId: UUID
    ) -> Int {
        var savedCount = 0

        for exercise in exercises {
            let draft = drafts[exercise.id] ?? SetDraftValue.initial(for: exercise)
            guard draft.isValidManualPB(for: exercise),
                  let values = draft.manualPBValues(for: exercise) else { continue }

            let didSave = (try? memberPerformance.recordManualPB(
                exerciseId: exercise.id,
                memberId: memberId,
                weight: values.weight,
                reps: values.reps,
                time: values.time,
                distance: values.distance,
                achievedAt: Date()
            )) != nil

            if didSave {
                savedCount += 1
            }
        }

        return savedCount
    }
}
