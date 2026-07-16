import Foundation

protocol PerformanceDataAccess {

    // MARK: -- Sessions
    func saveSession(_ session: SessionModel) throws
    func fetchSessions(memberId: UUID) throws -> [SessionModel]
    func fetchSession(id: UUID) throws -> SessionModel?
    func updateSession(_ session: SessionModel) throws

    // MARK: -- Exercise Entries
    func saveExerciseEntry(_ entry: ExerciseEntryModel) throws
    func fetchExerciseEntries(sessionId: UUID) throws -> [ExerciseEntryModel]
    func updateExerciseEntry(_ entry: ExerciseEntryModel) throws

    // MARK: -- Sets
    func saveSet(_ set: ModelSet) throws
    func fetchSets(exerciseEntryId: UUID) throws -> [ModelSet]
    func updateSet(_ set: ModelSet) throws

    // MARK: -- Personal Bests (manual entries only)
    func savePersonalBest(_ pb: PersonalBestModel) throws
    func fetchAllPBs(memberId: UUID, exerciseId: UUID) throws -> [PersonalBestModel]
}
