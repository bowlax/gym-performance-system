# Owner Surface — Design Doc

**Source:** Steve's discovery answers (8 questions, transcribed 21 Jul).
**Status:** Draft for review. Nothing here is built yet. Scope and
sequencing proposed below, pending Lee's sign-off before any Cursor
work starts.

**Updated for current state:** phase 2 (auth, sync, both member
surfaces, disconnect/sign-out) is complete and shipped. iOS is in full
App Store review (build 16); the web member surface is live on
Cloudflare. A real population now exists — around 16 connected members
at time of writing, growing organically as Wolf's ~110 members
individually decide to connect, no marketing push. This is enough to
make the population-dependent items below (3.2–3.4) genuinely worth
scoping, though still small enough that "most PBs this month" or an
inactivity list will look thin for a while yet.

**Prior decision, confirmed by this discovery, not changed:** single
owner surface, no separate coach surface. Ben and Sean (coaches) see PB
numbers and session rosters only — no admin, no member motivation
data, no goals visibility beyond what's on the board. Steve is
explicit: coaches are "employed to deliver sessions," not to manage
information. This doc is about what **Steve** sees.

---

## 1. What the discovery actually says

Steve's day is roughly 50–60% session delivery, 40–50% admin/lead
generation/business development, plus a large, recurring load of
one-to-one WhatsApp messaging — quarterly goal-setting alone generates
~80 individual conversations. Programming is entirely manual and
outside the app: sessions are planned by feel, communicated to coaches
via WhatsApp voice notes, and not tracked digitally.

Two things he does today that the app could materially help with:

- **Spotting who's doing well / who's slipping** — currently done by
  eyeballing the board colours, checking TeamUp for session frequency,
  and general gym-floor observation. He's explicit this is too
  reliant on him personally and too slow: he'd like to catch a
  slipping member at 7–10 days of absence, but currently often
  doesn't notice until 10–14 days.
- **Giving concrete, evidence-based feedback** — currently anecdotal
  ("we were there together and saw it"). He wants something
  *irrefutable*: a graph, a before/after number, something he can put
  in front of a member and say "look."

One thing that came up independently and matches work already
shipped: a member (Nick) asked Steve — unprompted — for a way to see
rolling PBs alongside an all-time best. That's #28, already built and
deployed. This is validation, not new scope, but worth noting: the
feature we built on early feedback landed on the thing at least one
real member independently wants.

---

## 2. Access model — read before building anything

Everything shipped so far assumes single-member scope: RLS keyed on
`auth.jwt() member_id`, or on-device data that's inherently one
member's. The owner surface is the first thing that needs to read
*across* members, and that's a genuine new volatility axis — not a
UI decision. This section settles it once, so every subsequent
endpoint inherits a decided boundary instead of each one reinventing
its own check.

**Who can call these endpoints.** One consistent claim,
`app_role = 'owner'`, checked at the RLS / ResourceAccess layer — the
same place `app_role` already gates coach reads today. Not a
per-function hand-check in application code. If a new owner-facing
Edge Function is tempted to write its own "is this the owner" logic
inline, that's the drift starting; it should instead rely on the same
RLS policy every other access decision in this system already goes
through.

**What the boundary returns.** Aggregate and summary data only —
counts, dates, derived PB values. Never raw training rows belonging to
another member. A member's own session detail stays scoped to that
member, full stop; the owner role widens *what can be summarised
about*, not *what can be read in full*.

**Which features need the shared Engine, and which don't.** Not
everything here is the same kind of query, and that's fine — the
Method doesn't require false unification:

- **Anything touching current-PB or staleness status** (the progress
  graph, any "who's lapsed" logic) MUST route through the existing
  `pb-derivation.ts` / `PBDerivation.swift` — never reimplement
  freshness, tie-break, or reset logic inside an owner-facing query.
  This is the one place real drift risk exists: a fresh SQL query
  written to answer "who's lapsed" would almost certainly miss the
  reset line, the tie-break rule, or the undated-entry decision that
  #28 got right after real design work.
- **Most-PBs-this-period and exercise-frequency are genuinely
  independent aggregate shapes** — different group-by, different
  tables, no shared core logic with each other or with PB derivation
  beyond reading badge/session data that's already correct. Each is
  its own small, use-case-named Manager. No forced Engine needed.

**Naming.** Follow the existing use-case-named Edge Function
convention (`add-manual-pb`, `log-set`) rather than a generic
"owner API": `owner-current-pbs`, `owner-inactive-members`,
`owner-pb-frequency`, or similar — one function per use case, not one
do-everything endpoint.

**What this unlocks.** Both a future dashboard and a future
conversational interface (e.g. an LLM tool-calling setup) can consume
the same functions as their data source. Neither gets broader
database access than these endpoints expose — the endpoints *are* the
safe wrapper, for either consumer. This was the resolution to the
bot-vs-dashboard access question: build this layer once, regardless of
which interface sits on top, or if both eventually do.

---

## 3. Scope boundary: owner-only, not member-facing comparison

Several of Steve's asks are inherently about **him** seeing something
across **all** members (who's done the most PBs this week, who hasn't
trained in N days). None of this is one member seeing another's data.

This matters for two reasons:

1. **Consent shape.** The privacy policy drafted this session covers
   "you and your coach can see your data." An aggregate leaderboard
   or cross-member comparison, if ever shown *to members*, is a
   different kind of visibility and isn't covered. Keeping these
   views **owner-only** avoids that question entirely for now. If a
   member-facing leaderboard is ever wanted, it needs its own consent
   framing and its own line in the policy — treat as explicitly out
   of scope here.
2. **Population dependency.** Every feature below that depends on
   session/PB frequency across members only has data for members who
   have **connected**. Right now that's nobody but Lee. These features
   are correctly sequenced, but most are not *usable* until TestFlight
   widens and real members connect (which itself waits on the privacy
   policy). This doc separates "buildable now" from "buildable but
   pointless until population exists."

---

## 4. Proposed features, in priority order

### 3.1 Progress graph on the progression screen

**What:** A visual chart of a member's value over time for a given
exercise — the thing Steve describes wanting most directly: "here's a
graph, here's where it started, here's where it is now."

**Why first:** It's the single clearest, most emotionally specific ask
in the whole discovery — Steve calls it a "game changer" for feedback
conversations, unprompted, twice. It's also likely the cheapest of the
substantial asks: the progression screen already derives and displays
history per exercise; this is a rendering change on data that already
exists, not a new data model.

**Open question before building:** does the progression screen
currently show history as a list, or is there already a chart? Check
before scoping — if it's list-only today, this is the addition; if a
chart exists, this becomes "does it need reset markers / lifetime PB
shown on it," which is a smaller ask.

**Volatility note (Method framing):** charting is a *display* concern
over the existing derivation — it should sit entirely in the Client
layer, consuming `PBReadDerivation`'s output as-is. No Business Logic
or ResourceAccess changes anticipated.

**Owner-facing or member-facing?** Both, arguably — Steve wants it to
show *members* their own graph too ("two taps away from... here's my
current PB"), not just something he sees. Worth clarifying with Steve
whether this is a member-facing progression enhancement, an
owner-facing per-member lookup, or both. My read: **both**, since the
underlying data and rendering are identical either way — the owner
surface would just let Steve pick *which* member's graph he's looking
at.

---

### 3.2 "Most PBs this week/month" — owner view

**What:** An aggregate: across all connected members, who's hit the
most personal bests in a given period.

**Why:** Directly requested, cheap relative to its value — the PB
derivation already computes badges/achievements per member; this is a
count-and-rank across members rather than a new concept.

**Data need:** requires querying across members, which today's RLS
model scopes tightly to `member_id = auth.jwt() member_id`. An owner
view needs a policy allowing the owner role to read aggregate PB
counts (not full training detail — counts and dates, not the
underlying sets) across the gym. This is a genuinely new RLS
surface, not just a new query — needs its own policy design, not just
a new SELECT.

**Population dependency:** minimal at low numbers, but genuinely
useless until enough members are connected that "most PBs this month"
means something. Buildable now; with ~16 connected members today, the
feature would work but read thin — worth building once population is
flagged as "worth it" rather than waiting for a specific number.

---

### 3.3 Inactivity view — "who hasn't trained in 7–10 days"

**What:** Owner-facing list of connected members sorted by days since
last session, so Steve can catch someone slipping in his stated
window (7–10 days) instead of his current 10–14 day lag.

**Why:** This is the *second* clearest ask in the discovery — Steve
explicitly says he wants to be faster at this and currently isn't.

**Data need:** `last session date per member`, derivable from existing
session data — no new storage, just a new owner-scoped aggregate
query (same RLS consideration as 3.2).

**Population dependency:** still the main blocker, though less absolute
than when this was first written (Lee-only). With around 16 connected
members now, this view shows real signal rather than one row - but
that's still a small fraction of Wolf's ~110, so "who's slipping"
coverage is partial. Worth building now that there's something real to
test against; just be honest with Steve that it only reflects the
connected subset, not the whole gym, until adoption grows further.

**Note:** Steve currently gets a *partial* version of this for free
via TeamUp's own automated 7-day inactivity message — worth checking
whether this app feature is additive to that or would duplicate/
conflict with it. Ask Steve.

---

### 3.4 Exercise frequency — gym-wide, not per-member

**What:** "When did we last programme/perform split squats" — a
programming aid for Steve, not a member metric. He currently has no
way to answer this other than searching his own WhatsApp history to
coaches.

**Why it's different from 3.2/3.3:** this aggregates across
*exercises*, not across *members*. It's "how recently has exercise X
appeared in ANY session," which is a different query shape — group by
exercise, not group by member.

**Data need:** last-performed date per exercise, gym-wide. Simple
aggregate over existing session/entry data. Same RLS consideration —
owner needs a scoped read across all members' sessions for this one
purpose.

**Population dependency:** less severe than 3.2/3.3 — even a handful
of connected members gives Steve *some* signal about what's been
programmed recently, since it's about session content, not member
behaviour. Could be useful earlier than the member-count-dependent
features.

---

### 3.5 Goals — explicitly deferred, needs its own design pass

**What Steve described:** a full quarterly cycle — ~110 individual
goal-setting conversations, informal targets per lift (usually "hit 5–6
new PBs" or "add 2.5–5kg to specific lifts"), tracked manually against
session count and PB achievement, ticked off by hand, rolled into the
next quarter with adjustment.

**Why this is not on the numbered list above:** it's not a feature,
it's a subsystem. It needs its own data model (a goal has a target, an
exercise, a period, a status — none of which exist today), its own UI
(setting, tracking, closing out), and its own volatility analysis
before any of it gets built. Folding it into the list above would
undersell it and risk a rushed design.

**Recommendation:** treat as **Phase 3** — a dedicated design
conversation once the smaller owner-surface items above are shipped
and the connect flow has real population. Flag to Steve that this is
recognised as important and substantial, not dropped.

---

## 5. What this doc deliberately does NOT cover

- **Coach surface** — confirmed out of scope; coaches see what they
  see today (PB numbers, session rosters).
- **Member-facing leaderboards / cross-member comparison** — the
  aggregate views above are owner-only. A member-facing version is a
  different consent question, not addressed here.
- **Goals** — see 3.5. Deliberately deferred, not designed here.
- **TeamUp inactivity-message overlap** (3.3) — needs a quick check
  with Steve, not a design decision here.

---

## 6. Suggested sequencing

| Order | Item | Buildable now? | Useful now? |
|---|---|---|---|
| 1 | Progress graph | Yes — check current progression screen first | Yes, immediately (even for Lee's own data) |
| 2 | Most PBs this month (owner) | Yes, needs new RLS policy | Only once population exists |
| 3 | Exercise frequency (owner) | Yes, needs new RLS policy | Partially useful even at low population |
| 4 | Inactivity view (owner) | Yes, needs new RLS policy | Blocked on real population |
| 5 | Goals | No — needs its own design phase | N/A |

**Practical read:** build the graph first — it's the highest-value,
lowest-dependency item and doesn't wait on anything. The three
owner-aggregate views (2–4) are worth designing the RLS approach for
once, since they share a shape (owner-scoped cross-member read), but
their real-world value is gated on the same thing the whole
connect-flow work has been gated on: members actually connecting,
which waits on the privacy policy.

---

## 7. Open questions for Steve

1. Does he want the progress graph as something **members** see
   themselves (self-service, "two taps to my bench graph"), or
   primarily something **he** pulls up during a coaching conversation,
   or both?
2. Does the TeamUp 7-day inactivity auto-message already cover the
   "who's slipping" need well enough, or does he want the in-app view
   in addition/instead?
3. For "most PBs this month" — is this something he'd want members to
   see too eventually (a leaderboard), or strictly an owner tool? (My
   read from the transcript: he asked for it as something *he* sees,
   not framed as member-facing — worth confirming rather than
   assuming.)
