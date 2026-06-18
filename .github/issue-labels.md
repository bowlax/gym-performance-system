# GitHub Issue Labels — TestFlight Feedback Triage

Labels used to triage feedback from TestFlight testers and internal issue tracking.

| Label | Description | Colour |
|-------|-------------|--------|
| `bug` | Something is broken | `#d73a4a` |
| `ux` | Works but could be better | `#1A5BA6` |
| `enhancement` | New feature or improvement | `#0075ca` |
| `phase-2` | Valid but belongs in phase 2 | `#6f42c1` |
| `tester-feedback` | Raised by a TestFlight tester | `#e4e669` |
| `wont-fix` | Considered and declined | `#ffffff` |
| `in-progress` | Currently being worked on | `#fbca04` |

## Triage flow

1. Apply `tester-feedback` when the issue comes from TestFlight beta feedback.
2. Classify with one of: `bug`, `ux`, or `enhancement`.
3. Use `phase-2` for valid requests deferred to a later release.
4. Mark active work with `in-progress`.
5. Close declined items with `wont-fix`.

Labels are managed on GitHub via `gh label create` (see repository settings → Labels).
