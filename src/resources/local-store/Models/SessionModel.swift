import Foundation
import SwiftData

@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var date: Date
    var notes: String?
    var caloriesBurned: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        memberId: UUID,
        date: Date,
        notes: String? = nil,
        caloriesBurned: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberId = memberId
        self.date = date
        self.notes = notes
        self.caloriesBurned = caloriesBurned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
