# Test Specifications -- Data Layer

**Activities:** C3, P3  
**Phase:** 1  
**Framework:** Swift Testing (iOS 17+) or XCTest  
**Location:** `tests/data/`  
**Status:** Specified -- ready for implementation

> These test specifications define what must be verified for the data layer to be considered complete. Cursor should implement these as Swift test files. All tests should run against an in-memory SwiftData store -- never against the live on-device store.

---

## Test Setup

All data layer tests use an in-memory ModelContainer:

```swift
let schema = Schema([
    UserIdentityModel.self,
    ExerciseModel.self,
    SessionModel.self,
    ExerciseEntryModel.self,
    ModelSet.self,
    PersonalBestModel.self
])

let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
let container = try ModelContainer(for: schema, configurations: [config])
let context = ModelContext(container)
```

---

## C3 -- Configuration Data Access Tests

**File:** `tests/data/ConfigurationDataAccessTests.swift`

### TC-C1: Fetch exercises returns empty when store is empty

```
Given: an empty store
When: fetchExercises() is called
Then: returns an empty array without throwing
```

### TC-C2: Seed exercises populates the store

```
Given: an empty store
And: a list of valid ExerciseModel objects
When: seedExercises() is called
Then: exercises are persisted to the store
And: fetchExercises() returns the seeded exercises
```

### TC-C3: Fetch exercises returns only active exercises

```
Given: a store containing both active and inactive exercises
When: fetchExercises() is called
Then: only exercises where isActive is true are returned
```

### TC-C4: Fetch exercises returns results ordered by displayOrder

```
Given: exercises seeded with displayOrder values 3, 1, 2
When: fetchExercises() is called
Then: exercises are returned in displayOrder ascending order (1, 2, 3)
```

### TC-C5: Fetch exercise by id returns correct exercise

```
Given: multiple exercises in the store
When: fetchExercise(id:) is called with a known id
Then: the correct exercise is returned
```

### TC-C6: Fetch exercise by id returns nil for unknown id

```
Given: exercises in the store
When: fetchExercise(id:) is called with an unknown id
Then: nil is returned without throwing
```

### TC-C7: Fetch exercises by category returns only matching exercises

```
Given: a mix of pbExercise and conditioning exercises in the store
When: fetchExercises(category: .pbExercise) is called
Then: only pbExercise exercises are returned
When: fetchExercises(category: .conditioning) is called
Then: only conditioning exercises are returned
```

### TC-C8: Seed does not duplicate if called twice

```
Given: exercises already seeded in the store
When: seedExercises() is called again with the same exercises
Then: no duplicate records are created
```

---

## P3 -- Performance Data Access Tests

**File:** `tests/data/PerformanceDataAccessTests.swift`

### Sessions

#### TC-P1: Save and fetch session

```
Given: a valid SessionModel
When: saveSession() is called
Then: the session is persisted
And: fetchSessions(memberId:) returns the session for the correct member
```

#### TC-P2: Fetch sessions returns only sessions for the specified member

```
Given: sessions for two different memberIds
When: fetchSessions(memberId:) is called for one member
Then: only that member's sessions are returned
```

#### TC-P3: Fetch session by id

```
Given: a saved session
When: fetchSession(id:) is called with its id
Then: the correct session is returned
```

#### TC-P4: Fetch session by id returns nil for unknown id

```
Given: sessions in the store
When: fetchSession(id:) is called with an unknown id
Then: nil is returned without throwing
```

#### TC-P5: Update session persists changes

```
Given: a saved session with notes nil
When: the session's notes field is updated and updateSession() is called
Then: fetchSession(id:) returns the session with the updated notes
And: updatedAt is more recent than createdAt
```

#### TC-P6: Sessions cannot be deleted

```
Given: the PerformanceDataAccess protocol
Then: no delete function exists for sessions
```

---

### Exercise Entries

#### TC-P7: Save and fetch exercise entry

```
Given: a saved session and a valid ExerciseEntryModel linked to it
When: saveExerciseEntry() is called
Then: fetchExerciseEntries(sessionId:) returns the entry for the correct session
```

#### TC-P8: Fetch exercise entries returns only entries for the specified session

```
Given: exercise entries for two different sessions
When: fetchExerciseEntries(sessionId:) is called for one session
Then: only that session's entries are returned
```

#### TC-P9: Update exercise entry persists changes

```
Given: a saved exercise entry
When: updateExerciseEntry() is called with a modified entry
Then: the changes are persisted and updatedAt is updated
```

---

### Sets

#### TC-P10: Save and fetch set

```
Given: a saved exercise entry and a valid ModelSet linked to it
When: saveSet() is called
Then: fetchSets(exerciseEntryId:) returns the set for the correct entry
```

#### TC-P11: Multiple sets per exercise entry

```
Given: a saved exercise entry
When: three sets are saved against it
Then: fetchSets(exerciseEntryId:) returns all three sets
```

#### TC-P12: Update set persists changes

```
Given: a saved set with weight 80.0
When: the weight is updated to 85.0 and updateSet() is called
Then: fetchSets(exerciseEntryId:) returns the set with weight 85.0
And: updatedAt is updated
```

#### TC-P13: Sets cannot be deleted

```
Given: the PerformanceDataAccess protocol
Then: no delete function exists for sets
```

---

### Personal Bests

#### TC-P14: Save and fetch current PB

```
Given: a valid PersonalBestModel with isCurrent true
When: savePersonalBest() is called
Then: fetchCurrentPB(memberId:exerciseId:) returns the PB
```

#### TC-P15: Only one current PB per member per exercise

```
Given: an existing current PB for a member and exercise
When: markPBAsSuperseded() is called on the existing PB
And: a new PersonalBestModel with isCurrent true is saved
Then: fetchCurrentPB(memberId:exerciseId:) returns only the new PB
And: fetchAllPBs(memberId:exerciseId:) returns both records
```

#### TC-P16: Fetch all PBs returns full history

```
Given: three PersonalBest records for the same member and exercise
  -- two with isCurrent false, one with isCurrent true
When: fetchAllPBs(memberId:exerciseId:) is called
Then: all three records are returned
```

#### TC-P17: Fetch current PBs returns all current PBs for a member

```
Given: current PBs for a member across three different exercises
When: fetchCurrentPBs(memberId:) is called
Then: all three current PBs are returned
And: no historical PBs are included
```

#### TC-P18: Fetch current PB returns nil when no PB exists

```
Given: no PB records for a member and exercise combination
When: fetchCurrentPB(memberId:exerciseId:) is called
Then: nil is returned without throwing
```

#### TC-P19: markPBAsSuperseded sets isCurrent to false

```
Given: a PersonalBest with isCurrent true
When: markPBAsSuperseded(id:) is called
Then: the record's isCurrent is false
And: fetchCurrentPB() no longer returns it
```

#### TC-P20: Personal bests cannot be deleted

```
Given: the PerformanceDataAccess protocol
Then: no delete function exists for personal bests
```

---

## File Locations

```
tests/data/ConfigurationDataAccessTests.swift
tests/data/PerformanceDataAccessTests.swift
tests/data/TestHelpers.swift    -- shared in-memory container setup
```
