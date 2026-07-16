# MP4 -- Member Performance Test Specification

> **Historical (phase 1 build spec).** Tests assume the **stored-status** PB model
> (`isCurrent` / cascade / `wasReset`). Superseded by issue **#28**. Live tests live
> under `tests/core/` and shared vectors under `tests/vectors/`. Authoritative
> behaviour: `docs/data-schema.md`, `docs/gym-performance-system-design.md`.

**Activity:** MP4  
**Layer:** Business Logic  
**Phase:** 1 -- Active  
**Status:** Specified -- ready for implementation  
**Framework:** Swift Testing or XCTest  
**Location:** `tests/core/MemberPerformanceTests.swift`

> All tests use an in-memory ModelContainer. Reuse TestHelpers.swift from tests/data/.
> All tests use the seeded exercise data from ExerciseModel.seedData.

---

## Test Setup

Each test should:
1. Create an in-memory ModelContainer with all models registered
2. Initialise SwiftDataConfigurationDataAccess and seed exercises
3. Initialise SwiftDataPerformanceDataAccess
4. Initialise DefaultExerciseRegistry
5. Initialise DefaultMemberPerformance with the above dependencies
6. Use a fixed test member UUID for all member-specific operations

```swift
let testMemberId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
```

---

## Session Recording Tests

### TC-MP1: Save a valid session with one exercise and one set

```
Given: a session with one ExerciseEntry (Free Squat) and one Set (80kg x 5 reps)
When: saveSession() is called
Then: the session is persisted
And: the exercise entry is persisted
And: the set is persisted
And: SessionResult.newPBs contains one PersonalBest for Free Squat
And: the PersonalBest has entryType: sessionDerived
And: the PersonalBest has isCurrent: true
```

### TC-MP2: Save a session where no PB is achieved

```
Given: an existing PB for Free Squat at 100kg x 5 reps
When: a session is saved with Free Squat at 90kg x 5 reps
Then: SessionResult.newPBs is empty
And: the existing PB remains current
```

### TC-MP3: Save a session that beats an existing PB

```
Given: an existing PB for Free Squat at 80kg x 5 reps (isCurrent: true)
When: a session is saved with Free Squat at 85kg x 5 reps
Then: SessionResult.newPBs contains one PersonalBest at 85kg x 5 reps
And: the new PersonalBest has isCurrent: true
And: the previous PersonalBest at 80kg has isCurrent: false
And: fetchAllPBs returns both records
```

### TC-MP4: Save a session with multiple exercises, multiple PBs

```
Given: no existing PBs
When: a session is saved with Free Squat (80kg x 5) and Overhead Press (50kg x 5)
Then: SessionResult.newPBs contains two PersonalBest records
And: both have isCurrent: true
```

### TC-MP5: Save a session with a conditioning exercise -- no PB evaluated

```
Given: a conditioning exercise in the session
When: saveSession() is called
Then: no PersonalBest record is created for the conditioning exercise
And: the session and set are still persisted
```

### TC-MP6: Reject a session with no exercise entries

```
Given: a session with no ExerciseEntries
When: saveSession() is called
Then: an error is thrown
And: nothing is persisted
```

### TC-MP7: Reject a set with missing required measurement fields

```
Given: a Free Squat set with weight populated but reps nil
When: saveSession() is called
Then: an error is thrown
And: nothing is persisted
```

### TC-MP8: Update a session -- does not re-evaluate PBs

```
Given: a saved session with a PB at 80kg x 5
When: the session notes are updated via updateSession()
Then: the PB record is unchanged
And: the session notes are updated
```

---

## Manual PB Entry Tests

### TC-MP9: Record a manual PB with no existing PB

```
Given: no existing PB for Free Squat for the test member
When: recordManualPB() is called with exerciseId: freeSquat, weight: 80.0, reps: 5
Then: ManualPBResult.isNewPB is true
And: ManualPBResult.personalBest is not nil
And: the PersonalBest has entryType: manualEntry
And: the PersonalBest has setId: nil
And: the PersonalBest has isCurrent: true
And: achievedAt is today's date
```

### TC-MP10: Record a manual PB that beats existing PB

```
Given: existing PB for Free Squat at 80kg x 5 (isCurrent: true)
When: recordManualPB() is called with weight: 85.0, reps: 5
Then: ManualPBResult.isNewPB is true
And: the new PersonalBest has isCurrent: true
And: the previous PersonalBest has isCurrent: false
```

### TC-MP11: Record a manual PB that does not beat existing PB

```
Given: existing PB for Free Squat at 80kg x 5
When: recordManualPB() is called with weight: 75.0, reps: 5
Then: ManualPBResult.isNewPB is false
And: ManualPBResult.personalBest is nil
And: the existing PB is unchanged
```

### TC-MP12: Reject manual PB with missing required fields

```
Given: Free Squat requires weightAndReps measurement
When: recordManualPB() is called with weight populated but reps nil
Then: an error is thrown
```

### TC-MP13: Manual PB and session-derived PB coexist in history

```
Given: a manual PB for Free Squat at 80kg x 5
When: a session is saved with Free Squat at 85kg x 5
Then: fetchAllPBs returns two records
And: the manual entry has entryType: manualEntry
And: the session-derived entry has entryType: sessionDerived
And: the session-derived entry has isCurrent: true
```

---

## Progression View Tests

### TC-MP14: currentPBs returns only pbExercise exercises

```
Given: PBs for both a pbExercise and a conditioning exercise
Then: currentPBs() returns only the pbExercise PB
```

### TC-MP15: currentPBs returns one record per exercise

```
Given: two PB records for Free Squat -- one historical, one current
When: currentPBs() is called
Then: only the record with isCurrent: true is returned for Free Squat
```

### TC-MP16: currentPBs returns results ordered by exercise displayOrder

```
Given: current PBs for Overhead Press (displayOrder 1) and Free Squat (displayOrder 2)
When: currentPBs() is called
Then: Overhead Press appears before Free Squat
```

### TC-MP17: pbProgression returns history within the date window

```
Given: three PBs for Free Squat at dates: 8 months ago, 5 months ago, 1 month ago
When: pbProgression() is called with from: 6 months ago
Then: only the two PBs within the window are returned (5 months ago, 1 month ago)
And: results are ordered by achievedAt ascending
```

### TC-MP18: pbProgression returns empty when no PBs in window

```
Given: one PB for Free Squat at 8 months ago
When: pbProgression() is called with from: 6 months ago
Then: an empty array is returned
```

### TC-MP19: sessionConsistency returns weekly counts including zero weeks

```
Given: sessions on Monday and Wednesday of week 1, none in week 2, one on Tuesday of week 3
When: sessionConsistency() is called covering those 3 weeks
Then: three WeeklySessionCount records are returned
And: week 1 has count 2
And: week 2 has count 0
And: week 3 has count 1
```

### TC-MP20: sessionConsistency weeks always start on Monday

```
Given: any date range
When: sessionConsistency() is called
Then: every WeeklySessionCount.weekStarting is a Monday
```

---

## File Location

```
tests/core/MemberPerformanceTests.swift
```
