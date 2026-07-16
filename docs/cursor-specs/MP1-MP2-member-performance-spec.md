# MP1/MP2 -- Member Performance Specification

> **Historical (phase 1 build spec).** Describes the **stored-status** PB model
> (`isCurrent` / supersede / cascade). That model was superseded by issue **#28**
> (derived current / lifetime / badges over sets + manuals). Do not implement
> against this file. Authoritative: `docs/data-schema.md`,
> `docs/gym-performance-system-design.md` (§ Personal bests — derived model),
> `docs/supabase-schema.md`, and `tests/vectors/pb-*.json`.

**Activity:** MP1, MP2  
**Layer:** Business Logic  
**Phase:** 1 -- Active  
**Status:** Defined -- ready for implementation (MP3)  
**Last updated:** May 2026

---

## Purpose

Member Performance is the core business logic component for phase 1. It orchestrates session recording, PB evaluation, manual PB entry, and progression views. It is the only component that coordinates between the Exercise Registry and the Performance Data Access layer.

---

## Schema Updates Required Before Implementation

### 1. PersonalBestModel -- setId becomes optional, entryType added

```swift
@Model
final class PersonalBestModel {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var exerciseId: UUID
    var setId: UUID?            // was non-optional -- now nil for manual entries
    var weight: Double?
    var reps: Int?
    var time: Double?
    var distance: Double?
    var achievedAt: Date
    var isCurrent: Bool
    var entryType: PBEntryType  // new field
    var createdAt: Date

    init(id: UUID = UUID(),
         memberId: UUID,
         exerciseId: UUID,
         setId: UUID? = nil,
         weight: Double? = nil,
         reps: Int? = nil,
         time: Double? = nil,
         distance: Double? = nil,
         achievedAt: Date,
         isCurrent: Bool = true,
         entryType: PBEntryType = .sessionDerived,
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
        self.entryType = entryType
        self.createdAt = createdAt
    }
}
```

### 2. PBEntryType enum -- add to Enums.swift

```swift
enum PBEntryType: String, Codable {
    case sessionDerived   // PB detected automatically from a logged set
    case manualEntry      // PB entered directly by the member
}
```

---

## Supporting Types

Add these to a new file: `src/core/member-performance/MemberPerformanceTypes.swift`

```swift
import Foundation

// Returned after saving a session
struct SessionResult {
    let session: SessionModel
    let newPBs: [PersonalBestModel]  // empty if no PBs were achieved
}

// Returned after attempting a manual PB entry
struct ManualPBResult {
    let isNewPB: Bool
    let personalBest: PersonalBestModel?  // nil if not a new PB
}

// One week's session count for the consistency view
struct WeeklySessionCount {
    let weekStarting: Date  // always a Monday
    let count: Int          // zero if no sessions that week -- never omitted
}
```

---

## Protocol Definition

```swift
protocol MemberPerformance {

    // MARK: -- Session Recording

    // Saves a complete session with all exercise entries and sets.
    // Evaluates every set against PB rules.
    // Returns the session and any new PBs achieved.
    func saveSession(
        _ session: SessionModel,
        entries: [ExerciseEntryModel],
        sets: [UUID: [ModelSet]]        // keyed by ExerciseEntryModel.id
    ) throws -> SessionResult

    // Updates an existing session's top-level fields (notes, caloriesBurned, date)
    // Does not re-evaluate PBs on edit
    func updateSession(_ session: SessionModel) throws

    // Updates an existing set
    // Does not re-evaluate PBs on edit
    func updateSet(_ set: ModelSet) throws

    // MARK: -- Manual PB Entry

    // Records a standalone PB without a session.
    // Validates the entry against the exercise's MeasurementType.
    // Checks whether the entry beats the current PB.
    // If it does (or no current PB exists), saves and returns the new PB.
    // If it doesn't, returns ManualPBResult with isNewPB: false.
    // achievedAt is always set to today's date in phase 1.
    func recordManualPB(
        exerciseId: UUID,
        memberId: UUID,
        weight: Double?,
        reps: Int?,
        time: Double?,
        distance: Double?
    ) throws -> ManualPBResult

    // MARK: -- Progression Views

    // Returns all current PBs for a member (isCurrent: true), ordered by exercise displayOrder
    // Only pbExercise category exercises are included
    func currentPBs(memberId: UUID) throws -> [PersonalBestModel]

    // Returns PB history for a member and exercise, ordered by achievedAt ascending
    // from: the start date of the window -- default to 6 months ago
    func pbProgression(
        memberId: UUID,
        exerciseId: UUID,
        from: Date
    ) throws -> [PersonalBestModel]

    // Returns session consistency as weekly counts for a member
    // from: the start date of the window -- default to 6 months ago
    // Every week in the window is represented, even weeks with zero sessions
    func sessionConsistency(
        memberId: UUID,
        from: Date
    ) throws -> [WeeklySessionCount]

}
```

---

## Implementation Rules

### Session Recording

1. A session must have at least one ExerciseEntry -- reject empty sessions
2. Each ExerciseEntry must reference a valid, active exercise from the Exercise Registry
3. Each ExerciseEntry must have at least one Set
4. Each Set must have the correct measurement fields populated for its exercise's MeasurementType:
   - weightAndReps: weight and reps required
   - weightAndTime: weight and time required
   - timeOnly: time required
   - distanceOnly: distance required
   - repsOnly: reps required
   - weightAndDistance: weight and distance required
5. Save the Session, all ExerciseEntries, and all Sets via PerformanceDataAccess
6. For each Set, call ExerciseRegistry.isPB(set:exercise:currentPB:)
7. If isPB returns true:
   - Call PerformanceDataAccess.markPBAsSuperseded(id:) on the existing current PB
   - Save a new PersonalBest with entryType: .sessionDerived and isCurrent: true
8. Collect all new PBs and return them in SessionResult
9. If no PBs are achieved, return SessionResult with empty newPBs array

### Manual PB Entry

1. Validate that the exercise exists and is active
2. Validate that the correct measurement fields are provided for the exercise's MeasurementType
3. Fetch the current PB for this member and exercise
4. Call ExerciseRegistry.isPB() to evaluate the entry
5. If not a new PB, return ManualPBResult(isNewPB: false, personalBest: nil)
6. If a new PB:
   - If a current PB exists, call markPBAsSuperseded on it
   - Save a new PersonalBest with:
     - entryType: .manualEntry
     - setId: nil
     - achievedAt: Date() -- today
     - isCurrent: true
   - Return ManualPBResult(isNewPB: true, personalBest: newPB)

### Progression Calculation

1. pbProgression fetches all PersonalBest records for the member and exercise where achievedAt >= from, ordered by achievedAt ascending
2. currentPBs fetches all PersonalBest records where memberId matches and isCurrent is true, then filters to pbExercise category exercises, ordered by exercise displayOrder
3. sessionConsistency:
   - Fetch all sessions for the member where date >= from
   - Determine the Monday of the week containing `from`
   - Generate one WeeklySessionCount per week from that Monday to today
   - Count sessions falling within each week
   - Weeks with no sessions get count: 0 -- never omitted

### Edit Rules

- Sessions and sets may be edited but never deleted
- PBs are never re-evaluated when a session or set is edited
- Manual PB entries may not be edited after entry -- phase 1 only

---

## Dependencies

- ExerciseRegistry -- for exercise lookup, validation, and isPB() evaluation
- PerformanceDataAccess -- for all read and write operations
- AccessControl -- for confirming member identity

---

## File Locations

```
src/core/member-performance/MemberPerformance.swift           -- protocol
src/core/member-performance/MemberPerformanceTypes.swift      -- supporting types
src/core/member-performance/DefaultMemberPerformance.swift    -- implementation
```
