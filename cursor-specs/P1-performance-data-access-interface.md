# P1 -- Performance Data Access Interface

**Layer:** Resource Access  
**Phase:** 1 -- Active  
**Technology:** SwiftData (iOS 17+)  
**Status:** Defined -- ready for implementation (P2)

---

## Purpose

Reads and writes all session, exercise entry, set and personal best data. Abstracts the underlying storage from the business logic layer entirely. When data moves from local to centralised storage in phase 2, only this component changes -- nothing above it.

---

## Naming Note

`Set` is a reserved type name in Swift. The SwiftData model is named `ModelSet` throughout. This must be consistent across the entire codebase.

---

## Protocol Definition

```swift
protocol PerformanceDataAccess {

    // MARK: -- Sessions
    func saveSession(_ session: SessionModel) throws
    func fetchSessions(memberId: UUID) throws -> [SessionModel]
    func fetchSession(id: UUID) throws -> SessionModel?
    func updateSession(_ session: SessionModel) throws

    // MARK: -- Exercise Entries
    func saveExerciseEntry(_ entry: ExerciseEntryModel) throws
    func fetchExerciseEntries(sessionId: UUID) throws -> [ExerciseEntryModel]
    func updateExerciseEntry(_ entry: ExerciseEntryModel) throws

    // MARK: -- Sets
    func saveSet(_ set: ModelSet) throws
    func fetchSets(exerciseEntryId: UUID) throws -> [ModelSet]
    func updateSet(_ set: ModelSet) throws

    // MARK: -- Personal Bests
    func savePersonalBest(_ pb: PersonalBestModel) throws
    func fetchCurrentPB(memberId: UUID, exerciseId: UUID) throws -> PersonalBestModel?
    func fetchAllPBs(memberId: UUID, exerciseId: UUID) throws -> [PersonalBestModel]
    func fetchCurrentPBs(memberId: UUID) throws -> [PersonalBestModel]
    func markPBAsSuperseded(id: UUID) throws

}
```

---

## Implementation Notes

- Concrete class name: `SwiftDataPerformanceDataAccess`
- Uses SwiftData `ModelContext` for all persistence operations
- No delete functions -- records are never physically deleted per schema design rules
- `markPBAsSuperseded` sets `isCurrent` to false on the specified PersonalBest record
- All functions are throwing -- errors propagate to the caller
- Sessions and sets may be updated but never deleted

---

## File Location

```
src/data/performance-data-access/PerformanceDataAccess.swift            -- protocol
src/data/performance-data-access/SwiftDataPerformanceDataAccess.swift   -- implementation
```
