# Data Schema Specification

**Project:** Gym Performance System  
**Phase:** 1 -- iOS, On-Device, Members Only  
**Technology:** SwiftData (iOS 17+)  
**Status:** Validated -- ready for implementation  
**Last updated:** May 2026

> This document is the authoritative schema specification for phase 1. All Resource Access layer components must implement against this schema. Do not modify without updating the project document and re-validating against use cases.

---

## Design Principles

- **UUID primary keys throughout** -- enables collision-free merging when data centralises in phase 2. Never use auto-incrementing integers.
- **Soft fields for phase 2 data** -- optional fields anticipated for phase 2 (e.g. `parentExerciseId`) are present but unused in phase 1.
- **No deletes** -- records are never physically deleted. Members may edit but not delete sessions or sets. This protects PB history integrity.
- **Nullable measurement fields** -- Set carries nullable fields for all measurement types. The Exercise.measurementType determines which fields are relevant for any given exercise.
- **PB evaluation is exercise-driven** -- PB rules live on the Exercise entity. Member Performance consults Exercise before evaluating any set.

---

## Entities

### UserIdentity

The identity of a system user. In phase 1, a single hardcoded member record. In phase 2, populated from central authentication.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| role | Role | No | See enums |
| displayName | String | No | Member's name as displayed in the app |
| createdAt | Date | No | |

---

### Exercise

Defines an exercise, how it is measured, and -- for PB exercises -- what constitutes a personal best. Authoritative source for all exercise definitions. Read-only in phase 1, bundled with the app.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| name | String | No | e.g. "Back Squat", "Incline Bench Press" |
| category | ExerciseCategory | No | See enums |
| measurementType | MeasurementType | No | See enums -- determines which Set fields are used |
| pbRule | PBRule | Yes | Nil for conditioning exercises |
| targetReps | Int | Yes | Populated only when pbRule is heaviestWeightAtReps |
| parentExerciseId | UUID | Yes | Nil unless this exercise is a variant of another. References Exercise.id |
| displayOrder | Int | No | Controls ordering in exercise lists |
| isActive | Bool | No | False for retired exercises. Never deleted |
| createdAt | Date | No | |

**Rules:**
- If `category` is `conditioning`, `pbRule` and `targetReps` must be nil
- If `category` is `pbExercise`, `pbRule` must be populated
- If `pbRule` is `heaviestWeightAtReps`, `targetReps` must be populated
- Only exercises where `isActive` is true appear in session logging

---

### Session

A training session on a specific date. The top-level container for all exercise and set data.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| memberId | UUID | No | Foreign key → UserIdentity.id |
| date | Date | No | The date training took place |
| notes | String | Yes | Optional free text member observations |
| caloriesBurned | Int | Yes | Optional, member-entered from wearable device |
| createdAt | Date | No | |
| updatedAt | Date | No | Updated on any edit |

**Rules:**
- One session per member per date is the expected pattern, but not enforced at schema level
- Sessions may be edited but never deleted

---

### ExerciseEntry

One exercise performed within a session. A session contains one or more exercise entries.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| sessionId | UUID | No | Foreign key → Session.id |
| exerciseId | UUID | No | Foreign key → Exercise.id |
| createdAt | Date | No | |
| updatedAt | Date | No | Updated on any edit |

**Rules:**
- An exercise entry may not be deleted, only edited
- Each exercise entry must have at least one associated Set

---

### Set

One logged set within an exercise entry. Members log their best one or best few sets per exercise -- not every warm-up set.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| exerciseEntryId | UUID | No | Foreign key → ExerciseEntry.id |
| weight | Double | Yes | Kilograms. Nil for non-weight exercises |
| reps | Int | Yes | Nil for non-rep exercises |
| time | Double | Yes | Seconds. Nil for non-timed exercises |
| distance | Double | Yes | Metres. Nil for non-distance exercises |
| createdAt | Date | No | |
| updatedAt | Date | No | Updated on any edit |

**Rules:**
- The Exercise.measurementType determines which fields must be populated for a valid set
- Sets may not be deleted, only edited
- At least one measurement field must be populated

**Populated fields by MeasurementType:**

| MeasurementType | weight | reps | time | distance |
|---|---|---|---|---|
| weightAndReps | ✅ | ✅ | -- | -- |
| timeOnly | -- | -- | ✅ | -- |
| distanceOnly | -- | -- | -- | ✅ |
| repsOnly | -- | ✅ | -- | -- |
| weightAndDistance | ✅ | -- | -- | ✅ |

---

### PersonalBest

A PB record for a member against a specific exercise. Derived from Set data by Member Performance using Exercise.pbRule. All PB records are retained for progression history -- only the current PB has `isCurrent: true`.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| memberId | UUID | No | Foreign key → UserIdentity.id |
| exerciseId | UUID | No | Foreign key → Exercise.id |
| setId | UUID | No | Foreign key → Set.id -- the set that achieved this PB |
| weight | Double | Yes | Mirrors the achieving set's relevant value |
| reps | Int | Yes | |
| time | Double | Yes | |
| distance | Double | Yes | |
| achievedAt | Date | No | Date of the session in which this PB was set |
| isCurrent | Bool | No | True for the current PB, false for historical |
| createdAt | Date | No | |

**Rules:**
- Only one PersonalBest per member per exercise may have `isCurrent: true` at any time
- When a new PB is set, the existing `isCurrent` record is updated to false and a new record is inserted with `isCurrent: true`
- PersonalBest records are never deleted
- Only exercises where `category` is `pbExercise` generate PersonalBest records

---

## Enums

### Role
```
member    -- gym member, accesses their own data only
coach     -- coach, accesses all member data (phase 2)
owner     -- owner/manager, full access (phase 2)
```

### ExerciseCategory
```
pbExercise      -- appears on the board and in PB views. PB is tracked and evaluated
conditioning    -- logged in sessions for tracking. No PB defined or evaluated
```

### MeasurementType
```
weightAndReps       -- e.g. Back Squat: 100kg x 5 reps
timeOnly            -- e.g. 400m Run: 1:32
distanceOnly        -- e.g. Rowing: 2000m
repsOnly            -- e.g. Pull-ups: 15 reps
weightAndDistance   -- e.g. Weighted Carry: 40kg x 20m
```

### PBRule
```
heaviestWeightAtReps    -- heaviest weight achieved at exactly targetReps reps
heaviestWeight          -- heaviest weight regardless of rep count
fastestTime             -- lowest time value
longestDistance         -- highest distance value
mostReps                -- highest rep count
```

---

## Relationships

```
UserIdentity  ──(1:many)──  Session
UserIdentity  ──(1:many)──  PersonalBest
Session       ──(1:many)──  ExerciseEntry
ExerciseEntry ──(1:many)──  Set
Exercise      ──(1:many)──  ExerciseEntry
Exercise      ──(1:many)──  PersonalBest
Exercise      ──(0:1)────── Exercise (self -- parentExerciseId for variants)
Set           ──(1:0:1)──── PersonalBest (a set may or may not be a PB)
```

---

## Phase 2 Anticipations

The following schema decisions have been made specifically to ease phase 2 migration:

| Decision | Rationale |
|---|---|
| UUID primary keys | Enables collision-free merging of on-device records into a central store |
| `parentExerciseId` on Exercise | Supports exercise variant grouping in coach and owner analytical views |
| `role` on UserIdentity | Schema already supports coach and owner roles even though only member is active in phase 1 |
| `isCurrent` on PersonalBest | Supports full PB history views without schema change in phase 2 |
| Nullable measurement fields on Set | Accommodates any future exercise measurement types without schema change |

---

## Validation Against Phase 1 Use Cases

| Use Case | Entities Used | Result |
|---|---|---|
| Record a training session | Session, ExerciseEntry, Set, Exercise | ✅ |
| Record a personal best | Set, Exercise (pbRule), PersonalBest | ✅ |
| View progression over time | PersonalBest (history via isCurrent) | ✅ |
| View current personal bests | PersonalBest (isCurrent: true) | ✅ |
| View consistency over time | Session (date, memberId) | ✅ |
| Goals, weight, injuries, flags, commentary | Out of scope -- phase 2 | ✅ Correctly absent |
