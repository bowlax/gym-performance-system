# MS1 -- Screen Flow Specification

**Activity:** MS1  
**Layer:** Client -- iOS Member Surface  
**Phase:** 1 -- Active  
**Tooling:** Lovable (screens), Cursor (logic connections)  
**Status:** Defined -- ready for implementation (MS2-MS4)  
**Last updated:** May 2026

---

## Design Principles

- **Speed above all** -- members log after training, possibly tired. Every interaction must be minimal
- **Board first** -- the digital PB board is the heart of the app and the default view
- **No dead ends** -- every screen has a clear next action
- **Phase 1 is view-only for history** -- editing is deferred to phase 2
- **Two tabs only** -- Board and Log Session. Progression is always accessed with exercise context from the Board

---

## Navigation Structure

```
Tab Bar
├── Board (default tab)
│   └── Tap exercise with PB → Progression screen
│       └── "Add PB manually" → Manual PB Entry (sheet)
│   └── Tap "No PB yet" → Manual PB Entry (sheet)
└── Log Session
    ├── Session header → Exercise selection → Set entry → Save → PB celebration
    └── "History" button → Session History → Session Detail (view only)

First Launch Only:
└── Onboarding → Welcome → Set Opening PBs → Board
```

---

## Screens

---

### Screen 1 -- Board (Home Tab, Default)

**Purpose:** The digital equivalent of the gym PB board. First thing a member sees on launch.

**Layout:**
- Title: "Personal Bests"
- List of all active PB exercises, ordered by displayOrder
- Each row shows:
  - Exercise name
  - Current PB value(s) -- formatted for the exercise's MeasurementType:
    - weightAndReps: "100kg × 5"
    - weightAndTime: "20kg × 1:45"
    - timeOnly: "1:52"
    - distanceOnly: "420m"
    - repsOnly: "15 reps"
    - weightAndDistance: "40kg × 20m"
  - Date achieved -- e.g. "12 Mar"
- Exercises with no PB show: exercise name + "No PB yet" in muted text

**Interactions:**
- Tap exercise row with PB → Progression screen for that exercise
- Tap exercise row with no PB → Manual PB Entry sheet for that exercise

**Data source:** MemberPerformance.currentPBs(memberId:)

---

### Screen 2 -- Progression

**Purpose:** Full exercise history -- all logged sets with PBs highlighted, plus consistency.

**Accessed from:** Tapping any exercise row on the Board.

**Layout:**
- Title: exercise name
- Current PB value prominently displayed at top -- large, clear
- **Chart -- Exercise History**
  - Line chart, last 6 months
  - One data point per session where this exercise was logged
  - Data point = best set from that session
  - PB achievements highlighted with a distinct marker or colour
  - Non-PB sessions shown as regular points on the same line
  - Y axis: primary measurement value (weight for weightAndReps/weightAndTime/weightAndDistance, time for timeOnly, distance for distanceOnly, reps for repsOnly)
  - X axis: date
  - If no data in window: empty state message -- "No sessions logged in the last 6 months"
- **History list** below chart
  - All sessions where this exercise was logged, most recent first
  - Each row: date, value(s), PB badge where applicable
- **Consistency section** below history
  - Title: "Sessions"
  - Weekly bar chart, last 6 months
  - Every week shown -- zero weeks appear as empty bars, gaps are visible
  - Y axis: session count
  - X axis: week

**Actions:**
- Back → Board
- "Add PB manually" button → Manual PB Entry sheet for this exercise

**Data sources:**
- MemberPerformance.currentPBs(memberId:) -- for current PB display
- MemberPerformance.exerciseHistory(memberId:exerciseId:from:) -- for chart and history list
- MemberPerformance.sessionConsistency(memberId:from:) -- for consistency chart

---

### Screen 3 -- Log Session

**Purpose:** Record a completed training session quickly after training.

**Layout:**
- Title: "Log Session"
- "History" button top right → Session History
- Session header fields:
  - Date -- today's date, displayed but not editable in phase 1
  - Notes -- optional free text field
  - Calories -- optional integer field with "kcal" label
- Exercise cards section -- initially empty
- "Add Exercise" button
- "Save Session" button -- disabled until at least one exercise with one set is added

**Logging flow:**

**Step 1 -- Add Exercise**
- Tapping "Add Exercise" presents a sheet with the full list of active PB exercises
- Ordered by displayOrder
- Member taps one or more exercises to select them
- Selected exercises are highlighted
- "Add X exercises" confirm button at bottom
- Confirmed exercises appear as cards on the Log Session screen

**Step 2 -- Enter sets per exercise**
- Each exercise appears as a card with the exercise name as the card title
- Input fields matching the MeasurementType:
  - weightAndReps: weight (kg) field + reps field
  - weightAndTime: weight (kg) field + time field (mm:ss format)
  - timeOnly: time field (mm:ss format)
  - distanceOnly: distance field (metres)
  - repsOnly: reps field
  - weightAndDistance: weight (kg) field + distance field (metres)
- "Add set" link below the first set row -- adds a second row of inputs
- Maximum 3 sets per exercise
- "Remove exercise" option on each card -- removes the card entirely

**Step 3 -- Save**
- "Save Session" validates all inputs
- Missing required fields show inline validation messages
- On successful save: Member Performance evaluates PBs
- **If new PBs achieved:** celebration sheet slides up
  - Title: "New Personal Bests! 🎉"
  - List of each new PB: exercise name + new value
  - "Done" button dismisses sheet and switches to Board tab
- **If no new PBs:** switches to Board tab silently

**Data sources:**
- ExerciseRegistry.pbExercises() -- for exercise selection list
- MemberPerformance.saveSession() -- on save

---

### Screen 4 -- Session History (View Only)

**Purpose:** Let members review past sessions.

**Accessed from:** "History" button on Log Session tab.

**Layout:**
- Title: "Session History"
- Chronological list of past sessions, most recent first
- Each row shows:
  - Date
  - Exercises logged (comma-separated names)
  - PB indicator -- subtle badge if any PBs were achieved that session

**Tapping a session row → Session Detail view:**
- Title: date of session
- Notes and calories if present
- List of exercises logged, each showing:
  - Exercise name
  - Each set logged: value(s)
  - PB badge on sets that achieved a PB
- No edit controls in phase 1 -- view only

**Data sources:**
- MemberPerformance.fetchSessions(memberId:) -- session list
- PerformanceDataAccess.fetchExerciseEntries(sessionId:) -- session detail
- PerformanceDataAccess.fetchSets(exerciseEntryId:) -- set detail

---

### Manual PB Entry (Modal Sheet)

**Purpose:** Record a standalone PB without logging a full session.

**Presented as:** Modal sheet -- lightweight, not a full screen navigation.

**Layout:**
- Title: exercise name (pre-selected from context)
- Input fields matching the exercise's MeasurementType -- same as session set entry
- "Save PB" button

**On save:**
- **If new PB:** brief inline confirmation -- "New PB saved ✓" -- sheet dismisses, Board updates
- **If not a new PB:** message shown on sheet -- "This doesn't beat your current PB of [value]. Not saved." Member can correct values or dismiss

**Data source:** MemberPerformance.recordManualPB()

---

### Onboarding (First Launch Only)

**Purpose:** Set opening PBs before using the app for the first time.

**Triggered:** On first launch, detected by checking whether UserIdentity exists in the store.

**Flow:**

**Screen A -- Welcome**
- App name and brief description
- "Get started" button

**Screen B -- Set Your PBs**
- Title: "What are your current PBs?"
- Subtitle: "Add what you know. You can always update these later."
- List of all PB exercises
- Each row has input fields matching the exercise's MeasurementType
- All fields optional -- member skips exercises they don't have a PB for
- "Done" button at bottom

**On completing onboarding:**
- Each entered PB is saved via MemberPerformance.recordManualPB()
- UserIdentity is created and persisted
- Member lands on the Board

---

## Value Formatting Rules

Consistent formatting across all screens:

| MeasurementType | Format | Example |
|---|---|---|
| weightAndReps | "[weight]kg × [reps]" | "100kg × 5" |
| weightAndTime | "[weight]kg × [mm:ss]" | "20kg × 1:45" |
| timeOnly | "[mm:ss]" | "1:52" |
| distanceOnly | "[distance]m" | "420m" |
| repsOnly | "[reps] reps" | "15 reps" |
| weightAndDistance | "[weight]kg × [distance]m" | "40kg × 20m" |

**Cable Row note:** weight is a unitless integer (stack position). Display without "kg" suffix -- e.g. "12 × 8" where 12 is the stack number and 8 is reps.

---

## Empty States

| Screen | Condition | Message |
|---|---|---|
| Board | No PBs at all (post-onboarding) | "Tap any exercise to log your first PB" |
| Board row | No PB for this exercise | "No PB yet" |
| Progression chart | No sessions in last 6 months | "No sessions logged in the last 6 months" |
| Session History | No sessions logged yet | "No sessions logged yet -- start by logging your first session" |

---

## Phase 2 Deferred

The following are intentionally absent from phase 1:

- Session date editing -- date is always today
- Session and set editing -- view only in history
- Progression time window selection -- fixed at 6 months
- Push notifications
- Coach commentary display
- Goal tracking
