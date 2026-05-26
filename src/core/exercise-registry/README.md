# Exercise Registry

**Layer:** Business Logic  
**Phase:** 1 -- Active  
**Status:** Not yet defined

## Purpose

Defines all exercises, their measurement types, and the rules for what constitutes a personal best for each. This is the authoritative source of exercise definitions for the entire system.

## Responsibilities

- Maintain the list of exercises available in the system
- Define measurement types per exercise (weight and reps, time, distance, etc.)
- Define PB rules per exercise type
- Expose exercise definitions to Member Performance and Configuration Data Access

## Phase 1 Note

Exercise definitions are static and bundled with the app in phase 1. The registry reads from Configuration Data Access, which reads from the Local Device Store. App update required when exercises change -- acceptable given quarterly change frequency.

## Key Activities

- E1: Define exercise list and measurement types
- E2: Define PB rules per exercise type
- E3: Build the component
- E4: Test PB rule evaluation against known scenarios

Refer to `docs/gym-performance-system-design.md` for full architectural context.
