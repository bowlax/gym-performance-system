import Foundation
import SwiftData

@Model
final class ExerciseModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var measurementType: MeasurementType
    var pbRule: PBRule?
    var targetReps: Int?
    var minimumReps: Int?
    var parentExerciseId: UUID?
    var displayOrder: Int
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        measurementType: MeasurementType,
        pbRule: PBRule? = nil,
        targetReps: Int? = nil,
        minimumReps: Int? = nil,
        parentExerciseId: UUID? = nil,
        displayOrder: Int,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.measurementType = measurementType
        self.pbRule = pbRule
        self.targetReps = targetReps
        self.minimumReps = minimumReps
        self.parentExerciseId = parentExerciseId
        self.displayOrder = displayOrder
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
