# Performance Data Access

**Layer:** Resource Access  
**Phase:** 1 -- Active  
**Status:** Not yet defined

## Purpose

Reads and writes session, PB and progression data. Abstracts the underlying storage from the business logic layer. When data moves from local to centralised storage in phase 2, only this component changes.

## Responsibilities

- Write session records
- Write and retrieve PB records per member per exercise
- Retrieve progression history for a member

## Dependencies

- Local Device Store (phase 1)
- Central Data Store (phase 2 -- swap only changes this component)

## Key Activities

- P1: Define the read and write interface
- P2: Build the component
- P3: Test against Local Device Store

Refer to `docs/gym-performance-system-design.md` for full architectural context.
