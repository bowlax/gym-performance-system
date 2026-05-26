# Local Device Store

**Layer:** Resource  
**Phase:** 1 -- Active  
**Technology:** SwiftData (iOS 17+)  
**Status:** Technology selected, schema not yet defined

## Purpose

On-device persistent storage for all phase 1 data. Accessed exclusively through the Resource Access layer -- no component above Resource Access talks to this directly.

## Technology Decision

SwiftData selected in activity L1. Rationale:
- Native iOS 17+ framework
- Clean Swift API with minimal boilerplate
- Natural fit with SwiftUI and Lovable-generated code
- Well supported by Cursor for scaffolding

## Key Activities

- L1: Technology selection -- complete
- L2: Data schema definition -- pending
- L3: Schema validation against use cases -- pending

## Phase 2 Note

When data centralises in phase 2, this store is replaced by Central Data Store. The swap is contained entirely within the Resource Access layer. Nothing above it changes.

Refer to `docs/gym-performance-system-design.md` for full architectural context.
