# Access Control

**Layer:** Utility  
**Phase:** 1 -- Active  
**Status:** Defined, not yet built

## Purpose

Enforces what each user type can see and do across the entire system. Every component that needs to know who the current user is, or whether an action is permitted, calls Access Control. No component makes access decisions independently.

## Phase 1 Implementation

Phase 1 stubs a single member identity. There is no authentication -- the app is single-user on a personal device.

### Interface

```swift
AccessControl
  currentUser() → UserIdentity
  canAccess(resource: Resource, user: UserIdentity) → Bool
```

### UserIdentity Model

```swift
UserIdentity
  id: UUID
  role: Role (member | coach | owner)
  displayName: String
  createdAt: Date
```

### Phase 1 Behaviour

- `currentUser()` returns a hardcoded UserIdentity with role: member
- `canAccess()` returns true for all valid resource requests

## Phase 2 Notes

In phase 2, `currentUser()` is replaced with real authentication. The interface does not change -- only the implementation behind it. All components calling this utility will continue to work without modification.

## Decisions

- Identity model defined in activity A1
- Stub implementation defined in activity A2
- Tests defined in activity A3

Refer to `docs/gym-performance-system-design.md` for full architectural context.
