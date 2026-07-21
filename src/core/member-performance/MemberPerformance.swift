import Foundation

protocol MemberPerformance {

    // MARK: -- Session Recording

    /// Saves a complete session with all exercise entries and sets.
    /// Returns the session and any new PBs achieved (derived, not stored).
    func saveSession(
        _ session: SessionModel,
        entries: [ExerciseEntryModel],
        sets: [UUID: [ModelSet]]
    ) throws -> SessionResult

    func updateSession(_ session: SessionModel) throws

    func updateSet(_ set: ModelSet) throws

    // MARK: -- Manual PB Entry

    func recordManualPB(
        exerciseId: UUID,
        memberId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        achievedAt: Date?
    ) throws -> ManualPBResult

    /// Updates an existing manual PB in place (values and optional date).
    /// Does not require beating the current PB — used to fix lifetime / undated entries.
    func updateManualPB(
        id: UUID,
        memberId: UUID,
        exerciseId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?,
        achievedAt: Date?
    ) throws

    // MARK: -- Progression Views

    func currentPBs(memberId: UUID) throws -> [PersonalBestModel]

    func pbProgression(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [PersonalBestModel]

    func sessionConsistency(
        memberId: UUID,
        from: Date
    ) throws -> [WeeklySessionCount]

    func exerciseHistory(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [ExerciseSetSummary]

    func deleteSession(id: UUID, memberId: UUID) throws

    // MARK: -- PB Management

    func resetCurrentPB(memberId: UUID, exerciseId: UUID, undo: Bool) throws

    func deletePersonalBest(id: UUID, memberId: UUID, exerciseId: UUID) throws

    func deleteHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws

    func projectedCurrentPBAfterDeletingHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws -> PersonalBestModel?
}

extension MemberPerformance {
    func resetCurrentPB(memberId: UUID, exerciseId: UUID) throws {
        try resetCurrentPB(memberId: memberId, exerciseId: exerciseId, undo: false)
    }
}
