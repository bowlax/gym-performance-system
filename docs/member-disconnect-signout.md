# Member disconnect (iOS) and sign-out (web)

Engineering note for the shipped session-end behaviours. Product intent is in
`docs/gym-performance-system-design.md` §19 (Deletion model). This file maps
that intent to code entry points.

**Neither action deletes training data.** Central/cloud history is retained.
Full erasure is a separate administrator-executed GDPR request (email
privacy@lbconsulting.tech) — not part of disconnect or sign-out.

---

## iOS — Disconnect

| | |
|---|---|
| UI | Settings (`AppInfoSheet`) → Disconnect confirm alert |
| Implementation | `MemberConnectionStore.disconnect()` |
| Path | `src/utilities/sync-manager/MemberConnectionStore.swift` |

**Clears**

- Access / refresh tokens and expiry (Keychain + UserDefaults)
- `connectedMemberId`, connected gym id
- `isConnected` → `false`
- `dontAskConnectAgain` → `false` (so connect can be offered again)

**Retains**

- All local SwiftData training history
- All central/cloud rows for that member
- `hasEverConnected` and `lastConnectedMemberId` (used to refuse reconnecting as a *different* TeamUp account on the same device)

After disconnect the device is local-only again. Reconnecting with the **same**
TeamUp account runs create-or-adopt + `syncAfterConnect` (retag → PULL → MERGE →
PUSH) and restores cloud history. See
[`docs/ios-sync-first-connect.md`](ios-sync-first-connect.md) and
[`docs/ios-sync-pull-merge-push.md`](ios-sync-pull-merge-push.md).

---

## Web — Sign out

| | |
|---|---|
| UI | Settings → Sign out |
| Client | `auth-provider.signOut` → `POST /api/auth/signout` |
| Server | `clearAuthSession()` in `src/lib/gp/session.server.ts` |
| Route | `src/routes/api/auth/signout.ts` |

**Clears**

- Sealed httpOnly `gp_auth` cookie (Worker SSR session; `SESSION_SECRET`)
- In-memory React auth session state

**Retains**

- All central/cloud training data (web has no local store)
- Device member id cookie (`gp_device_member_id`) used for the next authorize

Signing out ends the browser session only. Signing in again resumes the same
cloud member under TeamUp OAuth.

---

## Related

- Design §19 Deletion model / privacy dependency
- Privacy policy §6 (how long we keep data) and landing FAQ
- Connect (not disconnect): [`docs/ios-sync-first-connect.md`](ios-sync-first-connect.md)
