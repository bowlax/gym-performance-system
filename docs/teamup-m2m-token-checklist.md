# TeamUp M2M token — for Steve

A short checklist for generating one extra TeamUp credential. This is **new** — we still have the client ID and secret you already sent. We have not lost those.

---

## What this is for

It lets our backend periodically ask TeamUp for the list of member names, so the owner tools can show real names instead of anonymous account numbers.

---

## Why this is different from what you already gave us

The earlier **client ID and secret** let members log in through the app.

This new token is a different kind of access. It lets our server ask TeamUp for data directly, without anyone logging in. We need it for this specific feature (putting names next to the numbers).

---

## How to generate it

Do this while logged into the TeamUp **business dashboard** as owner or admin (the same place you registered the original API application).

- [ ] Log in to the TeamUp business dashboard as owner/admin
- [ ] Go to **Settings → Integrations → API Integration**
- [ ] Open the existing application:
  - If you see **Get Started**, follow that only if no application exists yet
  - If one already exists (likely, from the original setup): **Options → Manage Applications** (or **View and Update Applications**) and open it
- [ ] Scroll to **M2M Tokens** and click **Add**
- [ ] Set an **expiry** and **permissions**
  - Permissions must be **Provider / admin** (staff / whole-business access), **not** customer-scoped
  - Customer-scoped would only see your own profile, not the full member list
  - A long expiry (or no expiry, if offered) is fine — we can revoke it later
- [ ] Click **Generate Token**
- [ ] **Copy the token immediately** and store it somewhere safe

**Important:** TeamUp shows this token **once**. If you leave the screen without copying it, you cannot view it again — you would have to delete it and generate a new one.

---

## How to send it to Lee

Treat this the same way as the original client secret.

- **Do not** send it over ordinary email or a plain text / WhatsApp message
- Prefer a **password-manager share**, or read it aloud / in person

This token can read the member list. Treat it as sensitive as a password.

---

## If something looks wrong

TeamUp allows **up to two** M2M tokens per application. You can revoke or rotate them later from the same screen. Nothing here is permanent, and it is not risky to generate one and replace it if needed.

When Lee has the token stored, you are done.
