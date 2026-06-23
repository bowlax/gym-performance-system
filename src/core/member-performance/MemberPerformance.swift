import Foundation

protocol MemberPerformance {

    // MARK: -- Session Recording

    /// Saves a complete session with all exercise entries and sets.
    /// Evaluates every set against PB rules.
    /// Returns the session and any new PBs achieved.
    func saveSession(
        _ session: SessionModel,
        entries: [ExerciseEntryModel],
        sets: [UUID: [ModelSet]]
    ) throws -> SessionResult

    /// Updates an existing session's top-level fields (notes, caloriesBurned, date).
    /// Does not re-evaluate PBs on edit.
    func updateSession(_ session: SessionModel) throws

    /// Updates an existing set.
    /// Does not re-evaluate PBs on edit.
    func updateSet(_ set: ModelSet) throws

    // MARK: -- Manual PB Entry

    /// Records a standalone PB without a session.
    func recordManualPB(
        exerciseId: UUID,
        memberId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?
    ) throws -> ManualPBResult

    // MARK: -- Progression Views

    /// Returns all current PBs for a member, ordered by exercise displayOrder.
    func currentPBs(memberId: UUID) throws -> [PersonalBestModel]

    /// Returns PB history for a member and exercise, ordered by achievedAt ascending.
    func pbProgression(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [PersonalBestModel]

    /// Returns session consistency as weekly counts for a member.
    func sessionConsistency(
        memberId: UUID,
        from: Date
    ) throws -> [WeeklySessionCount]

    /// Returns one ExerciseSetSummary per session where this exercise was logged,
    /// representing the best set from that session, ordered by sessionDate ascending.
    func exerciseHistory(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [ExerciseSetSummary]

    /// Deletes a session and cascades removal of entries, sets, and affected PBs.
    func deleteSession(id: UUID, memberId: UUID) throws

    // MARK: -- PB Management

    /// Clears the current PB for an exercise while preserving history.
    func resetCurrentPB(memberId: UUID, exerciseId: UUID) throws

    /// Permanently deletes a PB record, promoting the previous PB if needed.
    func deletePersonalBest(id: UUID, memberId: UUID, exerciseId: UUID) throws

    /// Deletes a progression history entry (session set, session PB, or manual PB).
    func deleteHistoryEntry(
        setId: UUID?,
        personalBestId: UUID?,
        memberId: UUID,
        exerciseId: UUID
    ) throws
}
