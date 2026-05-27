# Cursor Instructions -- Data Layer Implementation

**Activities:** C2, C3, P2, P3  
**Prerequisites:** Repository cloned locally, spec files added to docs/

---

## Before You Start

Make sure the following files are in your repo under `docs/`:

- `gym-performance-system-design.md`
- `gym-performance-system-project.md`
- `data-schema.md`
- `cursor-specs/swiftdata-models.md`
- `cursor-specs/C1-configuration-data-access-interface.md`
- `cursor-specs/P1-performance-data-access-interface.md`
- `cursor-specs/C3-P3-data-layer-tests.md`

---

## Step 1 -- Open the project in Cursor

Open the `gym-performance-system` folder in Cursor. You should see the full folder structure in the sidebar.

---

## Step 2 -- Set up the Xcode project

Before Cursor can generate Swift files, there needs to be an Xcode project for it to work within.

Open a new chat in Cursor and paste this prompt:

---

**Cursor Prompt 1 -- Xcode Project Setup:**

```
I am building an iOS app called GymPerformance using SwiftUI and SwiftData on iOS 17+.

Please create a new Xcode project structure within this repository. The project should:

1. Be named GymPerformance
2. Target iOS 17+
3. Use SwiftUI for the interface
4. Use SwiftData for persistence
5. Be placed at the root of this repository alongside the existing src/, docs/, and tests/ folders

After creating the project, set up the ModelContainer using the specification in docs/cursor-specs/swiftdata-models.md. Register all six model classes in the container.

Place the app entry point at GymPerformance/GymPerformanceApp.swift.

Do not create any views yet -- just the project structure and model container setup.
```

---

## Step 3 -- Create the SwiftData model classes

Open a new chat in Cursor and paste this prompt:

---

**Cursor Prompt 2 -- SwiftData Models:**

```
Using the specification in docs/cursor-specs/swiftdata-models.md, create the SwiftData model classes for the Gym Performance app.

Create one file per model class, placed in src/resources/local-store/Models/:

- UserIdentityModel.swift
- ExerciseModel.swift
- SessionModel.swift
- ExerciseEntryModel.swift
- ModelSet.swift  (note: named ModelSet to avoid collision with Swift's Set type)
- PersonalBestModel.swift
- Enums.swift  (all enums: Role, ExerciseCategory, MeasurementType, PBRule)

Each model must:
- Be a SwiftData @Model class
- Use UUID primary keys with @Attribute(.unique)
- Match the field definitions exactly as specified
- Include a complete initialiser with sensible defaults for optional fields

Also create src/resources/local-store/ModelContainer+Setup.swift with the ModelContainer configuration registering all six model classes.

Reference docs/data-schema.md for the full schema rules and constraints.
```

---

## Step 4 -- Implement Configuration Data Access

Open a new chat in Cursor and paste this prompt:

---

**Cursor Prompt 3 -- Configuration Data Access:**

```
Using the specification in docs/cursor-specs/C1-configuration-data-access-interface.md, implement the Configuration Data Access component.

Create two files in src/data/configuration-data-access/:

1. ConfigurationDataAccess.swift -- the protocol definition
2. SwiftDataConfigurationDataAccess.swift -- the concrete SwiftData implementation

The implementation must:
- Accept a SwiftData ModelContext in its initialiser
- Use ModelContext for all persistence operations
- Implement all four protocol functions: fetchExercises(), fetchExercise(id:), fetchExercises(category:), seedExercises()
- fetchExercises() returns only active exercises (isActive == true), ordered by displayOrder ascending
- seedExercises() should check whether exercises already exist before inserting to prevent duplication
- All functions throw on error

Reference docs/data-schema.md for the ExerciseModel definition and docs/cursor-specs/swiftdata-models.md for the model class implementation.
```

---

## Step 5 -- Implement Performance Data Access

Open a new chat in Cursor and paste this prompt:

---

**Cursor Prompt 4 -- Performance Data Access:**

```
Using the specification in docs/cursor-specs/P1-performance-data-access-interface.md, implement the Performance Data Access component.

Create two files in src/data/performance-data-access/:

1. PerformanceDataAccess.swift -- the protocol definition
2. SwiftDataPerformanceDataAccess.swift -- the concrete SwiftData implementation

The implementation must:
- Accept a SwiftData ModelContext in its initialiser
- Use ModelContext for all persistence operations
- Implement all functions across sessions, exercise entries, sets, and personal bests
- Never implement delete functions for any entity -- records are only edited, never deleted
- markPBAsSuperseded(id:) sets isCurrent to false on the specified PersonalBest record only
- fetchCurrentPBs(memberId:) returns only PersonalBest records where isCurrent is true
- All functions throw on error

Important: Set is a reserved Swift type. Use ModelSet throughout.

Reference docs/data-schema.md for all model definitions and schema rules.
```

---

## Step 6 -- Implement the tests

Open a new chat in Cursor and paste this prompt:

---

**Cursor Prompt 5 -- Data Layer Tests:**

```
Using the test specifications in docs/cursor-specs/C3-P3-data-layer-tests.md, implement the test suite for the data layer.

Create three files in tests/data/:

1. TestHelpers.swift -- shared in-memory ModelContainer setup used by all tests
2. ConfigurationDataAccessTests.swift -- all TC-C tests
3. PerformanceDataAccessTests.swift -- all TC-P tests

Requirements:
- Use Swift Testing framework (iOS 17+ / Xcode 16+) if available, otherwise XCTest
- All tests must use an in-memory ModelContainer (isStoredInMemoryOnly: true) -- never the live store
- Each test case in the spec becomes one test function
- Test names should match the test case IDs (e.g. testTC_C1_FetchExercisesReturnsEmptyWhenStoreIsEmpty)
- Tests must be independent -- no shared mutable state between tests

Reference docs/cursor-specs/swiftdata-models.md for model class names and initialisers.
```

---

## Step 7 -- Run the tests

In Xcode or via Cursor's terminal:

```bash
xcodebuild test \
  -scheme GymPerformance \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or run tests directly in Xcode with Cmd+U.

All 28 test cases (8 for Configuration, 20 for Performance) should pass before moving on.

---

## Step 8 -- Commit

Once all tests pass, commit everything:

```bash
git add .
git commit -m "Data layer complete -- C2, C3, P2, P3 done. All tests passing."
git push
```

---

## Step 9 -- Update the project document

Ask Claude Code to update `docs/gym-performance-system-project.md`:

```
Update docs/gym-performance-system-project.md:

1. Mark activities C1, C2, C3, P1, P2, P3 as complete (✅)
2. Add a session log entry:
   - Activities completed: C1, C2, C3, P1, P2, P3
   - Decisions made: ModelSet naming convention adopted to avoid Swift Set collision. 
     In-memory container used for all tests.
   - Next up: E1 -- Define exercise list and measurement types
3. Update Next Session to point to E1, noting it requires domain input.

Then commit with message: "Session log updated -- data layer complete"
```

---

## If Cursor Gets Confused

Cursor works best with focused, single-purpose prompts. If a prompt produces unexpected results:

1. Start a new chat -- do not try to fix in the same context
2. Be more specific about the file location and class names
3. Paste the relevant spec section directly into the prompt rather than referencing the file
4. Check that the model class names match exactly -- SwiftData is sensitive to naming

---

## What Comes Next

Once the data layer is complete and committed, return to Claude with both context documents. The next activity is E1 -- defining the exercise list and measurement types for phase 1. This requires your domain knowledge about the exercises at your gym.
