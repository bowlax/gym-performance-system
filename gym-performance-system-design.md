# Gym Performance System -- Project Design Document

**Methodology:** Righting Software (The Method)  
**Status:** Architecture validated, phase 1 scoped  
**Last updated:** May 2026

---

## 1. Mission Statement

To make the performance and progression of members measurable over time, enabling both individuals to understand their development and gym management to make evidence-based decisions about programme design and organisational direction.

---

## 2. Stakeholders

| Stakeholder | Description |
|---|---|
| **Members** | All gym members who train. Treated equally for now. Veterans group noted but not specialised yet. |
| **Coaches** | Three in total. Operational and member-facing. No member assignment -- all coaches can see all members. |
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

---

## 4. Core Use Cases

These are the smallest set that define the essence of the system. Every architectural component must serve at least one of them.

1. **A member's performance is recorded and made meaningful over time**
2. **That meaning is surfaced to the right person at the right time**
3. **Collective performance patterns reveal the effectiveness of the gym's programme**

> **Note:** Core use case 3 cannot be delivered until data is centralised. Phase 1 delivers core use cases 1 and 2 only.

---

## 5. Volatility Register

Each volatility is encapsulated by a specific component. Changes to any of these should require changes only to the component that encapsulates them.

| # | Volatility | Encapsulated By |
|---|---|---|
| 1 | User types and roles | Access Control utility |
| 2 | Client platform | Client layer surfaces and platforms |
| 3 | Data location | Resource Access layer + Resource layer |
| 4 | Exercise definitions and PB rules | Exercise Registry + Configuration Data Access |
| 5 | Flag and insight rules | Insight Engine |
| 6 | Goal types | Goal Management |
| 7 | Authentication and access control | Access Control utility |
| 8 | Notification and delivery mechanism | Notification Manager + Notification Service Access |
| 9 | Aggregation and reporting | Aggregation Service |
| 10 | Sensitive and personal data -- privacy, access, regulatory handling | Sensitive Data Manager + Sensitive Data Access |

---

## 6. Full System Architecture

Dependencies flow downward only. No component may call a component in a layer above it.

---

### Utilities
*Cross-cutting concerns consumed by all layers*

| Component | Responsibility |
|---|---|
| **Access Control** | Enforces what each user type can see and do across the entire system |
| **Sensitive Data Manager** | Governs privacy rules, consent and regulatory handling of personal and health data |
| **Notification Manager** | Determines who needs to be notified of what, and when. Decoupled from delivery mechanism |

---

### Client Layer
*Encapsulates platform volatility. Each surface connects to the same Business Logic beneath it. Implementation decisions -- one app or many -- are deferred to build time*

**Surfaces:**

| Surface | Description |
|---|---|
| **Member Surface** | Logging sessions and PBs, viewing personal progression, receiving guidance |
| **Coach Surface** | Viewing member data, setting goals, adding commentary, viewing flags |
| **Owner Surface** | Gym-wide patterns, strategic intelligence, member and coach management |

**Platforms:**

| Platform | Status |
|---|---|
| **iOS Platform** | Current -- phase 1 |
| **Web Platform** | Future -- phase 2, already anticipated |

---

### Business Logic Layer
*The rules, processes and decisions that define how the system behaves. Platform agnostic and storage agnostic*

| Component | Responsibility |
|---|---|
| **Member Performance** | Recording and evaluating sessions, PBs and progression over time |
| **Exercise Registry** | Exercise definitions, measurement types and PB rules |
| **Goal Management** | Creating, tracking and evaluating goals of any type |
| **Insight Engine** | Detecting patterns in data and generating flags. Consumes AI Model Access when available |
| **Aggregation Service** | Producing gym-wide views and pattern analysis for the owner |

---

### Resource Access Layer
*Knows how to talk to storage and services. Knows nothing about what the data means. Changing storage only changes this layer*

| Component | Responsibility |
|---|---|
| **Performance Data Access** | Session, PB and progression data |
| **Member Profile Access** | Identity, role, attendance and non-sensitive member data |
| **Sensitive Data Access** | Weight, injuries, health notes -- governed by Sensitive Data Manager |
| **Goal Data Access** | Goal records and evaluation state |
| **Configuration Data Access** | Exercise definitions, PB rules, system configuration |
| **AI Model Access** | Abstracts analytical capability -- rules-based today, LLM-powered in future |
| **Notification Service Access** | Passes notifications to the delivery layer, decoupled from mechanism |

---

### Resource Layer
*Actual storage and infrastructure. Swappable without touching anything above*

| Component | Status |
|---|---|
| **Local Device Store** | Phase 1 -- on-device storage |
| **Central Data Store** | Phase 2 -- centralised database, already anticipated in architecture |
| **LLM Service** | Future -- AI analytical capability, already anticipated |
| **Notification Service** | Phase 2 -- email, push or other delivery infrastructure |

---

## 7. Architecture Validation

All three core use cases were walked through the architecture as call chains. All validated cleanly with no structural gaps.

| Core Use Case | Result |
|---|---|
| A member's performance is recorded and made meaningful over time | ✅ Validated |
| That meaning is surfaced to the right person at the right time | ✅ Validated |
| Collective performance patterns reveal the effectiveness of the gym's programme | ✅ Validated -- requires Central Data Store |

---

## 8. Phase Definitions

### Phase 1 -- iOS, On-Device, Members Only

**Scope:** A member can record their sessions, track their personal bests, and view their progression over time.

**Active components:**

| Layer | Components |
|---|---|
| Utilities | Access Control |
| Client | Member Surface on iOS Platform |
| Business Logic | Member Performance, Exercise Registry *(static, bundled)* |
| Resource Access | Performance Data Access, Configuration Data Access |
| Resource | Local Device Store |

**Explicitly deferred to phase 2:**
- Goal Management
- Insight Engine
- Aggregation Service
- Sensitive Data Manager
- Notification Manager
- Coach Surface
- Owner Surface
- Central Data Store
- LLM Service
- Notification Service

**Known constraint:** Exercise definitions bundled with the app. App update required when exercises change. Acceptable given quarterly change frequency at current scale.

---

### Phase 2 -- Centralised, Coach and Owner Surfaces

**Scope:** Full use case set across all stakeholders. Central data store replaces local device store. Coach and owner surfaces become viable. Insight Engine, Aggregation Service and Notification Manager activated.

**Key unlock:** Core use case 3 -- collective performance patterns -- becomes deliverable only in this phase.

---

## 9. Key Design Decisions

| Decision | Rationale |
|---|---|
| Goals are coach-owned, not member-authored | Reflects current gym practice -- coaches set goals, members work towards them |
| Messaging between members and coaches is out of scope | Coaches and members interact in person. Digital messaging adds complexity without adding value |
| Session programme planning is out of scope | System is an intelligence tool, not a planning tool. Insights inform planning done elsewhere |
| Veterans group not specialised | Treated as members for now. Noted for future consideration |
| Exercise definitions bundled in phase 1 | Quarterly change frequency makes app updates acceptable. Avoids infrastructure cost in proof of concept phase |
| Phase 1 is members only, no coach or owner surface | Centralisation is a prerequisite for cross-member views. Phase 1 validates core individual use case before investing in infrastructure |
| Injury notes are free text | Structured forms would discourage logging. Low friction is more important than structured data at this stage |

---

## 10. Open Questions and Future Considerations

- Veterans group -- may need specialised session types or goal structures in future
- Notification delivery mechanism -- push on iOS, to be determined for web
- LLM integration specifics -- model choice, prompting strategy, cost model
- Data privacy and regulatory requirements -- GDPR compliance for weight and injury data, to be addressed before phase 2
- Authentication mechanism -- to be designed before coach and owner surfaces are built
- Whether member and coach surfaces are one app or separate apps -- deferred to build time

---

*This document is the authoritative design record for the Gym Performance System. All build decisions should trace back to the architecture and use cases captured here. When starting a new session, provide this document as context before proceeding.*
