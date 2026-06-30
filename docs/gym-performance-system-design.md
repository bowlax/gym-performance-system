# Gym Performance System -- Project Design Document

**Methodology:** Righting Software (The Method)  
**Status:** Phase 1 complete -- Phase 2 scoping in progress  
**Last updated:** June 2026

---

## 1. Mission Statement

To make the performance and progression of members measurable over time, enabling both individuals to understand their development and gym management to make evidence-based decisions about programme design and organisational direction.

---

## 2. Stakeholders

| Stakeholder | Description |
|---|---|
| **Members** | All gym members who train. Treated equally for now. Veterans group noted but not specialised yet. |
| **Coaches** | Three in total. Operational and member-facing. No member assignment -- all coaches can see all members. Coaches can only see members who have chosen to sync. |
| **Owner** | Single person. Also a coach in practice, but always accesses the system in a management/strategic capacity. Has a superset of all access. |

---

## 3. Use Cases

### Member Use Cases
1. Record a training session and what was done in it
2. Record a personal best against an exercise
3. View their own progression over time
4. View their current personal bests
5. Review progress against a current goal
6. View their consistency over time
7. Log their weight over time
8. Receive system-generated flags based on their data patterns
9. Receive commentary or guidance from a coach
10. Record an injury or difficulty *(free text, member-authored)*
11. Export their data in JSON format
12. Import previously exported data *(phase 2)*
13. Choose whether to sync data to the central store *(phase 2)*

### Coach Use Cases
1. View a member's progression over time
2. View a member's consistency and attendance
3. View a member's current personal bests
4. View a member's progress against their quarterly goals
5. View system-generated flags for a member
6. Add commentary or guidance against a flag or member record
7. Set a quarterly goal for a member *(coach-owned, member is consumer only)*
8. View a member's recorded injuries and difficulties

### Owner Use Cases
1. View patterns across all members -- progression, plateaus, disengagement
2. View a member's weight trend
3. View attendance and consistency trends across the gym
4. View aggregate performance data across all members
5. View system-generated flags across the whole gym
6. Manage member records -- adding and deactivating members
7. Manage coach accounts and access

### System Use Cases
1. Detect patterns in member data and generate flags -- attendance drops, progression plateaus, PB streaks, goal trajectory
2. Deliver flags to relevant coaches and owner
3. Notify a member when coaching commentary is received
4. Evaluate and track member progress against quarterly goals over time
5. Aggregate member data into gym-wide views for the owner
6. Sync member data between local device store and central store *(phase 2)*

---

## 4. Core Use Cases

These are the smallest set that define the essence of the system. Every architectural component must serve at least one of them.

1. **A member's performance is recorded and made meaningful over time**
2. **That meaning is surfaced to the right person at the right time**
3. **Collective performance patterns reveal the effectiveness of the gym's programme**

> **Note:** Core use case 3 cannot be delivered until data is centralised. Phase 1 delivers core use cases 1 and 2 only. Core use case 3 is limited to syncing members in phase 2 -- members who have opted out of sync are invisible to coaches and the owner.

---

## 5. Volatility Register

Each volatility is encapsulated by a specific component. Changes to any of these should require changes only to the component that encapsulates them.

| # | Volatility | Encapsulated By |
|---|---|---|
| 1 | User types and roles | Access Control utility |
| 2 | Client platform | Client layer surfaces and platforms |
| 3 | Data location and sync behaviour | Resource Access layer + Resource layer + Sync Manager utility |
| 4 | Exercise definitions and PB rules | Exercise Registry + Configuration Data Access |
| 5 | Flag and insight rules | Insight Engine |
| 6 | Goal types | Goal Management |
| 7 | Authentication and access control | Access Control utility |
| 8 | Notification and delivery mechanism | Notification Manager + Notification Service Access |
| 9 | Aggregation and reporting | Aggregation Service |
| 10 | Sensitive and personal data -- privacy, access, regulatory handling | Sensitive Data Manager + Sensitive Data Access |
| 11 | Sync behaviour -- when data syncs, conflict resolution, offline handling | Sync Manager utility |

> **Note:** Volatility 3 has been reframed from "data location" to "data location and sync behaviour" to reflect the local-first architecture decision. The device is always the source of truth; the central store is an optional sync target, not a replacement.

---

## 6. Full System Architecture

Dependencies flow downward only. No component may call a component in a layer above it.

---

### Utilities
*Cross-cutting concerns consumed by all layers*

| Component | Responsibility | Status |
|---|---|---|
| **Access Control** | Enforces what each user type can see and do across the entire system | Phase 1 active |
| **Sensitive Data Manager** | Governs privacy rules, consent and regulatory handling of personal and health data | Phase 2 |
| **Notification Manager** | Determines who needs to be notified of what, and when. Decoupled from delivery mechanism | Phase 2 |
| **Sync Manager** | Manages sync state, registration status, conflict resolution rules, and offline behaviour. Knows whether a member has opted in to sync | Phase 2 |

---

### Client Layer
*Encapsulates platform volatility. Each surface connects to the same Business Logic beneath it. Implementation decisions -- one app or many -- are deferred to build time*

**Surfaces:**

| Surface | Description | Status |
|---|---|---|
| **Member Surface** | Logging sessions and PBs, viewing personal progression, receiving guidance | Phase 1 active -- iOS |
| **Coach Surface** | Viewing member data, setting goals, adding commentary, viewing flags | Phase 2 -- web |
| **Owner Surface** | Gym-wide patterns, strategic intelligence, member and coach management | Phase 2 -- web |

**Platforms:**

| Platform | Status |
|---|---|
| **iOS Platform** | Phase 1 active |
| **Web Platform** | Phase 2 |

---

### Business Logic Layer
*The rules, processes and decisions that define how the system behaves. Platform agnostic and storage agnostic*

| Component | Responsibility | Status |
|---|---|---|
| **Member Performance** | Recording and evaluating sessions, PBs and progression over time | Phase 1 active |
| **Exercise Registry** | Exercise definitions, measurement types and PB rules | Phase 1 active |
| **Goal Management** | Creating, tracking and evaluating goals of any type | Phase 2 |
| **Insight Engine** | Detecting patterns in data and generating flags. Consumes AI Model Access when available | Phase 2 |
| **Aggregation Service** | Producing gym-wide views and pattern analysis for the owner | Phase 2 |

---

### Resource Access Layer
*Knows how to talk to storage and services. Knows nothing about what the data means. Changing storage only changes this layer*

| Component | Responsibility | Status |
|---|---|---|
| **Performance Data Access** | Session, PB and progression data | Phase 1 active |
| **Member Profile Access** | Identity, role, attendance and non-sensitive member data | Phase 2 |
| **Sensitive Data Access** | Weight, injuries, health notes -- governed by Sensitive Data Manager | Phase 2 |
| **Goal Data Access** | Goal records and evaluation state | Phase 2 |
| **Configuration Data Access** | Exercise definitions, PB rules, system configuration | Phase 1 active |
| **AI Model Access** | Abstracts analytical capability -- rules-based today, LLM-powered in future | Phase 2 |
| **Notification Service Access** | Passes notifications to the delivery layer, decoupled from mechanism | Phase 2 |
| **Sync Service Access** | Handles data flow between Local Device Store and Central Data Store for syncing members | Phase 2 |

---

### Resource Layer
*Actual storage and infrastructure. The device is always the source of truth in the local-first model*

| Component | Status | Notes |
|---|---|---|
| **Local Device Store** | Phase 1 active | SwiftData, iOS 17+. Always the source of truth for all members |
| **Central Data Store** | Phase 2 | Sync target for members who have opted in. Not a replacement for local store |
| **LLM Service** | Phase 3 | AI analytical capability for Insight Engine |
| **Notification Service** | Phase 2 | Email, push or other delivery infrastructure |

---

## 7. Architecture Validation

All three core use cases were walked through the architecture as call chains. All validated cleanly with no structural gaps.

| Core Use Case | Result |
|---|---|
| A member's performance is recorded and made meaningful over time | ✅ Validated |
| That meaning is surfaced to the right person at the right time | ✅ Validated |
| Collective performance patterns reveal the effectiveness of the gym's programme | ✅ Validated -- requires Central Data Store and member sync opt-in |

---

## 8. Local-First Sync Architecture

**This is a foundational architectural decision made during phase 1 testing.**

The system uses a local-first model. The device is always the source of truth. The central store is an optional sync layer, not a replacement for local storage.

### Principles

- All data is written to the Local Device Store first, always
- The app must function fully offline at all times
- Members choose whether to sync -- sync is on by default but can be opted out
- The registration step is the sync decision -- members either identify themselves or stay anonymous and on-device only
- Non-syncing members are invisible to coaches and the owner
- Syncing members have their data available to coaches and the owner

### Registration and sync flow

```
Install app
  → Complete onboarding (set opening PBs) -- available to all members
  → "Connect your account?" prompt
      → Yes: enter name + email → verify → sync enabled → visible to coaches
      → Skip: stay anonymous → data local only → invisible to coaches
  → Board screen
  → (Can connect later from settings)
```

### Phase 1 to phase 2 migration

Members with existing phase 1 data migrate when phase 2 launches:
- On first launch of phase 2 app, prompted to connect account
- If they connect: local data syncs to central store automatically
- If they skip: nothing changes, data remains local only
- Export/import remains the path for local-only members who change phones

### Multi-gym consideration

When a second gym is onboarded, `gymId` will be added to all entities. The local-first model supports this cleanly -- each installation is associated with one gym. The architecture does not need to change; only the data model gains `gymId`.

---

## 9. Phase Definitions

### Phase 1 -- iOS, On-Device, Members Only ✅ Complete

**Scope:** A member can record their sessions, track their personal bests, and view their progression over time.

**Status:** Complete. TestFlight build live. 18+ installs, 80+ sessions logged.

**Active components:**

| Layer | Components |
|---|---|
| Utilities | Access Control |
| Client | Member Surface on iOS Platform |
| Business Logic | Member Performance, Exercise Registry *(static, bundled)* |
| Resource Access | Performance Data Access, Configuration Data Access |
| Resource | Local Device Store |

**Phase 1 technical decisions:**
- SwiftData for on-device persistence (iOS 17+)
- UUID primary keys throughout -- anticipates phase 2 centralisation
- Bundle ID: `uk.co.wayoflifefitness.gymperformance`
- Developer account: Wolf Way of Life Fitness (UK limited company)
- 76+ tests passing across 4 suites
- Wolf blue (#1A5BA6) primary accent, electric yellow (#FFD600) for PB moments
- White wolf head on black app icon
- Distributed via TestFlight -- App Store release deferred to phase 2 completion

**Phase 1 schema decisions:**
- `PersonalBest.setId` is optional -- supports manual entry path
- `PersonalBest.entryType` enum: `sessionDerived` / `manualEntry`
- `PersonalBest.isCurrent` -- moving flag, only one true per member per exercise
- `PersonalBest.wasReset` -- tracks whether a record was explicitly reset
- `Exercise.pbRule` is optional -- conditioning exercises have no PB rule
- `bestWeightAndReps` PB rule uses moving weight floor -- going below current best weight is never a PB
- PB cascade after deletion restores the best non-reset remaining record per exercise PBRule
- Session deletion cascades to sets and associated PB records
- `ModelSet` naming used instead of Swift's `Set` to avoid type collision
- `#Predicate` does not support captured enum values -- filter in memory after fetch

---

### Phase 2 -- Local-First Sync, Coach and Owner Surfaces

**Scope:** Introduce optional sync to a central data store, registration and authentication for syncing members, coach and owner web surfaces, and expanded member capabilities.

**Key architectural addition:** Sync Manager utility + Sync Service Access + Central Data Store

**Confirmed phase 2 components:**

| Component | Description |
|---|---|
| Central Data Store | Cloud-hosted database. Sync target for opted-in members. Not a replacement for local store |
| Sync Manager | Manages sync state, registration, conflict resolution, offline queuing |
| Sync Service Access | Resource Access component handling data flow between local and central store |
| Member Profile Access | Identity, role, attendance data |
| Sensitive Data Access | Weight, injuries, health notes |
| Goal Data Access | Goal records and evaluation |
| Goal Management | Coach-set quarterly goals, member progress tracking |
| Insight Engine | Pattern detection and flag generation |
| Aggregation Service | Gym-wide views for the owner |
| Notification Manager | Flag and commentary delivery |
| Notification Service Access | Delivery mechanism abstraction |
| Notification Service | Push, email or other delivery infrastructure |
| Coach Surface | Web-based, sees syncing members only |
| Owner Surface | Web-based, full visibility of syncing members |
| Member Web Surface | Browser-based member experience -- covers Android and web users |
| Web Platform | Phase 2 platform addition |

**Phase 2 migration path:**
- Existing phase 1 members prompted to connect account on first phase 2 launch
- Export/import feature covers local-only members changing phones
- `gymId` added to all entities to keep multi-gym option open

---

### Phase 3 -- Intelligence and Integrations

**Scope:** AI-powered insights, HealthKit integration, TeamUp integration.

| Item | Notes |
|---|---|
| LLM Service | Powers Insight Engine pattern detection |
| AI Model Access | Abstracts LLM capability from Insight Engine |
| HealthKit integration | Write gym sessions to Apple Health as HKWorkout. Read to follow |
| TeamUp integration | Review API capabilities during phase 2 scoping. May influence member identity model |

---

## 10. Key Design Decisions

| Decision | Rationale |
|---|---|
| Goals are coach-owned, not member-authored | Reflects current gym practice -- coaches set goals, members work towards them |
| Messaging between members and coaches is out of scope | Coaches and members interact in person. Digital messaging adds complexity without adding value |
| Session programme planning is out of scope | System is an intelligence tool, not a planning tool. Insights inform planning done elsewhere |
| Veterans group not specialised | Treated as members for now. Noted for future consideration |
| Exercise definitions bundled in phase 1 | Quarterly change frequency makes app updates acceptable. Avoids infrastructure cost in proof of concept phase |
| Phase 1 is members only, no coach or owner surface | Centralisation is a prerequisite for cross-member views. Phase 1 validates core individual use case before investing in infrastructure |
| Injury notes are free text | Structured forms would discourage logging. Low friction is more important than structured data at this stage |
| Local-first architecture | App must work offline. Members choose whether to sync. Device is always the source of truth |
| Registration is the sync decision | Members either identify themselves (sync on) or stay anonymous (local only). No separate settings toggle |
| Non-syncing members invisible to coaches | Privacy by design. Coaches and owner only see members who have consented to share data |
| App Store release deferred | Full App Store release deferred until phase 2 complete. TestFlight adequate for known gym community. Phase 2 tells a complete product story |
| Conditioning exercises deferred to phase 2 | Not on the PB board, members not motivated to log them. Relevant for coach session planning in phase 2 |
| PB minimum rep threshold removed | Coach decision. A PB is achieved if a higher weight is lifted regardless of reps. Simplifies bestWeightAndReps rule |
| gymId deferred but anticipated | Not built yet but will be added to all entities in phase 2 to keep multi-gym option open |
| Export phase 1, import phase 2 | Export gives members data portability now. Import is the phase 2 migration path for local-only members |
| Plank PB rule to confirm with coach | Currently heaviestWeight. May change to compound weight+time rule in phase 2 |

---

## 11. Open Questions and Future Considerations

- Veterans group -- may need specialised session types or goal structures in future
- Notification delivery mechanism -- push on iOS, to be determined for web
- LLM integration specifics -- model choice, prompting strategy, cost model
- Data privacy and regulatory requirements -- GDPR compliance for weight and injury data, to be addressed before phase 2
- Authentication mechanism for syncing members -- to be designed for phase 2
- Whether member and coach surfaces are one app or separate -- deferred to phase 2 build time
- TeamUp API capabilities -- review before designing Central Data Store member identity model
- Plank PB rule -- confirm with coach whether heaviestWeight is correct or should be compound weight+time
- Multi-gym -- gymId to be added to all entities in phase 2. Full multi-tenancy infrastructure deferred until a second gym is onboarded
- Conflict resolution strategy for sync -- what happens when data is edited on two devices before sync

---

## 12. GitHub Issues Register

| Issue | Title | Phase | Status |
|---|---|---|---|
| #3 | Reset PBs and delete individual history entries | Phase 1 | In progress |
| #4 | HealthKit integration | Phase 3 | Deferred |
| #5 | Export member data as JSON | Phase 1 | Pending |
| #6 | Import previously exported data | Phase 2 | Deferred |
| #7 | TeamUp integration | Phase 3 | Deferred -- review during phase 2 scoping |

---

*This document is the authoritative design record for the Gym Performance System. All build decisions should trace back to the architecture and use cases captured here. When starting a new session, provide this document as context before proceeding.*

---

## 13. Phase 2 Technology Stack

**Confirmed during phase 2 scoping (June 2026).**

These technology choices slot into the architectural component slots already defined. They do not change the logical architecture -- they realise it.

| Architectural Slot | Technology | Rationale |
|---|---|---|
| Identity / Authentication (Access Control utility) | TeamUp OAuth | Every gym member already has a TeamUp account. No custom authentication, password storage, or registration database needed |
| Central Data Store (Resource) | Supabase (PostgreSQL) | Database, auto-generated API, real-time sync, row-level security, and hosting in one platform |
| Server-side business logic | TypeScript (Supabase Edge Functions) | Same language as web surfaces, strong AI tooling support |
| Coach Surface (Client) | React | Lovable generates natively |
| Owner Surface (Client) | React | Lovable generates natively |
| Member Web Surface (Client) | React | Lovable generates natively. Covers Android and web users |
| iOS Member Surface (Client) | Swift / SwiftData (unchanged) | Preserves local-first, offline-capable operation |

### TeamUp as the identity source

Every gym member already has a TeamUp account. TeamUp becomes the single source of truth for member identity:

- Member identity comes from TeamUp via OAuth -- the TeamUp customer ID is the member's identity in the system
- Coach and owner identity maps to TeamUp's Provider role
- Anonymous/local-only members map to TeamUp's Unregistered Customer concept
- The "Connect your account?" registration step becomes "Connect your TeamUp account"
- The app never handles TeamUp passwords -- OAuth bearer token only
- Attendance data may be available directly from TeamUp, connecting to consistency tracking
- TeamUp's `TeamUp-Provider-ID` header supports multi-location businesses -- effectively becoming gymId for multi-gym scenarios

**Dependency note:** This creates a dependency on TeamUp for identity. A future gym not using TeamUp would need an alternative identity path. Acceptable given current and near-term gyms all use TeamUp.

### Supabase responsibilities

- PostgreSQL database -- the Central Data Store
- Auto-generated REST and real-time APIs
- Row-level security -- enforces the sync privacy model (members see own data, coaches see all synced members, non-syncing members invisible)
- Hosting -- no servers to manage
- Edge Functions -- server-side business logic for web surfaces and owner aggregation

### Business logic in two implementations

The business logic exists in two runtime environments:
- **Swift on device** -- for local-first, offline operation (existing phase 1 implementation)
- **TypeScript server-side** -- for web surfaces and owner aggregation working with synced data

Both are validated against the same specifications and test scenarios documented in this design and the project specs. The specifications are the contract -- not either implementation. This is consistent with The Method: the business logic is conceptually identical, implemented for two runtime environments.

### Local-first preserved

The iOS app retains its Swift business logic and local SwiftData store. The only addition is the sync layer (Sync Manager + Sync Service Access) that pushes and pulls data to Supabase when a member has connected their TeamUp account. The app continues to function fully offline. The local store remains the source of truth on the device.

### Trade-offs accepted

- Vendor dependency on TeamUp (identity) and Supabase (data, sync)
- Business logic exists in two implementations -- mitigated by shared specs and tests
- Supabase costs scale with usage -- generous low tiers, small current scale
- Row-level security rules require careful design to enforce the sync privacy model


---

## 14. Phase 2 Use Case Capture

**Status as of June 2026 scoping session.**

| Surface | Status |
|---|---|
| Registration and Sync | Complete -- 15 use cases |
| Connected Member (Group 1 -- sync-independent of coach) | Complete -- 11 use cases |
| Connected Member (Group 2 -- coach-dependent) | Parked -- needs coach input |
| Coach Surface | Parked -- needs coach input |
| Owner Surface | Parked -- needs owner input |
| Administrator | Partial -- GDPR deletion defined, support tooling deferred to phase 3 |

### Phase 2 Stakeholders

| Stakeholder | Description |
|---|---|
| Anonymous members | iOS only. Local store only, not synced, invisible to coaches |
| Connected members | Synced via TeamUp, visible to coaches |
| Coaches | TeamUp providers. Member-facing operational web surface |
| Owner | TeamUp provider with full strategic access |
| Administrator | Developer/support. Raw Supabase access in phase 2. Dedicated Admin Surface deferred to phase 3. GDPR deletion is a defined requirement |
| TeamUp | External identity and membership system. Source of truth for member identity |
| Sync process | System actor managing local-to-central data flow |

### iOS vs Web Member Distinction

A foundational phase 2 distinction:

**iOS members:**
- Local-first, offline-capable
- Can be anonymous (local-only) or connected (synced)
- Connection is a deliberate choice (the registration step)

**Web members (primarily Android):**
- Connected by definition -- no local store
- Always authenticated via TeamUp
- Inherently connectivity-dependent
- The anonymous/local-only option does not apply -- it is an iOS-only capability

### Registration and Sync Use Cases

**Connection:**
1. A member connects their TeamUp account, enabling sync
2. A member skips connection and remains anonymous/local-only (iOS only)
3. A previously anonymous member connects later from settings
4. A connected member disconnects, reverting to local-only (central data retained by default)
5. A member requests deletion of their central data (GDPR right to erasure)

**Syncing:**
6. A connected member's local data syncs to the central store
7. A connected member's data syncs down to a new device
8. A member logs data offline; the system syncs when connectivity returns
9. Local and central data merge using UUID identity, last-write-wins on conflict (by updatedAt)

**Migration:**
10. An existing phase 1 member connects for the first time; local history merges up to central

**Token management:**
11. A member's TeamUp token expires and is refreshed transparently
12. Token refresh fails; the member is prompted to reconnect

**Sync behaviour:**
13. Sync happens automatically in the background when connectivity allows
14. A member triggers a manual sync via a "sync now" action
15. A member views their sync status (last synced, syncing now, offline, error)

### Connected Member Use Cases -- Group 1

**Data protection and portability (iOS):**
1. A connected iOS member's data is automatically backed up to the central store
2. A connected iOS member restores their data on a new device by connecting
3. A connected iOS member's local and central data stay in sync

**Web access (all members, primarily Android):**
4. A member signs in to the web surface using TeamUp
5. A web member views their current PBs, progression, session history, and consistency
6. A web member logs a training session in the browser
7. A web member records a manual PB in the browser
8. A web member edits or deletes their data in the browser
9. A web member's actions write directly to the central store

**Data control:**
10. A member requests deletion of their central data (GDPR)
11. A connected iOS member disconnects, keeping local data, optionally retaining central data

### First Buildable Slice of Phase 2

Sync infrastructure plus member web access to own data. This delivers real member value (cloud backup, browser access, Android support) without requiring any coach use cases, and proves the entire sync infrastructure end to end -- de-risking everything that follows.

---

## 15. Business Logic Dual-Implementation Strategy

**Full web parity for Android members requires the member business logic to run server-side as well as on iOS.**

Because web members (primarily Android) have no local Swift app, the server must run PB evaluation, progression calculation, and all member business logic for them. This means the business logic exists in two implementations:

- **Swift on device** -- iOS members, offline-capable (existing phase 1 implementation)
- **TypeScript server-side** -- web members, runs in Supabase Edge Functions

### Divergence risk and mitigation

The risk: two implementations of the same rules drifting apart, so an iOS member and a web member could lift the same weight and get different PB results. This would destroy trust.

The mitigation: **shared, language-neutral test vectors.**

- Existing PB evaluation test scenarios are extracted into language-neutral JSON test vectors
- Each vector specifies inputs and expected result (e.g. currentPB, newSet, minimumReps, expectedResult)
- The Swift test suite loads and runs against these vectors
- The TypeScript test suite loads and runs against the SAME vectors
- Both must pass identically -- divergence is caught automatically
- The JSON vectors become the executable specification and single source of truth

### Why not a single shared implementation

Single-implementation approaches (Kotlin Multiplatform, Rust core with bindings) were considered and ruled out:

- **Kotlin Multiplatform** -- would require extracting business logic from the shipped Swift app into Kotlin, adds a third language, weaker AI tooling support, fiddly iOS integration
- **Rust core with WASM/bindings** -- steep learning curve, complex binding layer, massive overkill for simple comparison logic, weakest AI tooling support

The business logic is simple (a handful of comparisons that rarely change). The divergence risk is mild and well-bounded. Test vectors are proportionate to the actual risk. Single-implementation approaches would be a sledgehammer requiring skills deliberately not being invested in.

**Future consideration:** If the phase 3 Insight Engine grows into genuinely complex shared computation, a shared Rust core for that specific part could be reconsidered. Not warranted for phase 2 PB and progression logic.

### Early phase 2 activity

Extract existing Swift PB evaluation test scenarios into language-neutral JSON test vectors. This is a reformatting of existing work, not new thinking, and must happen before or alongside the TypeScript business logic implementation.


---

## 16. Multi-Gym Decision (Phase 2 Scoping)

**A second gym is a "maybe, not now" goal. Phase 2 keeps the door open without building multi-gym infrastructure.**

### Key realisation

A second gym is not just a data problem -- it is a configuration and branding problem:
- Different exercises, PB rules, and gym operations
- Different branding (Wolf identity is baked into icon, colours, launch screen, app name)
- Possibly different integrations (not every gym uses TeamUp)
- Possibly a separate App Store listing

The realistic multi-gym path is therefore one of:
- A separate branded app per gym, sharing codebase and backend
- A white-label configuration system (branding and exercises configured per deployment)
- A genuinely multi-tenant app with gym selection at login

Which is right is deferred to a dedicated design session when a second gym is real.

### What phase 2 does now (cheap, future-proofing only)

1. `gym_id` on every entity in the central store -- keeps every multi-gym path open at near-zero cost
2. Wolf's exercises bundled in the app -- preserves offline-first, works today
3. Central store exercises table seeded with Wolf's 19 exercises, same UUIDs, tagged with Wolf's gym_id

### What phase 2 explicitly defers

- Per-gym exercise configuration and sync
- Branding/white-label systems
- Multi-tenancy infrastructure
- Per-gym integration configuration

None of this is built until a second gym is a real, committed requirement, at which point it receives its own scoping session.

### Exercise definition strategy for phase 2 (single gym)

- App ships with Wolf's 19 exercises bundled (offline-first preserved for anonymous and connected members)
- Central store exercises table seeded with the same 19, identical UUIDs, tagged with Wolf's gym_id
- Member PBs sync up referencing exercise UUIDs that exist in both the bundle and the central store -- clean referential integrity
- When a second gym arrives, gym-specific exercise definitions and the mechanism to deliver them to connected members is designed then, not now
