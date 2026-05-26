# Configuration Data Access

**Layer:** Resource Access  
**Phase:** 1 -- Active  
**Status:** Not yet defined

## Purpose

Reads exercise definitions and system configuration. Read-only in phase 1. Abstracts the source of configuration data from the Exercise Registry.

## Responsibilities

- Read exercise definitions and measurement types
- Read PB rules per exercise type
- Read system configuration settings

## Phase 1 Note

Configuration is bundled with the app and stored in the Local Device Store on first run.

## Key Activities

- C1: Define the read interface
- C2: Build the component
- C3: Test against Exercise Registry

Refer to `docs/gym-performance-system-design.md` for full architectural context.
