# Shared test vectors

Language-neutral JSON fixtures used by Swift and (future) TypeScript tests
to keep PB evaluation behaviour aligned across implementations.

## Files

| File | Purpose |
|------|---------|
| `pb-evaluation-vectors.json` | `isPB` scenarios for all PB rules currently covered in Swift tests |
| `pb-cascade-vectors.json` | PB cascade / restorable selection after deletion or reset |

## `pb-evaluation-vectors.json` schema

Top-level object:

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | integer | Schema version (currently `1`) |
| `vectors` | array | PB evaluation test cases |

Each vector object:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable case id (e.g. `TC-E5`) |
| `description` | string | Human-readable intent |
| `rule` | string | PB rule: `heaviestWeight`, `heaviestWeightAtReps`, `bestWeightAndReps`, `fastestTime`, `longestDistance`, `mostReps` |
| `exerciseName` | string | Seed exercise name (Swift resolves from `ExerciseModel.seedData`) |
| `targetReps` | integer \| null | Rule parameter when relevant |
| `minimumReps` | integer \| null | Rule parameter when relevant |
| `currentPB` | set state \| null | Existing PB values, or `null` if none |
| `newSet` | set state | Set being evaluated |
| `expectedResult` | string | `isPB` or `notPB` |

Set state object (all fields optional; omit unused measurements):

| Field | Type | Description |
|-------|------|-------------|
| `weight` | number | Weight in kg |
| `reps` | integer | Rep count |
| `time` | number | Time in seconds |
| `distance` | number | Distance (metres) |

## `pb-cascade-vectors.json` schema

Top-level object:

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | integer | Schema version (currently `1`) |
| `vectors` | array | PB cascade selection test cases |

Each vector object:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable case id (e.g. `TC-C1`) |
| `description` | string | Human-readable intent |
| `rule` | string | PB rule driving ranking |
| `exerciseName` | string | Seed exercise name (Swift resolves from `ExerciseModel.seedData`) |
| `targetReps` | integer \| null | Rule parameter when relevant |
| `minimumReps` | integer \| null | Rule parameter when relevant |
| `records` | array | Remaining PB records to rank |
| `excludingIds` | string[] \| null | Record ids to omit (simulates deletion) |
| `excludingSetIds` | string[] \| null | Set ids whose linked PB rows are omitted |
| `expectedCurrentId` | string \| null | Record id that should become current, or `null` if none |

Record object:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable record id within the vector |
| `weight` | number | Weight in kg |
| `reps` | integer | Rep count |
| `time` | number | Time in seconds |
| `distance` | number | Distance in metres |
| `achievedAt` | string | ISO date `YYYY-MM-DD` (documents intent; ranking uses value fields only) |
| `wasReset` | boolean | When `true`, record is excluded from cascade candidates |
| `setId` | string | Optional linked set id for `excludingSetIds` scenarios |

Cascade semantics: among non-reset records not excluded by id or set id, the
best value per the exercise PB rule becomes current — not the most recent by date.

## Usage

Swift loads vectors from disk via `PBEvaluationVectors.swift` and runs them
in `ExerciseRegistryTests`. TypeScript loads the same file in
`supabase/functions/_shared/pb-evaluation_test.ts` (run via
`npm run pb-evaluation:test`).

Swift loads cascade vectors via `PBCascadeVectors.swift` and runs them in
`PersonalBestRankingTests`. TypeScript loads the same file in
`supabase/functions/_shared/pb-cascade_test.ts` (run via
`npm run pb-cascade:test`).
