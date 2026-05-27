import Foundation
import SwiftData

@Model
final class ExerciseEntryModel {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        exerciseId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
