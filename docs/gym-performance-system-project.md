# Gym Performance System -- Project Structure

**Methodology:** Righting Software (The Method)  
**Phase:** 1 -- iOS, On-Device, Members Only  
**Status:** Ready to build  
**Last updated:** May 2026

> At the start of every session, provide both this document and `gym-performance-system-design.md` as context.  
> Update activity status at the end of every session before closing.

---

## Activity Status Key

| Symbol | Meaning |
|---|---|
| ⬜ | Not started |
| 🔵 | In progress |
| ✅ | Complete |
| ⛔ | Blocked |
| 🔁 | Needs rework |

---

## Phase 1 Activity Register

### Foundation

| ID | Activity | Size | Depends On | Status | Notes |
|---|---|---|---|---|---|
| L1 | Select and configure on-device storage technology | S | -- | ✅ | |
| L2 | Define data schema for all phase 1 data types | M | L1 | ⬜ | High risk -- cascades everywhere. Must anticipate phase 2. Treat as dedicated session |
| L3 | Validate schema against all phase 1 use cases | S | L2 | ⬜ | Review activity -- walk every use case against the schema |
| A1 | Define user identity model for phase 1 | S | -- | ✅ | Phase 1 is single user / member only. Must be extensible for phase 2 |
| A2 | Build the Access Control utility | S | A1 | ✅ | Minimal in phase 1 but architecture must support future roles |
| A3 | Test Access Control | S | A2 | ✅ | |

### Data Layer

| ID | Activity | Size | Depends On | Status | Notes |
|---|---|---|---|---|---|
| C1 | Define the interface for reading exercise definitions | S | L3 | ⬜ | Read-only interface |
| C2 | Build the Configuration Data Access component | S | C1 | ⬜ | Thin layer over Local Device Store |
| C3 | Test Configuration Data Access | S | C2 | ⬜ | |
| P1 | Define the interface for reading and writing session and PB data | M | L3 | ⬜ | Read and write, multiple data types |
| P2 | Build the Performance Data Access component | M | P1 | ⬜ | |
| P3 | Test Performance Data Access | S | P2 | ⬜ | |

### Exercise and PB Logic

| ID | Activity | Size | Depends On | Status | Notes |
|---|---|---|---|---|---|
| E1 | Define the exercise list and measurement types for phase 1 | M | -- | ⬜ | Requires domain input -- collaborative session needed |
| E2 | Define PB rules per exercise type | M | E1 | ⬜ | Non-trivial -- multiple measurement types. Requires domain input |
| E3 | Build the Exercise Registry component | S | E2, C3 | ⬜ | Logic defined in E1/E2 -- build is straightforward |
| E4 | Test PB rule evaluation against known scenarios | M | E3 | ⬜ | Needs scenario coverage across all exercise types |

### Core Business Logic

| ID | Activity | Size | Depends On | Status | Notes |
|---|---|---|---|---|---|
| MP1 | Define session recording and PB evaluation rules | M | E4, P3 | ⬜ | Core business logic -- needs precision before build |
| MP2 | Define progression calculation logic | M | MP1 | ⬜ | What does progression mean, how is it calculated and displayed |
| MP3 | Build the Member Performance component | L | MP2, A3 | ⬜ | Most complex component in phase 1 |
| MP4 | Test Member Performance | L | MP3 | ⬜ | Broad scenario coverage -- session recording, PB detection, progression |

### Client and Integration

| ID | Activity | Size | Depends On | Status | Notes |
|---|---|---|---|---|---|
| MS1 | Define screen flows and interactions for phase 1 | M | MP2 | ⬜ | Design activity -- use Lovable for exploration |
| MS2 | Build the session logging screen | M | MS1, MP4 | ⬜ | |
| MS3 | Build the PB tracking and display screen | M | MS1, MP4 | ⬜ | |
| MS4 | Build the progression view screen | M | MS1, MP4 | ⬜ | |
| MS5 | Integration test -- full use case walkthrough end to end | L | MS2, MS3, MS4 | ⬜ | Walk every member use case through the built system |

---

## Critical Path

```
L1 → L2 → L3 → P1 → P2 → P3 ──────────────────────────────┐
                 ↓                                           ↓
                C1 → C2 → C3 → E1 → E2 → E3 → E4 ──────→ MP1 → MP2 → MP3 → MP4 → MS1 → MS2 → MS3 → MS4 → MS5
                                                             ↑
A1 → A2 → A3 ───────────────────────────────────────────────┘
```

The critical path runs through the data layer and into Member Performance. Exercise Registry and Access Control feed in before MP1 but can be built in parallel with the data layer work.

---

## Indicative Schedule

| Group | Activities | Indicative Sessions |
|---|---|---|
| Foundation | L1, L2, L3, A1, A2, A3 | 4 -- 5 |
| Data Layer | C1, C2, C3, P1, P2, P3 | 4 -- 5 |
| Exercise and PB Logic | E1, E2, E3, E4 | 4 -- 5 |
| Core Business Logic | MP1, MP2, MP3, MP4 | 6 -- 8 |
| Client and Integration | MS1, MS2, MS3, MS4, MS5 | 6 -- 8 |
| **Total** | **22 activities** | **24 -- 31 sessions** |

Sessions are variable in length and intensity. Two to three sessions per week is a realistic working pace, putting phase 1 delivery at six to ten weeks from start.

---

## Decisions Log

| Date | Decision | Rationale |
|---|---|---|
| May 2026 | Phase 1 is members only, on-device, PB and session tracking only | Centralisation is prerequisite for coach and owner views. Validates core use case before infrastructure investment |
| May 2026 | Goals deferred to phase 2 | No coach surface in phase 1. Keep scope tight |
| May 2026 | Exercise definitions bundled with app in phase 1 | Quarterly change frequency makes app updates acceptable at current scale |
| May 2026 | Injury and weight logging deferred to phase 2 | Out of scope for phase 1 member-only, PB-focused release |
| May 2026 | Messaging between coaches and members out of scope | In-person interaction covers this need. Digital messaging adds complexity without value |

---

## Issues and Risks

| ID | Description | Severity | Status |
|---|---|---|---|
| R1 | Data schema (L2) must anticipate phase 2 centralisation or migration becomes costly | High | Open -- mitigated by treating L2 as a dedicated careful session |
| R2 | Exercise definitions and PB rules (E1, E2) require domain expertise input -- cannot be completed without collaborative session | Medium | Open |
| R3 | Access Control built minimally in phase 1 must remain extensible for multi-role phase 2 | Medium | Open -- mitigated by design |

---

## Session Log

| Session | Date | Activities Completed | Decisions Made | Next Up |
|---|---|---|---|---|
| 1 | May 2026 | Design document completed. Architecture validated. Phase 1 scoped. Project document created | See decisions log | L1, then L2 as dedicated session |
| 2 | May 2026 | L1, A1, A2, A3 | SwiftData selected for iOS 17+ local storage. SSH authentication configured for GitHub. | L2 -- data schema definition |

---

## Next Session

**Start here:** L2 -- Data schema definition  
**Note:** This is a high risk activity -- it cascades across the entire data layer and must anticipate phase 2. Treat as a dedicated session. Do not rush it.

> Reminder: always provide both `gym-performance-system-design.md` and this document at the start of each session.
