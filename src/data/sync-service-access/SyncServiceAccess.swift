import Foundation

/// Cloud read/write for sync (pull + push).
protocol SyncServiceAccess: Sendable {
    func upsertSessions(_ rows: [[String: Any]]) async throws
    func upsertExerciseEntries(_ rows: [[String: Any]]) async throws
    func upsertSets(_ rows: [[String: Any]]) async throws
    func upsertPersonalBests(_ rows: [[String: Any]]) async throws
    func upsertExerciseResets(_ rows: [[String: Any]]) async throws

    /// Settings-only PATCH of the JWT member row. Does not create members.
    /// - Returns: `true` if a row was updated; `false` if zero rows matched
    ///   (broker has not established identity — caller must not invent a row).
    func patchMemberSettings(memberId: UUID, fields: [String: Any]) async throws -> Bool

    /// Pull rows whose cloud `synced_at` is later than `since` (nil → all rows with `synced_at` set).
    func pullSessions(since: Date?) async throws -> [CloudSessionRow]
    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow]
    func pullSets(since: Date?) async throws -> [CloudSetRow]
    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow]
    func pullMembers(since: Date?) async throws -> [CloudMemberRow]
    func pullExerciseResets(since: Date?) async throws -> [CloudExerciseResetRow]
}
