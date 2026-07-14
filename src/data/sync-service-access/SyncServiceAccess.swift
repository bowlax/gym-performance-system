import Foundation

/// Cloud read/write for sync (pull + push).
protocol SyncServiceAccess: Sendable {
    func upsertSessions(_ rows: [[String: Any]]) async throws
    func upsertExerciseEntries(_ rows: [[String: Any]]) async throws
    func upsertSets(_ rows: [[String: Any]]) async throws
    func upsertPersonalBests(_ rows: [[String: Any]]) async throws

    /// Pull rows whose cloud `synced_at` is later than `since` (nil → all rows with `synced_at` set).
    func pullSessions(since: Date?) async throws -> [CloudSessionRow]
    func pullExerciseEntries(since: Date?) async throws -> [CloudExerciseEntryRow]
    func pullSets(since: Date?) async throws -> [CloudSetRow]
    func pullPersonalBests(since: Date?) async throws -> [CloudPersonalBestRow]
}
