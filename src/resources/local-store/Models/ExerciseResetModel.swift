import Foundation
import SwiftData

/// Local storage for one `reset_at` date per member-exercise (#28 STEP 2).
/// Mirrors cloud `exercise_resets`. Sparse — only written when a reset exists.
@Model
final class ExerciseResetModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var exerciseId: UUID
    /// Calendar date of the reset line (UTC day).
    var resetAt: Date
    var createdAt: Date
    var updatedAt: Date
    /// Set when successfully pushed to the central store.
    var syncedAt: Date?
    /// Soft-delete clears the reset line without removing sync history.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        memberId: UUID,
        exerciseId: UUID,
        resetAt: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.memberId = memberId
        self.exerciseId = exerciseId
        self.resetAt = resetAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.deletedAt = deletedAt
    }
}
