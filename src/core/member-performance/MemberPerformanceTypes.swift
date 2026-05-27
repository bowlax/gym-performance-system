import Foundation

/// Returned after saving a session.
struct SessionResult {
    let session: SessionModel
    let newPBs: [PersonalBestModel]
}

/// Returned after attempting a manual PB entry.
struct ManualPBResult {
    let isNewPB: Bool
    let personalBest: PersonalBestModel?
}

/// One week's session count for the consistency view.
struct WeeklySessionCount {
    let weekStarting: Date
    let count: Int
}

/// Best set from a single session for exercise history views.
struct ExerciseSetSummary {
    let sessionDate: Date
    let set: ModelSet
    let isPB: Bool
}
