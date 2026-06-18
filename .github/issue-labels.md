# GitHub Issue Labels — TestFlight Feedback Triage

Labels used to triage feedback from TestFlight testers and internal issue tracking.

| Label | Description | Colour |
|-------|-------------|--------|
| `bug` | Something is broken | `#d73a4a` |
| `ux` | Works but could be better | `#1A5BA6` |
| `enhancement` | New feature or improvement | `#0075ca` |
| `phase-1` | In scope for phase 1 | `#238636` |
| `phase-2` | Deferred to phase 2 | `#6f42c1` |
| `phase-3` | Deferred to phase 3 | `#8b949e` |
| `tester-feedback` | Raised by a TestFlight tester | `#e4e669` |
| `wont-fix` | Considered and declined | `#ffffff` |
| `in-progress` | Currently being worked on | `#fbca04` |

## Triage flow

1. Apply `tester-feedback` when the issue comes from TestFlight beta feedback.
2. Classify with one of: `bug`, `ux`, or `enhancement`.
3. Apply a phase label: `phase-1`, `phase-2`, or `phase-3`.
4. Mark active work with `in-progress`.
5. Close declined items with `wont-fix`.

Labels are managed on GitHub via `gh label create` (see repository settings → Labels).
