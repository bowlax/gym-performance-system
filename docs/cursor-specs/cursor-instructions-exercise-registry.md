# Cursor Instructions -- Exercise Registry Implementation

**Activities:** E3, E4  
**Prerequisites:** 
- Data layer complete and tests passing (C2, C3, P2, P3)
- Schema updates from E2 applied (weightAndTime, bestWeightAndReps, minimumReps)
- docs/cursor-specs/E2-exercise-seed-data.md in repo

---

## Before You Start

Confirm the following are already in place:

- SwiftData models updated with `weightAndTime` in MeasurementType enum
- SwiftData models updated with `bestWeightAndReps` in PBRule enum
- ExerciseModel updated with `minimumReps: Int?` field
- Data layer tests passing (C3, P3)

If the schema updates from E2 have not yet been applied to the SwiftData model files, do that first before running these prompts.

---

## Step 1 -- Apply schema updates

If not already done, open a Cursor chat and paste this prompt:

---

**Cursor Prompt 1 -- Apply E2 Schema Updates:**

```
Apply the following schema updates to the existing SwiftData model files in src/resources/local-store/Models/:

1. In Enums.swift, update MeasurementType to add weightAndTime:
   case weightAndTime   // e.g. Plank: 20kg held for 45 seconds

2. In Enums.swift, update PBRule to add bestWeightAndReps:
   case bestWeightAndReps  // moving weight floor with minimum rep threshold

3. In ExerciseModel.swift, add minimumReps field:
   var minimumReps: Int?   // used when pbRule is bestWeightAndReps

4. Update ExerciseModel's initialiser to include minimumReps with a default of nil.

Reference docs/cursor-specs/E2-exercise-seed-data.md for the full rule definitions.
Reference docs/data-schema.md for the complete updated schema.

After making changes, confirm no existing tests are broken by running the test suite.
```

---

## Step 2 -- Create the exercise seed data file

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 2 -- Exercise Seed Data:**

```
Using the seed data specification in docs/cursor-specs/E2-exercise-seed-data.md, create the exercise seed data file.

Create one file:
  src/resources/local-store/ExerciseSeedData.swift

This file should contain a static extension on ExerciseModel providing a seedData array of all 19 exercises exactly as specified. Use the fixed UUIDs provided in the spec -- these must not be changed as they are stable identifiers that will survive migration to phase 2.

Important notes:
- Push-ups: bodyweight is recorded as 0kg
- Cable Row: weight is a unitless integer representing stack position, not kg. This is a display and data entry concern -- the model stores it as a Double like any other weight field
- Box Squat, Bench Press 1x5, and Trap Bar Deadlift have parentExerciseId values pointing to their parent exercises -- use the UUIDs provided exactly

Reference docs/data-schema.md for model field definitions.
```

---

## Step 3 -- Build the Exercise Registry

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 3 -- Exercise Registry:**

```
Build the Exercise Registry component for the Gym Performance app.

Create two files in src/core/exercise-registry/:

1. ExerciseRegistry.swift -- the protocol
2. DefaultExerciseRegistry.swift -- the concrete implementation

The ExerciseRegistry protocol:

```swift
protocol ExerciseRegistry {

    // Returns all active exercises ordered by displayOrder
    func allExercises() throws -> [ExerciseModel]

    // Returns all PB exercises (category == .pbExercise) ordered by displayOrder
    func pbExercises() throws -> [ExerciseModel]

    // Returns a single exercise by id
    func exercise(id: UUID) throws -> ExerciseModel?

    // Evaluates whether a new set constitutes a PB for a given exercise
    // Returns true if the set is a new PB, false otherwise
    func isPB(set: ModelSet, exercise: ExerciseModel, currentPB: PersonalBestModel?) -> Bool

    // Seeds exercises on first launch if none exist
    func seedIfNeeded() throws

}
```

The DefaultExerciseRegistry implementation:
- Accepts a ConfigurationDataAccess instance in its initialiser
- Delegates all data operations to ConfigurationDataAccess
- Implements isPB() using the PBRule logic defined in docs/cursor-specs/E2-exercise-seed-data.md
- seedIfNeeded() checks whether exercises exist via ConfigurationDataAccess.fetchExercises() and calls seedExercises() with ExerciseModel.seedData if the result is empty

isPB() logic by PBRule:

heaviestWeightAtReps:
  - set.reps must equal exercise.targetReps
  - set.weight must exceed currentPB?.weight (or currentPB is nil)

heaviestWeight:
  - set.weight must exceed currentPB?.weight (or currentPB is nil)

bestWeightAndReps:
  - Minimum rep threshold is exercise.minimumReps
  - If currentPB is nil: set is a PB if set.reps >= minimumReps
  - Weight increase PB: set.weight > currentPB.weight AND set.reps >= minimumReps
  - Reps increase PB: set.reps > currentPB.reps AND set.weight >= currentPB.weight AND set.reps >= minimumReps
  - Going below currentPB.weight is never a PB regardless of reps

fastestTime:
  - set.time must be less than currentPB?.time (or currentPB is nil)

longestDistance:
  - set.distance must exceed currentPB?.distance (or currentPB is nil)

mostReps:
  - set.reps must exceed currentPB?.reps (or currentPB is nil)

Reference docs/data-schema.md for all model definitions.
Reference docs/cursor-specs/E2-exercise-seed-data.md for full PB rule definitions and examples.
```

---

## Step 4 -- Implement the Exercise Registry tests

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 4 -- Exercise Registry Tests:**

```
Implement the test suite for the Exercise Registry component.

Create one file: tests/core/ExerciseRegistryTests.swift

Use Swift Testing or XCTest. All tests use an in-memory ModelContainer (reuse TestHelpers.swift from tests/data/).

Test cases to implement:

SEEDING

TC-E1: seedIfNeeded populates store when empty
  Given: empty store
  When: seedIfNeeded() is called
  Then: allExercises() returns 19 exercises

TC-E2: seedIfNeeded does not duplicate when called twice
  Given: already seeded store
  When: seedIfNeeded() is called again
  Then: allExercises() still returns 19 exercises

TC-E3: pbExercises returns only pbExercise category exercises
  Given: seeded store
  When: pbExercises() is called
  Then: all returned exercises have category == .pbExercise

TC-E4: exercises returned in displayOrder
  Given: seeded store
  When: allExercises() is called
  Then: results are ordered by displayOrder ascending

PB EVALUATION -- heaviestWeightAtReps (use Free Squat, targetReps: 5)

TC-E5: first set with correct reps is a PB
  Given: no current PB
  When: set has weight 80.0, reps 5
  Then: isPB returns true

TC-E6: heavier weight at correct reps is a PB
  Given: current PB weight 80.0, reps 5
  When: set has weight 85.0, reps 5
  Then: isPB returns true

TC-E7: same weight at correct reps is not a PB
  Given: current PB weight 80.0, reps 5
  When: set has weight 80.0, reps 5
  Then: isPB returns false

TC-E8: heavier weight at wrong reps is not a PB
  Given: current PB weight 80.0, reps 5
  When: set has weight 85.0, reps 3
  Then: isPB returns false

PB EVALUATION -- bestWeightAndReps (use 45-Degree Dumbbell Press, minimumReps: 5)

TC-E9: first set meeting minimum reps is a PB
  Given: no current PB
  When: set has weight 20.0, reps 5
  Then: isPB returns true

TC-E10: first set below minimum reps is not a PB
  Given: no current PB
  When: set has weight 20.0, reps 4
  Then: isPB returns false

TC-E11: weight increase at minimum reps is a PB
  Given: current PB weight 20.0, reps 8
  When: set has weight 22.0, reps 5
  Then: isPB returns true

TC-E12: reps increase at current best weight is a PB
  Given: current PB weight 20.0, reps 8
  When: set has weight 20.0, reps 10
  Then: isPB returns true

TC-E13: weight below current best is not a PB regardless of reps
  Given: current PB weight 22.0, reps 5
  When: set has weight 20.0, reps 12
  Then: isPB returns false

TC-E14: weight increase but reps below minimum is not a PB
  Given: current PB weight 20.0, reps 8
  When: set has weight 22.0, reps 4
  Then: isPB returns false

PB EVALUATION -- mostReps (use Chin-ups)

TC-E15: more reps is a PB
  Given: current PB reps 10
  When: set has reps 11
  Then: isPB returns true

TC-E16: same reps is not a PB
  Given: current PB reps 10
  When: set has reps 10
  Then: isPB returns false

PB EVALUATION -- fastestTime (use Ski 500m)

TC-E17: lower time is a PB
  Given: current PB time 120.0 seconds
  When: set has time 118.5 seconds
  Then: isPB returns true

TC-E18: higher time is not a PB
  Given: current PB time 120.0 seconds
  When: set has time 122.0 seconds
  Then: isPB returns false

PB EVALUATION -- longestDistance (use Bike)

TC-E19: longer distance is a PB
  Given: current PB distance 400.0 metres
  When: set has distance 420.0 metres
  Then: isPB returns true

TC-E20: shorter distance is not a PB
  Given: current PB distance 400.0 metres
  When: set has distance 390.0 metres
  Then: isPB returns false
```

---

## Step 5 -- Run the tests

```bash
xcodebuild test \
  -scheme GymPerformance \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

All 20 Exercise Registry tests plus all 28 data layer tests should pass -- 48 total.

---

## Step 6 -- Commit

```bash
git add .
git commit -m "Exercise Registry complete -- E3, E4 done. 48 tests passing."
git push
```

---

## Step 7 -- Update the project document

Ask Claude Code to update docs/gym-performance-system-project.md:

```
Update docs/gym-performance-system-project.md:

1. Mark activities E1, E2, E3, E4 as complete (✅)
2. Add a session log entry:
   - Activities completed: E1, E2, E3, E4
   - Decisions made: Conditioning exercises deferred to phase 2. 
     bestWeightAndReps PB rule defined with per-exercise minimum rep threshold. 
     weightAndTime measurement type added for plank. 
     Plank PB rule (heaviestWeight) flagged for coach confirmation.
   - Next up: MP1 -- Define session recording and PB evaluation rules
3. Update Next Session to point to MP1.

Then commit with message: "Session log updated -- exercise and PB logic complete"
```

---

## What Comes Next

Once E4 is complete and committed, return to Claude. The next activity is MP1 -- defining the session recording and PB evaluation rules for the Member Performance component. This is the most complex business logic component in phase 1 and stays in Claude before moving to Cursor for MP3.
