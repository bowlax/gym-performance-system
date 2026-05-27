# SwiftData Model Definitions

**Layer:** Resource  
**Phase:** 1 -- Active  
**Technology:** SwiftData (iOS 17+)  
**Location:** `src/resources/local-store/`  
**Status:** Ready for implementation

> These are the SwiftData model classes derived directly from `docs/data-schema.md`. Implement each as a SwiftData `@Model` class. All rules and constraints from the schema specification apply.

---

## Enums

```swift
enum Role: String, Codable {
    case member
    case coach
    case owner
}

enum ExerciseCategory: String, Codable {
    case pbExercise
    case conditioning
}

enum MeasurementType: String, Codable {
    case weightAndReps
    case timeOnly
    case distanceOnly
    case repsOnly
    case weightAndDistance
}

enum PBRule: String, Codable {
    case heaviestWeightAtReps
    case heaviestWeight
    case fastestTime
    case longestDistance
    case mostReps
}
```

---

## Model Classes

### UserIdentityModel

```swift
@Model
final class UserIdentityModel {
    @Attribute(.unique) var id: UUID
    var role: Role
    var displayName: String
    var createdAt: Date

    init(id: UUID = UUID(),
         role: Role,
         displayName: String,
         createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
```

---

### ExerciseModel

```swift
@Model
final class ExerciseModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var measurementType: MeasurementType
    var pbRule: PBRule?
    var targetReps: Int?
    var parentExerciseId: UUID?
    var displayOrder: Int
    var isActive: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         category: ExerciseCategory,
         measurementType: MeasurementType,
         pbRule: PBRule? = nil,
         targetReps: Int? = nil,
         parentExerciseId: UUID? = nil,
         displayOrder: Int,
         isActive: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.category = category
        self.measurementType = measurementType
        self.pbRule = pbRule
        self.targetReps = targetReps
        self.parentExerciseId = parentExerciseId
        self.displayOrder = displayOrder
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
```

---

### SessionModel

```swift
@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var date: Date
    var notes: String?
    var caloriesBurned: Int?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         memberId: UUID,
         date: Date,
         notes: String? = nil,
         caloriesBurned: Int? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.memberId = memberId
        self.date = date
        self.notes = notes
        self.caloriesBurned = caloriesBurned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

---

### ExerciseEntryModel

```swift
@Model
final class ExerciseEntryModel {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var exerciseId: UUID
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         sessionId: UUID,
         exerciseId: UUID,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

---

### ModelSet

Note: Named `ModelSet` to avoid collision with Swift's built-in `Set` type.

```swift
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

    init(id: UUID = UUID(),
         exerciseEntryId: UUID,
         weight: Double? = nil,
         reps: Int? = nil,
         time: Double? = nil,
         distance: Double? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
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
```

---

### PersonalBestModel

```swift
@Model
final class PersonalBestModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var exerciseId: UUID
    var setId: UUID
    var weight: Double?
    var reps: Int?
    var time: Double?
    var distance: Double?
    var achievedAt: Date
    var isCurrent: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         memberId: UUID,
         exerciseId: UUID,
         setId: UUID,
         weight: Double? = nil,
         reps: Int? = nil,
         time: Double? = nil,
         distance: Double? = nil,
         achievedAt: Date,
         isCurrent: Bool = true,
         createdAt: Date = Date()) {
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
        self.createdAt = createdAt
    }
}
```

---

## ModelContainer Setup

The app entry point needs a configured `ModelContainer` with all models registered:

```swift
let schema = Schema([
    UserIdentityModel.self,
    ExerciseModel.self,
    SessionModel.self,
    ExerciseEntryModel.self,
    ModelSet.self,
    PersonalBestModel.self
])

let modelConfiguration = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false
)

let container = try ModelContainer(
    for: schema,
    configurations: [modelConfiguration]
)
```

Place this in the app's main entry point file.

---

## File Locations

```
src/resources/local-store/Models/UserIdentityModel.swift
src/resources/local-store/Models/ExerciseModel.swift
src/resources/local-store/Models/SessionModel.swift
src/resources/local-store/Models/ExerciseEntryModel.swift
src/resources/local-store/Models/ModelSet.swift
src/resources/local-store/Models/PersonalBestModel.swift
src/resources/local-store/Models/Enums.swift
src/resources/local-store/ModelContainer+Setup.swift
```
