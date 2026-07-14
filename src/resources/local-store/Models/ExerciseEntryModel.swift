import Foundation
import SwiftData

@Model
final class ExerciseEntryModel {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date
    /// Set when this record has been successfully pushed to the central store.
    var syncedAt: Date?
    /// Soft-delete timestamp; nil means active.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        exerciseId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.deletedAt = deletedAt
    }
}
