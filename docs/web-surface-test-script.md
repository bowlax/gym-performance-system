# Member Web Surface - Manual Test Script

A repeatable checklist for testing the React member web surface locally. Run through
the relevant sections after any change that could affect behaviour, before committing
or deploying.

**Not automated** by design - the surface is still being actively shaped, so a written
checklist avoids the maintenance cost of end-to-end tests while keeping testing
consistent. Automate with Playwright later, as pre-launch hardening, once the surface
is structurally settled.

---

## Setup (before each test session)

1. Ensure `.env.local` in `src/client/web/member-surface` has the Supabase URL,
   publishable key, and a test device member id.
2. Start the dev server: `npm run dev` in `src/client/web/member-surface`.
3. Open the local URL (e.g. http://localhost:8080).
4. Confirm the app loads, signs in via the stub broker, and shows the Board without
   errors. If it cannot connect, the env or config is the issue, not the feature.

**Test data note:** the stub broker adopts the same member (TEST-CUSTOMER-001)
regardless of device id, so all test data lands under one member. Clear it between
sessions if a clean slate is needed (see Cleanup at the end).

---

## 1. Board

- [ ] The Board shows all exercises (all 19), in display order, not only those with a PB.
- [ ] Exercises with a PB show the current PB value, formatted correctly for their
      measurement type (weight in kg, reps, time in seconds, distance in metres).
- [ ] Exercises without a PB show an empty / "no PB yet" state.
- [ ] The training consistency section shows sessions plotted over time (once sessions
      exist). With no sessions, it shows an appropriate empty state.
- [ ] Tapping any exercise card opens its Progression screen.

---

## 2. Log a Session / Log a Set

- [ ] The log flow opens and shows the exercise selection and set input fields.
- [ ] Input fields match the exercise's measurement type (weight+reps, weight+time,
      time only, distance only, reps only).
- [ ] Logging a set for a new exercise creates the session, entry, and set, and the set
      appears.
- [ ] Logging a set that beats the current PB celebrates the new PB (yellow treatment)
      and updates the Board.
- [ ] Logging a set equal to the current PB does NOT create a new PB (equal is not a PB).
- [ ] Logging a timed exercise (e.g. Bike 60s) works - confirms time_seconds is sent
      correctly.
- [ ] Session history (reached from Log a Session) lists past sessions, most recent first.
- [ ] Tapping a session shows the exercises and sets logged in it.

---

## 3. Progression - Display

Open an exercise with some history (log a few ascending sets first if needed).

- [ ] The current PB hero shows the current PB value, large, wolf blue, tabular digits.
- [ ] If there is no current PB, the hero shows a "no current PB" state.
- [ ] The chart plots PB values over time.
- [ ] The history list shows records, most recent first (descending by date).
- [ ] Reset records (if any) show the distinct reset styling and label.

---

## 4. Progression - Add PB Manually

- [ ] The ellipsis / overflow menu shows "Add PB Manually".
- [ ] The form shows value fields for the measurement type, plus a date field.
- [ ] The date field defaults to today and does not allow future dates; past dates are
      allowed.
- [ ] Adding a manual PB **above** the current PB: succeeds, celebrates (yellow), becomes
      current, appears in history, Board updates.
- [ ] Adding a manual PB **below** the current PB: shows the "doesn't beat your current PB,
      not saved" message, and NO record is added (nothing persisted).
- [ ] Adding a manual PB when there is **no current PB**: becomes the opening PB.
- [ ] After adding, the hero, chart, and history all refresh to reflect the change.

---

## 5. Progression - Reset Current PB

- [ ] "Reset Current PB" appears in the menu ONLY when a current PB exists.
- [ ] It has destructive styling.
- [ ] Selecting it shows a confirmation dialog explaining the board will show no PB until
      a new one is logged.
- [ ] Cancelling the dialog makes no change.
- [ ] Confirming: the current PB is cleared. The hero shows the no-current-PB state.
- [ ] The reset record appears in history with the reset styling.
- [ ] No other record is promoted to current (reset clears, it does not promote).
- [ ] The Board shows no PB for that exercise afterwards.

---

## 6. Progression - Delete a History Record

Set up: have at least two PB records for an exercise (e.g. log ascending sets).

- [ ] Each history row has a delete affordance.
- [ ] Selecting delete shows a confirmation dialog.
- [ ] Cancelling makes no change.
- [ ] Deleting a **non-current** record: it is removed from history; the current PB is
      unchanged.
- [ ] Deleting the **current** PB: it is removed; the best remaining non-reset record is
      promoted to current (NOT simply the most recent); the hero and Board update to the
      promoted value.
- [ ] Deleting the current PB when no eligible record remains: the board shows no PB.
- [ ] For a session-derived record, deleting also removes the linked set (if that is the
      intended path).
- [ ] After deletion, the hero, chart, and history all refresh.

---

## 7. Cross-cutting checks

- [ ] Light mode and dark mode: switch system appearance and confirm every screen renders
      correctly, with no unreadable text or wrong backgrounds.
- [ ] Brand colours correct: wolf blue #1A5BA6 primary, PB yellow #FFD600 only for PB
      moments.
- [ ] Numbers use tabular digits and do not shift width as they change.
- [ ] After every state-changing action, the screen reflects the new server state (no
      stale values requiring a manual refresh).
- [ ] No console errors during normal use (open the browser dev tools console and watch).

---

## Cleanup (between sessions)

Two variants. Use the data-only cleanup by default - it clears test data 
but keeps the member, so the member identity stays stable across runs. 
Only use the full cleanup (which also deletes the member) when 
specifically testing the create-or-adopt / first-connection path, where 
you want no member to exist yet.

Set the member id once at the top of the block. Runs in the Supabase web 
SQL editor (PL/pgSQL DO block).

### Data-only cleanup (default - keeps the member)

```sql
do $$
declare
  target_member uuid := 'your-test-member-id-here';
begin
  delete from personal_bests where member_id = target_member;
  delete from sets where exercise_entry_id in (
    select ee.id from exercise_entries ee
    join sessions s on s.id = ee.session_id
    where s.member_id = target_member
  );
  delete from exercise_entries where session_id in (
    select id from sessions where member_id = target_member
  );
  delete from sessions where member_id = target_member;
  -- member record deliberately kept, so identity stays stable across runs
end $$;
```

### Full cleanup (also deletes the member - only for testing first-connection)

Add this line before end $$; in the block above:

```sql
  delete from members where teamup_customer_id = 'TEST-CUSTOMER-001';
```

---

## When to automate

Add Playwright end-to-end tests covering the core flows (log a set, and the three
progression actions) once the web surface is structurally settled, as part of pre-launch
hardening - alongside real TeamUp verification, ES256 signing, and the phase 2 privacy
policy. At that point the UI is stable enough that automated tests are worth their
maintenance cost, and they become part of the pre-launch gate.
