import Foundation
import SwiftData

@Model
final class ModelSet {
    @Attribute(.unique) var id: UUID
    var exerciseEntryId: UUID
    var weight: Double?
    var reps: Int?
    var time: Double?
    var distance: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exerciseEntryId: UUID,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseEntryId = exerciseEntryId
        self.weight = weight
        self.reps = reps
        self.time = time
        self.distance = distance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
