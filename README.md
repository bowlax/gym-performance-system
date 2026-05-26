# Gym Performance System

A system for making the performance and progression of gym members measurable over time, enabling individuals to understand their development and gym management to make evidence-based decisions about programme design and organisational direction.

## Methodology

This project follows the Righting Software methodology (The Method). All architectural decisions trace back to use cases and volatility analysis documented in `/docs`. Do not make structural changes without first consulting the design document.

## Documentation

| Document | Purpose |
|---|---|
| `docs/gym-performance-system-design.md` | Authoritative design record -- mission, stakeholders, use cases, architecture |
| `docs/gym-performance-system-project.md` | Working project document -- activity status, decisions log, session log |

**Always read both documents before starting any work on this codebase.**

## Architecture

The system is decomposed into layers. Dependencies flow downward only -- no component may call a component in a layer above it.

```
┌─────────────────────────────────────────┐
│           Utilities                     │
│  Access Control  │  Sensitive Data Mgr  │  Notification Manager
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│           Client Layer                  │
│  Member Surface  │  Coach Surface  │  Owner Surface
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│         Business Logic Layer            │
│  Member Performance  │  Exercise Registry  │  Goal Management
│  Insight Engine  │  Aggregation Service   │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│        Resource Access Layer            │
│  Performance Data Access               │
│  Configuration Data Access             │
│  Sensitive Data Access                 │
│  Goal Data Access                      │
│  AI Model Access                       │
│  Notification Service Access           │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│           Resource Layer                │
│  Local Device Store  │  Central Data Store
│  LLM Service  │  Notification Service   │
└─────────────────────────────────────────┘
```

## Repository Structure

```
/docs           Design and project documents
/src
  /core         Business logic components
  /data         Resource access components
  /client       Client surfaces by platform
  /utilities    Cross-cutting utilities
  /resources    Storage and infrastructure
/tests          Tests mirroring src structure
```

Folders marked with a README saying "Phase 2 Component" are intentionally empty. Do not add code to them until they have been formally activated in the project design document.

## Phase 1 Scope

iOS, on-device, members only. A member can record their sessions, track their personal bests, and view their progression over time.

**Active components in phase 1:**
- Access Control (utility)
- Member Surface on iOS (client)
- Member Performance (business logic)
- Exercise Registry (business logic)
- Performance Data Access (resource access)
- Configuration Data Access (resource access)
- Local Device Store -- SwiftData, iOS 17+ (resource)

## Tooling

| Tool | Purpose |
|---|---|
| Claude | Design, specification, architecture decisions |
| Cursor | Component implementation, business logic, resource access layer |
| Lovable | iOS client screens and interactions |
| Claude Code | Multi-file implementation tasks, refactoring |
| GitHub | Version control, persistent project record |
