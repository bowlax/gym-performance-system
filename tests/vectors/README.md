# Shared test vectors

Language-neutral JSON fixtures used by Swift and TypeScript tests
to keep PB behaviour aligned across implementations.

## Files

| File | Purpose | Status |
|------|---------|--------|
| `pb-evaluation-vectors.json` | Pairwise `isPB` for the PB rule itself | Keep — rule unchanged under #28 |
| `pb-expiry-vectors.json` | Freshness predicate in isolation (#28) | Spec for reshape |
| `pb-derivation-vectors.json` | Current + lifetime PB selection over records (#28) | Spec for reshape |
| `pb-badge-vectors.json` | Historic badges via running maximum (#28) | Spec for reshape |
| `pb-lifetime-visibility-vectors.json` | Progression lifetime element show/hide (#28) | Spec — rule-beats, not id differ |

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

## `#28` reshape vectors

Shared conventions:

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | integer | `1` |
| `issue` | integer | `28` |
| `purpose` | string | Spec summary |
| `openQuestions` | array | Optional unsettled design points |
| `vectors` | array | Cases |

### Staleness object

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | When `false`, records never expire |
| `periods` | integer | N complete calendar periods |
| `unit` | string | `quarters` or `months` |

### Record object (derivation + badges)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable id within the vector |
| `achievedAt` | string \| null | ISO date `YYYY-MM-DD`, or `null` for undated manual |
| `weight` / `reps` / … | number | Measurement fields as for evaluation vectors |
| `entryKind` | string | `session`, `manual`, or `manualUndated` |

### `pb-expiry-vectors.json`

Freshness only. `Fresh = evaluatedAt < expectedExpiryAt`. Expiry day itself is stale.

| Field | Type | Description |
|-------|------|-------------|
| `achievedAt` | string | ISO date |
| `staleness` | object | See above |
| `evaluatedAt` | string | ISO date |
| `expectedExpiryAt` | string \| null | Expiry date, or `null` when staleness disabled |
| `expectedFresh` | boolean | Freshness at `evaluatedAt` |
| `compareAchievedAt` | string | Optional second date for edge-asymmetry pairs |
| `expectedCompareExpiryAt` / `expectedCompareFresh` | | Paired expectations for asymmetry vectors |

### `pb-derivation-vectors.json`

| Field | Type | Description |
|-------|------|-------------|
| `rule` / `exerciseName` / `targetReps` / `minimumReps` | | Same meaning as evaluation vectors |
| `staleness` | object | |
| `resetAt` | string \| null | ISO date; **current only** — requires `achievedAt > resetAt` |
| `evaluatedAt` | string | ISO date |
| `records` | array | Candidate records |
| `expectedCurrentId` | string \| null | Best post-reset fresh record. On ties under the PB rule, **the most recent `achievedAt` wins** for current PB |
| `expectedLifetimeId` | string \| null | Best record overall (ignores reset + freshness) |

### `pb-badge-vectors.json`

| Field | Type | Description |
|-------|------|-------------|
| `rule` / `exerciseName` / … | | Ranking rule for “beats” |
| `records` | array | Dated (+ optional undated) records |
| `expectedBadgedIds` | string[] | Ids that were a lifetime best when achieved |

No `resetAt` — badges are lifetime milestones over all dated records. Order is by `achievedAt` ascending, not insertion order. Undated records never badge. Equal later records are **not** badged, so the earliest equal record keeps the badge.

### `pb-lifetime-visibility-vectors.json`

| Field | Type | Description |
|-------|------|-------------|
| `rule` | string | PB rule used for comparison |
| `current` / `lifetime` | object \| null | Measurement snapshots (`weight` / `reps` / `time` / `distance`) |
| `expectedShow` | boolean | Whether the progression lifetime element should show |

Show iff lifetime **strictly beats** current under the PB rule (`evaluatePB` / `PBRuleEvaluator`). Ties hide. Not record-id inequality — equal values can have different ids when current and lifetime resolve ties differently.

## Usage

Swift loads evaluation vectors via `PBEvaluationVectors.swift` /
`ExerciseRegistryTests`. TypeScript via
`supabase/functions/_shared/pb-evaluation_test.ts`
(`npm run pb-evaluation:test`).

Expiry / derivation / badge pure logic:
- TypeScript: `supabase/functions/_shared/pb-derivation.ts`
  (`npm run pb-derivation:test`)
- Swift: `src/core/member-performance/PBDerivation.swift`
  (`PBDerivationTests` / `PBDerivationVectors.swift`)

The board / progression read paths now call these derivation rules in product code; the vector suites remain the cross-language contract.
