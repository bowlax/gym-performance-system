# E2 -- Exercise Seed Data

**Activity:** E2  
**Layer:** Resource -- Local Device Store  
**Phase:** 1 -- Active  
**Status:** Defined -- ready for implementation  
**Last updated:** May 2026

> This file defines the complete exercise seed data for phase 1. Cursor should implement this as a Swift file containing a static array of ExerciseModel objects. This array is passed to `ConfigurationDataAccess.seedExercises()` on first launch if no exercises exist in the store.

---

## Schema Updates Required Before Implementation

The following changes to the schema and SwiftData models are required before implementing this seed data. Update the relevant files accordingly.

### 1. MeasurementType enum -- add weightAndTime

```swift
enum MeasurementType: String, Codable {
    case weightAndReps
    case weightAndTime      // added -- for plank and similar exercises
    case timeOnly
    case distanceOnly
    case repsOnly
    case weightAndDistance
}
```

### 2. PBRule enum -- add minimumReps parameter to bestWeightAndReps

```swift
enum PBRule: String, Codable {
    case heaviestWeightAtReps   // uses targetReps field on Exercise
    case heaviestWeight
    case bestWeightAndReps      // uses minimumReps field on Exercise
    case fastestTime
    case longestDistance
    case mostReps
}
```

### 3. Exercise model -- add minimumReps field

```swift
@Model
final class ExerciseModel {
    ...
    var targetReps: Int?        // used when pbRule is heaviestWeightAtReps
    var minimumReps: Int?       // used when pbRule is bestWeightAndReps
    ...
}
```

---

## PB Rule Definitions

### heaviestWeightAtReps
A new PB when the heaviest weight is achieved at exactly `targetReps` reps.
The rep count is fixed -- it never varies for this exercise.

### bestWeightAndReps
A new PB when EITHER:
- Weight exceeds the current best weight, with at least `minimumReps` reps, OR
- Reps exceed the current best reps, at or above the current best weight, with at least `minimumReps` reps

The current best weight is a moving floor -- it only ever goes up.
Going below the current best weight can never constitute a PB regardless of reps.

### heaviestWeight
A new PB when the weight exceeds the current best weight.
Used for plank -- weight and time are both recorded but PB is determined by weight only.
Note: to be confirmed with coach -- may change to a compound rule in phase 2.

### mostReps
A new PB when the rep count exceeds the current best.
Used for bodyweight exercises with no weight component.

### fastestTime
A new PB when the time value is lower than the current best.

### longestDistance
A new PB when the distance value is higher than the current best.

---

## Seed Data

### Swift Implementation

```swift
// ExerciseSeedData.swift
// Place in: src/resources/local-store/ExerciseSeedData.swift

extension ExerciseModel {

    static var seedData: [ExerciseModel] {
        [
            // MARK: -- Fixed Rep Barbell Lifts

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Overhead Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 1
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Free Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 2
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Box Squat",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                displayOrder: 3
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "Bench Press 3x5",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 4
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                name: "Bench Press 1x5",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                displayOrder: 5
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                name: "Straight Bar Deadlift",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 6
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                name: "Trap Bar Deadlift",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .heaviestWeightAtReps,
                targetReps: 5,
                minimumReps: nil,
                parentExerciseId: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                displayOrder: 7
            ),

            // MARK: -- Variable Rep Dumbbell and Bodyweight

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                name: "45-Degree Dumbbell Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 8
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
                name: "Flat Dumbbell Press",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 6,
                parentExerciseId: nil,
                displayOrder: 9
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                name: "Chest Dumbbell Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 10
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Split Squat Dumbbell",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 11
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                name: "One Arm Dumbbell Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 12
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                name: "Push-ups",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 13
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
                name: "Overhead Pull-downs",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 14
            ),
            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
                name: "Cable Row",
                category: .pbExercise,
                measurementType: .weightAndReps,
                pbRule: .bestWeightAndReps,
                targetReps: nil,
                minimumReps: 5,
                parentExerciseId: nil,
                displayOrder: 15
            ),

            // MARK: -- Reps Only

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
                name: "Chin-ups",
                category: .pbExercise,
                measurementType: .repsOnly,
                pbRule: .mostReps,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 16
            ),

            // MARK: -- Weight and Time

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
                name: "Plank",
                category: .pbExercise,
                measurementType: .weightAndTime,
                pbRule: .heaviestWeight,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 17
            ),

            // MARK: -- Timed

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
                name: "Ski 500m",
                category: .pbExercise,
                measurementType: .timeOnly,
                pbRule: .fastestTime,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 18
            ),

            // MARK: -- Distance

            ExerciseModel(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
                name: "Bike",
                category: .pbExercise,
                measurementType: .distanceOnly,
                pbRule: .longestDistance,
                targetReps: nil,
                minimumReps: nil,
                parentExerciseId: nil,
                displayOrder: 19
            )
        ]
    }
}
```

---

## Notes

| Exercise | Note |
|---|---|
| Box Squat | parentExerciseId points to Free Squat -- variant relationship for phase 2 use |
| Bench Press 1x5 | parentExerciseId points to Bench Press 3x5 -- variant relationship for phase 2 use |
| Trap Bar Deadlift | parentExerciseId points to Straight Bar Deadlift -- variant relationship for phase 2 use |
| Push-ups | Bodyweight recorded as 0kg. Weighted push-ups use actual plate weight |
| Cable Row | Weight recorded as unitless integer representing stack position, not kg |
| Plank | PB rule is heaviestWeight -- to confirm with coach. May change to compound rule in phase 2 |
| Bike | 60-second effort. Distance recorded in metres |

---

## Decisions to Revisit

| Decision | Owner | When |
|---|---|---|
| Plank PB rule -- heaviestWeight vs compound weight+time rule | Owner to confirm with coach | Before phase 2 |
| Conditioning exercises -- full list to be defined | Owner | Phase 2 scoping session |

---

## File Location

```
src/resources/local-store/ExerciseSeedData.swift
```
