# C1 -- Configuration Data Access Interface

**Layer:** Resource Access  
**Phase:** 1 -- Active  
**Technology:** SwiftData (iOS 17+)  
**Status:** Defined -- ready for implementation (C2)

---

## Purpose

Provides the Exercise Registry with exercise definitions. Read-only in phase 1 except for the initial seed on first launch. Knows how to retrieve data from the Local Device Store but knows nothing about what the data means.

---

## Protocol Definition

```swift
protocol ConfigurationDataAccess {

    // Retrieve all active exercises, ordered by displayOrder
    func fetchExercises() throws -> [ExerciseModel]

    // Retrieve a single exercise by id
    func fetchExercise(id: UUID) throws -> ExerciseModel?

    // Retrieve all exercises of a specific category
    func fetchExercises(category: ExerciseCategory) throws -> [ExerciseModel]

    // Seed initial exercise definitions on first launch
    // Only called if no exercises exist in the store
    func seedExercises(_ exercises: [ExerciseModel]) throws

}
```

---

## Implementation Notes

- Concrete class name: `SwiftDataConfigurationDataAccess`
- Uses SwiftData `ModelContext` for all persistence operations
- `seedExercises` is called once on first launch if the store contains no exercise records
- All functions are throwing -- errors propagate to the caller
- No update or delete functions -- exercise definitions are managed outside the app in phase 1

---

## File Location

```
src/data/configuration-data-access/ConfigurationDataAccess.swift       -- protocol
src/data/configuration-data-access/SwiftDataConfigurationDataAccess.swift  -- implementation
```
