import Foundation
import SwiftData

@Model
final class PersonalBestModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var exerciseId: UUID
    var setId: UUID?
    var weight: Double?
    var reps: Int?
    var time: Double?
    var distance: Double?
    var achievedAt: Date
    var isCurrent: Bool
    var wasReset: Bool = false
    var entryType: PBEntryType
    var createdAt: Date

    init(
        id: UUID = UUID(),
        memberId: UUID,
        exerciseId: UUID,
        setId: UUID? = nil,
        weight: Double? = nil,
        reps: Int? = nil,
        time: Double? = nil,
        distance: Double? = nil,
        achievedAt: Date,
        isCurrent: Bool = true,
        wasReset: Bool = false,
        entryType: PBEntryType = .sessionDerived,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.memberId = memberId
        self.exerciseId = exerciseId
        self.setId = setId
        self.weight = weight
        self.reps = reps
        self.time = time
        self.distance = distance
        self.achievedAt = achievedAt
        self.isCurrent = isCurrent
        self.wasReset = wasReset
        self.entryType = entryType
        self.createdAt = createdAt
    }
}
