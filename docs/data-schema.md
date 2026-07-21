# Data Schema Specification

**Project:** Gym Performance System  
**Phase:** 1 local store (SwiftData), aligned with live derived PB model (#28)  
**Technology:** SwiftData (iOS 17+)  
**Status:** Authoritative for local entities; PB *status* is derived, not stored  
**Last updated:** July 2026

> This document is the authoritative local schema for member devices. Resource Access
> implements against it. PB current / lifetime / badges are **derived at read time**
> from sets + manual entries (issue #28) — not stored flags. Cloud mirror:
> `docs/supabase-schema.md`. Design record: `docs/gym-performance-system-design.md`.

---

## Design Principles

- **UUID primary keys throughout** -- enables collision-free merging into the central store.
- **Soft fields for later work** -- optional fields anticipated for later phases (e.g. `parentExerciseId`) may be present but unused.
- **Session deletion** -- sessions may be deleted. Deletion removes exercise entries and sets. Current / lifetime PBs re-derive automatically; there is no cascade promotion of stored PB rows.
- **Nullable measurement fields** -- Set carries nullable fields for all measurement types. The Exercise.measurementType determines which fields are relevant for any given exercise.
- **PB evaluation is exercise-driven** -- PB rules live on the Exercise entity. Derivation and write-time evaluation consult Exercise before comparing records.
- **Derivation over storage for PB status** -- `sets` plus manual `PersonalBest` entries are the workout record. Current / lifetime / historic badges are computed, not flagged on rows.

---

## Personal-best derivation (as built, #28)

Inputs per member-exercise:

| Input | Role |
|---|---|
| Sets (via sessions / entries) | Session-dated candidate records |
| Manual `PersonalBest` rows | Candidates with no set behind them (`entryType: manualEntry`) |
| `ExerciseReset.resetAt` (if any) | Line that filters **current** only |
| Member staleness setting | Whether records expire; window = N complete calendar periods |

Semantics:

- **Fresh** = today is strictly before the record’s expiry. Expiry = start of the period after N complete calendar periods (quarters or months) since `achievedAt`. When staleness is OFF, **dated** records never expire (always fresh). **Undated manuals are never fresh, regardless of the staleness setting** — deliberate decision (2026-07-21), not an incidental code-order effect. Reasoning: “current” is a claim about *now*, which an undated entry cannot support even when time-filtering is off; **lifetime** remains the only place an undated entry can appear (vector TC-D20).
- **Current PB** = best record where `achievedAt` is strictly after `resetAt` (if any) **and** the record is fresh. Tie under the PB rule → **most recent `achievedAt` wins**. Undated entries are excluded because they are never fresh.
- **Lifetime PB** = best record with **no** reset filter and **no** freshness filter. Reset clears current standing only; lifetime is unaffected. Undated manuals participate here.
- **Historic badges** = running maximum over dated records in `achievedAt` order. Equal to the running max is **not** badged (earliest breakthrough only). Reset does not affect badges. Undated manuals are excluded from badge history.
- **PB rule** (`bestWeightAndReps`, etc.) is unchanged — applied to the eligible pool.

Display:

- Board: current PB only (empty if none).
- Progression: current + lifetime element when lifetime **strictly beats** current under the PB rule (ties hide). Not gated on staleness or record-id inequality.
- Progression History lists dated sets/manuals **and undated manuals** (labeled Undated) so lifetime-only entries can be edited or deleted. Undated rows are excluded from the chart.
- Reset appears as a dated timeline marker, not a flag on a PB row.

### Decisions that must not be lost

1. **Existing `was_reset` rows were NOT migrated** into `exercise_resets` (deliberate). Tiny population, reset dates unrecoverable for local-only resets, migration would ship untested. Members who had reset may see a PB reappear and redo the reset in the new undoable model. Recorded on issue #28.
2. **Undated manuals are never current, even with staleness OFF** (decision 2026-07-21). Current is a claim about now; undated cannot support that claim when time-filtering is disabled. Lifetime-only. Spec vector: `TC-D20` in `pb-derivation-vectors.json`.
3. **Real-device check:** all 19 then-current PBs matched derivation and every session-derived `setId` resolved to a live set. Derivation therefore reads **sets + manuals**, not legacy PB rows. If orphan PB rows ever appear without sets in the wild, derivation would lose that history and this needs revisiting.

---

## Entities

### UserIdentity

The identity / member-state row. On device, the member UUID and display name live in UserDefaults (Access Control); this SwiftData model holds **syncable member state** (staleness), keyed to that UUID via `MemberState`.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key — same as UserDefaults member UUID when present |
| role | Role | No | See enums |
| displayName | String | No | |
| createdAt | Date | No | |
| stalenessEnabled | Bool | No | Default false (OFF) |
| stalenessPeriods | Int | No | Default 2 |
| stalenessUnit | StalenessPeriodUnit | No | `quarter` or `month` |
| updatedAt | Date | No | LWW / dirty push |
| syncedAt | Date | Yes | Set when pushed |

---

### Exercise

Defines an exercise, how it is measured, and — for PB exercises — what constitutes a personal best. Authoritative source for all exercise definitions. Bundled / seeded with the app in phase 1.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| name | String | No | e.g. "Back Squat", "Incline Bench Press" |
| category | ExerciseCategory | No | See enums |
| measurementType | MeasurementType | No | See enums — determines which Set fields are used |
| pbRule | PBRule | Yes | Nil for conditioning exercises |
| targetReps | Int | Yes | Populated only when pbRule is heaviestWeightAtReps |
| minimumReps | Int | Yes | Populated only when pbRule is bestWeightAndReps |
| parentExerciseId | UUID | Yes | Nil unless this exercise is a variant of another. References Exercise.id |
| displayOrder | Int | No | Controls ordering in exercise lists |
| isActive | Bool | No | False for retired exercises. Never deleted |
| createdAt | Date | No | |

**Rules:**
- If `category` is `conditioning`, `pbRule`, `targetReps` and `minimumReps` must be nil
- If `category` is `pbExercise`, `pbRule` must be populated
- If `pbRule` is `heaviestWeightAtReps`, `targetReps` must be populated
- If `pbRule` is `bestWeightAndReps`, `minimumReps` must be populated
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
- Sessions may be edited
- Sessions may be deleted. Deletion removes ExerciseEntries and Sets. PB status re-derives from remaining sets + manuals

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
- Exercise entries are removed when their parent session is deleted
- Each exercise entry must have at least one associated Set

---

### Set

One logged set within an exercise entry. Members log their best one or best few sets per exercise — not every warm-up set. Sets are candidates for derived current / lifetime / badges.

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
- At least one measurement field must be populated

**Populated fields by MeasurementType:**

| MeasurementType | weight | reps | time | distance |
|---|---|---|---|---|
| weightAndReps | ✅ | ✅ | -- | -- |
| weightAndTime | ✅ | -- | ✅ | -- |
| timeOnly | -- | -- | ✅ | -- |
| distanceOnly | -- | -- | -- | ✅ |
| repsOnly | -- | ✅ | -- | -- |
| weightAndDistance | ✅ | -- | -- | ✅ |

---

### PersonalBest

**Manual entries only** (no set behind them). Session PBs are not stored — they are derived from sets. Legacy `sessionDerived` rows may still exist from older builds but are not written or used for derivation.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| memberId | UUID | No | Foreign key → UserIdentity.id |
| exerciseId | UUID | No | Foreign key → Exercise.id |
| setId | UUID | Yes | Always nil for new manuals |
| entryType | PBEntryType | No | `manualEntry` for writes; `sessionDerived` is legacy only |
| weight | Double | Yes | |
| reps | Int | Yes | |
| time | Double | Yes | |
| distance | Double | Yes | |
| achievedAt | Date | Yes | Optional. Undated manuals are never fresh (even with staleness OFF) — lifetime-only; listed in History as Undated for edit/delete |
| createdAt | Date | No | |
| updatedAt | Date | Yes | LWW / dirty |
| syncedAt | Date | Yes | |
| deletedAt | Date | Yes | Soft delete |

**Rules:**
- Only exercises where `category` is `pbExercise` participate in PB derivation
- `entryType` is internal bookkeeping — not displayed to members
- There is **no** `isCurrent` / `wasReset` — status is derived
- Manual delete soft-deletes (or removes) the row; current standing re-derives

---

### ExerciseReset

One `resetAt` date per member-exercise. Sparse — only written when a reset exists. Undo soft-deletes the row. Affects **current** derivation only.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| id | UUID | No | Primary key |
| memberId | UUID | No | |
| exerciseId | UUID | No | Unique with memberId |
| resetAt | Date | No | Calendar date of the reset line |
| createdAt | Date | No | |
| updatedAt | Date | No | Later resets overwrite `resetAt` (monotonic) |
| syncedAt | Date | Yes | |
| deletedAt | Date | Yes | Soft-delete = undo |

---

## Enums

### PBEntryType
```
sessionDerived    -- legacy; no longer written. Session PBs are derived from sets
manualEntry       -- PB entered directly by the member without a session
```

### StalenessPeriodUnit
```
quarter    -- calendar quarters (Jan–Mar, Apr–Jun, Jul–Sep, Oct–Dec)
month      -- calendar months
```

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
weightAndTime       -- e.g. Plank: 20kg held for 45 seconds
timeOnly            -- e.g. Ski 500m: 1:52
distanceOnly        -- e.g. Bike: 420m in 60 seconds
repsOnly            -- e.g. Chin-ups: 15 reps
weightAndDistance   -- e.g. Weighted Carry: 40kg x 20m
```

### PBRule
```
heaviestWeightAtReps    -- heaviest weight achieved at exactly targetReps reps. Rep count is fixed
heaviestWeight          -- heaviest weight regardless of reps or time
bestWeightAndReps       -- moving weight floor with minimum rep threshold (see minimumReps on Exercise)
                        -- new PB when weight exceeds current best at or above minimumReps, OR
                        -- reps exceed current best at or above current best weight and minimumReps
fastestTime             -- lowest time value
longestDistance         -- highest distance value
mostReps                -- highest rep count
```

---

## Relationships

```
UserIdentity   ──(1:many)──  Session
UserIdentity   ──(1:many)──  PersonalBest (manual entries)
UserIdentity   ──(1:many)──  ExerciseReset
Session        ──(1:many)──  ExerciseEntry
ExerciseEntry  ──(1:many)──  Set
Exercise       ──(1:many)──  ExerciseEntry
Exercise       ──(1:many)──  PersonalBest
Exercise       ──(1:many)──  ExerciseReset
Exercise       ──(0:1)────── Exercise (self -- parentExerciseId for variants)
```

Derived (not stored): current PB, lifetime PB, badge set IDs — from sets + manuals + reset + staleness.

---

## Phase 2 Anticipations

| Decision | Rationale |
|---|---|
| UUID primary keys | Enables collision-free merging of on-device records into a central store |
| `parentExerciseId` on Exercise | Supports exercise variant grouping in coach and owner analytical views |
| `role` on UserIdentity | Schema already supports coach and owner roles even though only member is active in phase 1 |
| Nullable measurement fields on Set | Accommodates any future exercise measurement types without schema change |
| Derived PB status | Cloud and device share the same derivation vectors (`tests/vectors/pb-*.json`) |

---

## Validation Against Phase 1 Use Cases

| Use Case | Entities / path | Result |
|---|---|---|
| Record a training session | Session, ExerciseEntry, Set, Exercise | ✅ |
| Record a personal best | Sets + manuals → derivation; manuals stored in PersonalBest | ✅ |
| View progression over time | Sets + manuals + badges (derived) + reset markers | ✅ |
| View current personal bests | Derived current PB over sets + manuals | ✅ |
| View consistency over time | Session (date, memberId) | ✅ |
| Goals, weight, injuries, flags, commentary | Out of scope -- phase 2 | ✅ Correctly absent |
