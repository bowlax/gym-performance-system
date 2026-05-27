# Cursor Instructions -- Member Performance Implementation

**Activities:** MP3, MP4  
**Prerequisites:**
- Exercise Registry complete and 48 tests passing (E3, E4)
- docs/cursor-specs/MP1-MP2-member-performance-spec.md in repo
- docs/cursor-specs/MP4-member-performance-tests.md in repo

---

## Before You Start

Confirm the following are in place:
- All 48 tests passing (data layer + exercise registry)
- E2 schema updates applied (weightAndTime, bestWeightAndReps, minimumReps)

---

## Step 1 -- Apply schema updates for PersonalBest

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 1 -- PersonalBest Schema Updates:**

```
Apply the following schema updates before building the Member Performance component.

1. In src/resources/local-store/Models/Enums.swift, add the PBEntryType enum:

enum PBEntryType: String, Codable {
    case sessionDerived   // PB detected automatically from a logged set
    case manualEntry      // PB entered directly by the member
}

2. In src/resources/local-store/Models/PersonalBestModel.swift:
   - Change setId from non-optional UUID to optional UUID?
   - Add var entryType: PBEntryType
   - Update the initialiser: setId: UUID? = nil, entryType: PBEntryType = .sessionDerived

3. In src/data/performance-data-access/PerformanceDataAccess.swift and 
   SwiftDataPerformanceDataAccess.swift, update any references to setId to handle 
   the optional type correctly.

After making changes, run the full test suite to confirm all 48 tests still pass.
```

---

## Step 2 -- Build Member Performance

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 2 -- Member Performance Implementation:**

```
Using the specification in docs/cursor-specs/MP1-MP2-member-performance-spec.md, 
implement the Member Performance component.

Create three files in src/core/member-performance/:

1. MemberPerformance.swift -- the protocol
2. MemberPerformanceTypes.swift -- SessionResult, ManualPBResult, WeeklySessionCount
3. DefaultMemberPerformance.swift -- the concrete implementation

The DefaultMemberPerformance implementation:
- Accepts ExerciseRegistry and PerformanceDataAccess in its initialiser
- Implements all protocol functions exactly as specified
- Follows all implementation rules in the spec precisely

Key implementation details to follow carefully:

SESSION RECORDING:
- Validate session has at least one ExerciseEntry before saving anything
- Validate each set has correct fields for its exercise's MeasurementType
- Save Session, ExerciseEntries, and Sets via PerformanceDataAccess
- For each set, call ExerciseRegistry.isPB(set:exercise:currentPB:)
- If isPB returns true: markPBAsSuperseded on existing current PB, save new PersonalBest 
  with entryType: .sessionDerived
- Return SessionResult with all new PBs

MANUAL PB ENTRY:
- Validate exercise exists and is active
- Validate correct measurement fields for the exercise's MeasurementType
- Fetch current PB and call ExerciseRegistry.isPB()
- If not a new PB: return ManualPBResult(isNewPB: false, personalBest: nil)
- If new PB: markPBAsSuperseded if needed, save PersonalBest with entryType: .manualEntry,
  setId: nil, achievedAt: Date()
- Return ManualPBResult(isNewPB: true, personalBest: newPB)

SESSION CONSISTENCY:
- Generate one WeeklySessionCount per week from the start of the window to today
- Weeks with zero sessions must be included -- never omitted
- Week start is always Monday
- Count sessions whose date falls within each week

Reference docs/data-schema.md for all model definitions.
Reference docs/cursor-specs/MP1-MP2-member-performance-spec.md for full rules.
```

---

## Step 3 -- Implement Member Performance tests

Open a new Cursor chat and paste this prompt:

---

**Cursor Prompt 3 -- Member Performance Tests:**

```
Using the test specification in docs/cursor-specs/MP4-member-performance-tests.md,
implement the Member Performance test suite.

Create one file: tests/core/MemberPerformanceTests.swift

Requirements:
- Use Swift Testing or XCTest
- All tests use an in-memory ModelContainer (reuse TestHelpers.swift)
- Each test initialises its own fresh DefaultMemberPerformance instance
- Use seeded exercise data from ExerciseModel.seedData
- Use fixed test member UUID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
- Implement all 20 test cases from the spec exactly

For tests involving date windows (TC-MP17, TC-MP18, TC-MP19, TC-MP20):
- Use Calendar.current to calculate dates relative to today
- For sessionConsistency tests, use a fixed reference week to avoid flaky tests

Reference docs/cursor-specs/MP1-MP2-member-performance-spec.md for implementation 
behaviour and docs/cursor-specs/MP4-member-performance-tests.md for test cases.
```

---

## Step 4 -- Run the full test suite

```bash
xcodebuild test \
  -scheme GymPerformance \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID'
```

Target: **68 tests passing** (28 data layer + 20 exercise registry + 20 member performance)

---

## Step 5 -- Commit

```bash
git add .
git commit -m "Member Performance complete -- MP3, MP4 done. 68 tests passing."
git push
```

---

## Step 6 -- Update the project document

Ask Claude Code to update docs/gym-performance-system-project.md:

```
Update docs/gym-performance-system-project.md:

1. Mark activities MP1, MP2, MP3, MP4 as complete (✅)
2. Add a session log entry:
   - Activities completed: MP1, MP2, MP3, MP4
   - Decisions made: PersonalBest.setId made optional to support manual PB entry. 
     PBEntryType enum added (sessionDerived, manualEntry). Manual PB backdating 
     deferred to phase 2. Progression default window is 6 months, passed as parameter.
   - Next up: MS1 -- Define screen flows and interactions
3. Update Next Session to point to MS1, noting this is a Claude activity before 
   Lovable is used for MS2-MS4.

Commit with message: "Session log updated -- core business logic complete, 68 tests passing"
```

---

## What Comes Next

Once MP4 is complete and committed, return to Claude. The next activity is MS1 -- defining the screen flows and interactions for phase 1. This is a design activity that stays in Claude before Lovable builds the actual screens.
