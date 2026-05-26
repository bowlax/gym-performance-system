# Member Performance

**Layer:** Business Logic  
**Phase:** 1 -- Active  
**Status:** Not yet defined

## Purpose

Records and evaluates member sessions, detects personal bests, and calculates progression over time. This is the core business logic component for the primary member use cases.

## Responsibilities

- Receive and store session records
- Evaluate each session against existing PBs using rules from Exercise Registry
- Calculate and expose progression views over time
- Store coaching commentary against member records (phase 2)

## Dependencies

- Exercise Registry -- for PB rules per exercise type
- Performance Data Access -- for reading and writing session and PB data
- Access Control -- for confirming user identity and permissions

## Key Activities

- MP1: Define session recording and PB evaluation rules
- MP2: Define progression calculation logic
- MP3: Build the component
- MP4: Test against known scenarios

Refer to `docs/gym-performance-system-design.md` for full architectural context.
