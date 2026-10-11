# Magzi wire contract (mobile + cockpit)

Source: `magzi-agent` @ `origin/main` 4c35dcf. Derived from `crates/magzid/src/{mobile_server.rs, mobile_server/*.rs, cockpit_server.rs, admin_server.rs, cockpit.rs}` and the `magzi_core` serializers they call. Code wins over `docs/mobile-api.openapi.yaml` where they differ.

Notation: TypeScript-ish. `ms` = Unix epoch milliseconds (i64). `T | null` = key always present, may be null (Rust `Option` with no `skip_serializing_if`). `k?:` = key may be absent. Tuples `[a, b]` = serde tuple → JSON array.

---

## 0. Cross-cutting rules

### Mobile API (`/mobile/v1/*`)
- Bind: `mobile.host:mobile.port` (default port **8766**). Plain HTTP (Tailscale/private). Disabled unless `mobile.enabled`.
- Auth header: `Authorization: Bearer <token>`. Exact parsing (`mobile_server.rs`):
  ```rust
  headers.get("authorization")...strip_prefix("Bearer ").map(|s| s.trim().to_string())
  ```
  Case-sensitive `Bearer ` prefix. Token is opaque (keep it in the Keychain). Server stores only a hash. TTL `mobile.tokenTtlSecs`, default 30 days. Every authed call bumps `session.lastSeenAtMs`.
- A token is rejected (401) when unknown, revoked, expired, or the user is disabled.
- Roles (`MobileUserRole`, lowercase): `"admin" | "family" | "user" | "guest"`. "Admin only" routes return 403. Household routes also use a separate **household role** (owner/adult/teen/child/carer/guest/housemate), worked out from the linked person's membership (`actor_from_mobile`). An unlinked login acts as household role `"guest"`.
- Error body: always `{ "error": string }`.
  - 401 `{"error":"unauthorized"}`
  - 500 `{"error":"internal"}` from mobile-store failures. Core-store failures return 500 `{"error":"<message>"}`.
  - Household/core errors (`ApiError`): status from the core (400/403/404/409/500) and `{"error": message}`. 403 messages are human sentences, e.g. `"✋ Approvals are for adults."`.
- Request bodies are read with axum `Json<…>`. You **must** send `Content-Type: application/json`. Otherwise axum rejects before the handler runs: 415, or 400/422 for bad JSON, with a **plain-text** body (not `{error}`). Unknown keys are ignored. Missing keys default to `""`, `false` or the documented default.
- Path `:id` declared `i64` (items, approvals, memory notes, places, timeline episodes): a non-numeric id returns a plain-text 400 from axum.
- Household id = WhatsApp group JID (e.g. `"1203...@g.us"`). URL-encode it in paths.
- Timestamps in bodies are `ms` everywhere except: the WS envelope `timestamp` (RFC 3339 string), `Grant.grantedAt`, capability timestamps and audit `time` (strings).

### Cockpit API (`/api/*`, `/metrics/usage`, `/ws`)
- Bind: `admin.host:admin.port` (default port **8765**). Disabled unless `admin.enabled`. Any other GET path serves the embedded SPA (`index.html` fallback).
- Single principal: the owner. No roles.
- Auth header: `Authorization: Bearer <token>`, same parser as mobile. The token is 256-bit hex (64 chars) from `AdminAuth::verify_otp`. Tokens are kept **in memory only**, so a daemon restart invalidates them. TTL `admin.tokenTtlSecs`, default 3600 s (clamped 60–86400).
- `require_auth!` → 401 `{"error":"unauthorized"}`.
- Error body: `{ "error": string }`.

---

## 1. Mobile shared types

```ts
type MobileUser = {            // magzi_core::mobile::MobileUser, camelCase
  userId: string; email: string; displayName: string;
  role: "admin"|"family"|"user"|"guest";
  scopes: string[];            // e.g. ["chat"], admin seed ["chat","admin"]
  createdBy: string; createdAtMs: ms; disabledAtMs: ms | null;
}
type MobileSession = {
  sessionId: string; userId: string; deviceId: string; deviceName: string;
  createdAtMs: ms; lastSeenAtMs: ms; expiresAtMs: ms; revokedAtMs: ms | null;
}
type MobileMessage = {         // app chat row
  messageId: string;           // "in:<clientMessageId>" | "out:<opaque id>"
  conversationId: string;      // "mobile:<userId>"
  userId: string; direction: "in"|"out"; text: string; createdAtMs: ms;
}
type Person = { person_id: string; display_name: string }   // NOTE: snake_case (no rename_all)
type Group = {                 // neuro::store::Group, camelCase, ALL fields always present
  id: string; name: string; enabled: boolean; intensity: string; quietHours: string;
  morningAt: string; eveningAt: string; weeklyReset: string; pausedUntil: ms;
  lastUnsolicitedAt: ms; lastCaptureAt: ms; lastConsideredAt: ms; dayKey: string; dayCount: number;
  lastMorning: string; lastEvening: string; lastWeekly: string; configHash: string;
  lastActivityAt: ms; createdAt: ms; coupleCheckin: string; bodyChecks: string;
  lastCouple: string; lastBody: string; nightBefore: string; lastNightBefore: string;
  incidentUntil: ms; incidentNote: string; allclearPending: boolean; lowPowerDay: string;
  tone: string; kind: string; timezone: string; ownerPersonId: string;
  profileFile: string; calendarGrant: string;
}
type Item = {                  // neuro::store::Item, camelCase
  id: number; kind: string /* "task"|"shopping"|"decision"|"checkin"|"project"|"idea"|… */;
  title: string; owner: string; status: string /* "open"|"done"|"dropped"|"likely"|"past"|"someday"|"merged"|… */;
  dueAt: ms | null; dueHasTime: boolean; remindAt: ms | null; reminded: boolean;
  firstStep: string; estimateMin: number | null; energy: string; notes: string;
  createdBy: string; createdAt: ms; updatedAt: ms; doneAt: ms | null; snoozedUntil: ms;
  warnedStage: number; area: string; repeat: string; rotate: boolean; private: boolean;
  leadMin: number | null; projectId: number | null;
}
type Fact = { key: string; label: string; value: string; updatedAt: ms }
type Note = { id: number; about: string; text: string; privateTo: string; source: string; createdAt: ms }
type Approval = {
  id: number; householdId: string; kind: string; summary: string; preview: string;
  requestedBy: string; requestedByRole: string; expires: ms;
  status: "pending"|"approved"|"denied"|string; decision: string; decidedBy: string;
}
type HouseholdEvent = {
  cursor: number; householdId: string;
  personId: string;            // actually the mobile userId of the writer
  kind: string;                // "item.changed" (only writer in the mobile server)
  payload: string;             // JSON-ENCODED string, e.g. "{\"item\":{...}}"
  idempotencyKey: string; at: ms;
}
type ThreadLine = { id: number; speaker: string; text: string; at: ms; fromMagzi: boolean; channel: string }
type ThreadMessage = {         // person thread (merged app + WhatsApp)
  messageId: string;           // app ids as above; WhatsApp "wa:<n>" or the stored message id
  conversationId: string;      // "person:<personId>"
  channel: "whatsapp"|"app"; direction: "in"|"out"; text: string; createdAtMs: ms;
}
type Invite = { code: string; householdId: string; name: string; role: string; personId: string; expiresAt: ms; link: string /* "magzi://invite/<code>" */ }
type Membership = { householdId: string; personId: string; name: string; role: string; state: string; joinedAt: ms; leftAt: ms }
type LeaveReport = { householdId: string; personId: string; name: string; state: string; membersRemoved: number; waRevoked: string[]; sessionsRevoked: number; approvalsCancelled: number[] }
type Honesty = { known: number; due: number; knownRate: number; wrong: number; inferred: number; wrongRate: number;
  kinds: { kind: string; wrong: number; total: number; demoted: boolean }[] }
type DriverMetrics = { pokes: number; acted: number; rate: number; stuck: number[];
  people: { name: string; today: number; cap: number; maxDay: number }[];
  groupToday: number; stage3: number; capBreaches: number; rescheduled: number; rotated: number; parked: number }
type TimeLine = { key: string; label: string; actualMin: number; plannedMin: number; changeMin: number | null }
type Sharing = {               // context::store::Sharing, camelCase, #[serde(default)]
  location: boolean; activity: boolean; workouts: boolean; proximity: boolean;
  presenceVisibleTo: "" | "self" | "adults" | "household";
  sharePlaceNames: boolean; shareWins: boolean; skipSensitive: boolean;
  liveLocation: boolean; selfWins: boolean; reflection: boolean;
} // defaults: everything false/"" except skipSensitive=true, selfWins=true
```

---

## 2. Mobile routes (59)

`A` = Bearer required. `ADM` = `MobileUserRole::Admin` required (403 otherwise).

### Auth / account

**1. POST `/mobile/v1/login/request`** (no auth)
- Body: `{ email?: string; phone?: string }`. A non-empty `phone` takes precedence (WhatsApp OTP route).
- 200 (always, so the server does not reveal whether an account exists):
  - phone known: `{ accepted: true, identifier: "phone", message: "A login code was sent to your WhatsApp." }`
  - phone unknown: `{ accepted: true, message: "If this number is a household member, a login code was sent on WhatsApp." }`
  - email (valid, invalid or unknown): `{ accepted: true, message: "If this email is enabled for Magzi, a login code was sent." }`
- 500 `{error:"internal"}`.
- The code is 6 digits. It expires after `otpTtlSecs` (default 300 s) and is throttled to one per `otpMinIntervalSecs` (default 60 s) per email. A throttled request still returns 200 but sends nothing.

**2. POST `/mobile/v1/login/verify`** (no auth)
- Body: `{ email?: string; phone?: string; code: string; deviceId?: string; deviceName?: string /* default "iPhone" */ }`.
- Phone login verifies against the pseudo-email `format!("{digits}@member.magzi")`, where `digits = phone.trim().replace('+', "")`. Send the phone exactly as in the request step.
- An empty or invalid `deviceId` is replaced by a server-generated `dev…` id. `deviceName` is truncated to 80 characters.
- 200 `{ token: string; user: MobileUser; session: MobileSession }`
- 401 `{error:"unauthorized"}`: wrong, expired or consumed code, or 5 or more failed attempts on that code.
- 500.

**3. GET `/mobile/v1/bootstrap`** A
```ts
{ server: "magzid";
  mode: "ShadowReadonly"|"StagingActive"|"ProductionActive";   // Rust Debug format, NOT kebab
  user: MobileUser; session: MobileSession;
  features: { chat: true; alerts: true; approvals: true; push: boolean /* mobile.push.apnsEnabled */ } }
```

**4. GET `/mobile/v1/me`** A → `{ user: MobileUser; person: Person | null }`. `person` uses snake_case keys.

**5. GET `/mobile/v1/users`** A ADM → `{ users: MobileUser[] }`. 403 `{error:"admin required"}`.

**6. POST `/mobile/v1/users`** A ADM
- Body: `{ email: string; displayName?: string /* default email */; role?: "admin"|"family"|"user"|"guest" /* default "user"; unknown→"user" */; scopes?: string[] /* default ["chat"] */ }`
- 200 `{ user: MobileUser }`. 400 `{error:<store message>}` (e.g. invalid or duplicate email). 403 `{error:"admin required"}`.

**7. POST `/mobile/v1/users/disable`** A ADM
- Body `{ userId: string }`. 400 `{error:"userId required"}`.
- 200 `{ changed: boolean; waRevoked: string[] }` (WhatsApp allow-list entries revoked).

**8. GET `/mobile/v1/sessions`** A → `{ sessions: MobileSession[] }` (own sessions only, newest `lastSeenAtMs` first).

**9. POST `/mobile/v1/me/devices`** A (push registration)
- Body `{ token: string; platform?: string /* default "ios" */ }`. 400 `{error:"token is required"}`.
- 200 `{ ok: true }`.

**10. PATCH `/mobile/v1/me/preferences`** A
- Body (all optional):
  - `brief`: `"on"|"off"|"default"|"HH:MM"|boolean|null`
  - `quietHours`: `"HH:MM-HH:MM"|""`
  - `channel`: `""|"whatsapp"|"app"`
  - `timeShare`: `boolean`
  - `pokeStyle`: `"gentle"|"direct"|"playful"|"quiet"`
  - `pokesPerDay`: integer 0–5
  - `adminRound`: `boolean`
  - `pokeOptionsOnly`: `boolean`
- 200:
```ts
{ quietHours: string; channel: string; brief: { enabled: boolean; at: string /* "" = default time */ };
  pokes: { pokeStyle: string; pokesPerDay: number; adminRound: boolean; pokeOptionsOnly: boolean;
           learnedFormat: string; learnedHour: number | null } | null;   // null if the login is not linked
  timeShare: boolean }
```
- 400 `{error:"brief must be on, off, default or HH:MM"}`, `"quietHours must be HH:MM-HH:MM"`, `"channel must be whatsapp or app"`, `"timeShare must be true or false"`, `"pokeStyle must be gentle, direct, playful or quiet"`, `"pokesPerDay must be 0 to 5"`, `"adminRound must be true or false"` or `"pokeOptionsOnly must be true or false"`.
- 409 `{error:"link this app login to your WhatsApp first (send the link code)"}` when the login has no linked person. The brief step always needs the link.

**11. GET `/mobile/v1/me/memory`** A
```ts
{ linked: boolean; personId: string /* "" if unlinked */;
  notes: { id: number; householdId: string; household: string; about: string; text: string; private: boolean; savedAt: ms }[];
  facts: { householdId: string; label: string; value: string; updatedAt: ms }[] }
```

**12. DELETE `/mobile/v1/me/memory/:id`** A → `{ ok: true }`. 404 `{error:"note not found"}`.

**13. PATCH `/mobile/v1/me/memory/:id`** A
- Body `{ text: string }`.
- 200 `{ note: Note }`. 400 `{error:"text is required"}`. 404 `{error:"note not found"}`.

**14. GET `/mobile/v1/me/activity`** A → `{ activity: { at: ms; what: string; why: string; household: string }[] }` (up to 50; `[]` if unlinked).

**15. GET `/mobile/v1/me/time`** A
- Query `?week=YYYY-Www` (an invalid value falls back to this week).
- 200:
```ts
{ week: string; from: ms; to: ms; lines: TimeLine[]; actualMin: number; plannedMin: number;
  share: boolean; household: { members: string[]; lines: TimeLine[] } | null }
```
- 409 if not linked. 404 `{error:"no time ledger for this person"}`.

### Chat

**16. GET `/mobile/v1/conversations/:id/messages`** A
- `:id = "mobile:<ownUserId>"`, otherwise 403 `{error:"not your conversation"}`.
  - Query `?limit` (default 50, clamped 1–200) and `?before=<i64>`.
  - **`before` is the internal SQLite row id, which no response exposes, so paging the app chat this way is effectively UNKNOWN/unusable.** Use the `person:` form to page by time.
  - 200 `{ messages: MobileMessage[] }`, newest first.
- `:id = "person:<personId>"` (only your own linked person, otherwise 403 `{error:"not your conversation"}`):
  - Query `?before=<ms>` (time cursor) and `?limit` (default 50, 1–200).
  - 200 `{ messages: ThreadMessage[] }`, newest first, app and WhatsApp private chat merged.

**17. POST `/mobile/v1/messages`** A
- Body `{ text: string /* required, trimmed */; clientMessageId?: string /* default "client-missing" */ }`.
- 202:
  ```ts
  { accepted: true; clientMessageId: string; serverMessageId: string /* "in:<clientMessageId>" */;
    conversationId: string /* "mobile:<userId>" */; status: "queued" }
  ```
- 400 `{error:"text required"}`. 401 if disabled. 500.
- **conversationId format for app chat: `mobile:<userId>`.**
- Message ids are globally keyed `in:<clientMessageId>`, so use a UUID. A retry with the same id returns the same stored row. The server still re-queues the turn and re-emits `message.accepted`; any downstream dedupe is UNKNOWN.
- The reply arrives on the WS as `typing` → `message.delta`* → `message.done`.

**18. GET `/mobile/v1/ws`** A (WebSocket) — see §3.

### Households

**19. GET `/mobile/v1/households`** A → `{ households: Group[] }`. Admin users see every enabled group. Other users see the groups where a member with their `displayName` is in the chat or shares load.

**20. GET `/mobile/v1/households/:id/items`** A
- Query `?view=open|mine|shopping|decisions` (default `open`; anything else returns all open items).
- 200 `{ items: Item[] }`. 403 (household role lacks UseSharedList). 404 `{error:"household not found"}`.

**21. POST `/mobile/v1/households/:id/items`** A (capture)
- Optional header `Idempotency-Key: <string>`.
- Body `{ title: string; kind?: string /* default "task" */ }`.
- 201 `{ item: Item }`. A replayed `Idempotency-Key` returns 200 with the stored first body.
- 400 `{error:"title is required"}`. 403.

**22. PATCH `/mobile/v1/items/:id`** A
- Body `{ householdId: string; action: "done"|"drop"|"claim" }`.
- 200 `{ item: Item }`.
- 400 `{error:"action must be done, drop or claim"}`. 403 (a child acting on another person's item). 404 `{error:"item not found"}`.

**23. POST `/mobile/v1/items/:id/swap`** A
- Body `{ householdId: string; to: string }`.
- 200 `{ item: Item; message: string }`. 400 `{error:"to is required"}`. 404.

**24. POST `/mobile/v1/items/:id/skip`** A
- Body `{ householdId: string }`.
- 200 `{ item: Item | null; message: string }`. 404 (also when the item is private or not open).

**25. POST `/mobile/v1/items/:id/reopen`** A
- Body `{ householdId: string }`.
- 200 `{ item: Item | null; wrongInference: boolean; kind: string }`.
- 404 `{error:"household not found"|"item not found"}`. 403. 409 `{error:<reason>}`.

**26. POST `/mobile/v1/items/:id/progress`** A
- Body `{ householdId: string; action: "drop"|"park"|"schedule"|"delegate"|"reopen"; to?: string /* delegate */; when?: string /* schedule, e.g. "sat 10:00" */ }`. The server reads `to`, then `when`, as one argument.
- 200 `{ item: Item }`.
- 400 `{error}` (e.g. `"unknown action X: use drop, park, schedule, delegate or reopen"`, `"give a date, e.g. \"sat 10:00\""`, `"say who to hand it to"`). 403. 404.

**27. GET `/mobile/v1/households/:id/facts`** A → `{ facts: Fact[] }`. 403.

**28. POST `/mobile/v1/households/:id/facts`** A
- Body `{ label: string; value: string }`.
- 200 `{ ok: true }`. 403.

**29. GET `/mobile/v1/households/:id/rota`** A
```ts
{ rota: { people: string[];
          week: { person: string; chores: { itemId: number; title: string; due: ms }[] }[];
          waiting: { id: number; itemId: number; title: string; by: string; at: ms }[] } }
```
- 403. 404.

**30. GET `/mobile/v1/households/:id/events`** A
- Query `?since=<cursor>` (default 0; returns `cursor > since`, ascending).
- 200 `{ events: HouseholdEvent[] }`. There is no membership check.

**31. GET `/mobile/v1/households/:id/meals`** A
```ts
{ plan: { day: string; meal: string; cook: string; quick: boolean }[];
  saved: { name: string; ingredients: string[]; quick: boolean }[] }
```

**32. GET `/mobile/v1/households/:id/bills`** A
```ts
type BillView = { id: number; title: string; kind: string; amount: string; payer: string; due: ms | null; repeat: string }
{ bills: BillView[]; renewals: BillView[] }
```

**33. GET `/mobile/v1/households/:id/summary/latest`** A
- 200 binary `application/pdf`, with `Content-Disposition: inline; filename="week-<YYYY-Www>.pdf"`.
- 404 `{error}` when no summary exists yet. 403.

**34. GET `/mobile/v1/households/:id/thread`** A
- Query `?before=<lineId>&limit=50` (1–200).
- 200 `{ lines: ThreadLine[] }`, newest first.
- 404 `{error:"household not found"}`. 403 `{error:"only the household's members can read its chat"}`.

**35. POST `/mobile/v1/households/:id/thread`** A
- Body `{ text: string; clientMessageId?: string /* default server "c…" id */ }`.
- 202 `{ accepted: true; messageId: string /* "app:<clientMessageId>" */; line: string /* "💬 <Name> (app): <text>" */ }`.
- Retried id: 202 `{ accepted: true; duplicate: true; messageId: string }`.
- 400 `{error:"text required"}`. 401 (disabled). 403. 404. 409 `{error:"link this app login to your WhatsApp first (send the link code)"}`.

**36. GET `/mobile/v1/households/:id/reality`** A
- Query `?week=YYYY-Www` (default: the report week).
- 200:
```ts
type Act = { action: "drop"|"delegate"|"schedule"|"reopen"; method: "POST"; path: string; needs?: "to"|"when" }
{ week: string; from: ms; to: ms;
  household: { planned: number; done: number; confirmed: number; likely: number; moved: number; past: number;
               unknown: number; upcoming: number; slipping: number; parked: number; merged: number };
  people: { name: string; planned: number; done: number }[];
  fairLoad: { chores: [string, number][]; runs: [string, number][] };
  inferred: { itemId: number; title: string; status: string;
              evidence: { kind: string; label: string; strength: string; reason: string; person: string; at: ms };
              undo: { method: "POST"; path: string /* "/mobile/v1/items/<id>/reopen" */ } }[];
  slipping: { itemId: number; title: string; owner: string; days: number; actions: Act[] }[];
  parked: { itemId: number; title: string; actions: Act[] }[];
  honesty: Honesty;
  driver: { metrics: DriverMetrics;
            items: { itemId: number; title: string; owner: string; nextAction: string; startBy: ms;
                     lead: { days: number; source: string; why: string }; stage: number /* -1 none */;
                     pokes: number; noPoke: boolean }[] } }
```
- 404. 403 `{error:"only the household's members can see its progress"}`.

**37. GET `/mobile/v1/households/:id/presence`** A
- 200 `{ presence: { name: string; state: string; asOf: ms | null }[] }`.
- 400 `{error:"household id"}`. 403 `{error:"Not a member of this household."}`. 409 (not linked).

### Approvals

**38. GET `/mobile/v1/households/:id/approvals`** A → `{ approvals: Approval[] /* pending only */; features: { approvals: true } }`. There is no membership check.

**39. POST `/mobile/v1/approvals/:id/approve`** and **40. POST `/mobile/v1/approvals/:id/deny`** A (no body)
- 200 `{ approval: Approval }`. An approval that is no longer pending is returned unchanged.
- 403 `{error:"✋ Approvals are for adults."}`: non-admin users are mapped to role `"guest"`, so effectively only `role:"admin"` can decide.
- 404 `{error:"approval not found"}`. 500.

### Membership (HH-6)

**41. POST `/mobile/v1/households/:id/invites`** A (admin user, or household role allowed to manage members)
- Body `{ name: string; role: string; phone?: string; email?: string }` (phone wins).
- 201 `{ invite: Invite }`. The code is valid for 7 days.
- 400 `{error}` (`"name is required"`, `"there is only one owner"`, `"no such household"`, …). 403 `{error:<refuse line>}`.

**42. POST `/mobile/v1/invites/accept`** A
- Body `{ code: string }`.
- 200 `{ household: { id: string; name: string }; membership: Membership }`.
- 400 `{error:"code required"}` or `{error:"That invitation code isn't one I issued."}` / `{error:"That invitation has already been used or it expired — ask for a new one."}`.

**43. POST `/mobile/v1/households/:id/leave`** A (no body)
- 200 `{ left: LeaveReport }`.
- 400 `{error:"this login isn't linked to a household member"}`.

**44. POST `/mobile/v1/households/:id/members/remove`** A (admin or manager)
- Body `{ personId: string }`.
- 200 `{ removed: LeaveReport }`.
- 400 `{error:"personId required"}`. 403 `{error:"the owner can't be removed"}` or the refuse line.

### Admin (mobile)

**45. GET `/mobile/v1/admin/status`** A ADM (403 `{error:"admin only"}`)
```ts
{ status: { startedAt: ms|null; uptimeMs: number|null; whatsappConnectedSince: ms|null; whatsappState: string;
            lastInboundAt: ms|null; lastOutboundAt: ms|null; llmProvider: string; deadLettersToday: number;
            households: { householdId: string; name: string; tokensToday: number; budget: number }[];
            lastBackupOkAt: ms|null;
            latency: { path: string; turns: number; queueP95Ms: number; readyP95Ms: number; totalP95Ms: number; budgetMs: number }[];
            pairingQrPending: boolean };
  text: string;                                                         // human status text
  honesty: { householdId: string; name: string; honesty: Honesty }[];
  driver: { group: string; name: string; driver: DriverMetrics }[] }     // houseshares excluded
```

**46. POST `/mobile/v1/admin/pause`** A ADM
- Body `{ on?: boolean /* default true */; hours?: number /* default 12, clamp 0.25–336 */ }`.
- 200 `{ paused: boolean; until: ms /* 0 when resumed */; groups: string[] }`.

**47. GET `/mobile/v1/admin/qr`** A ADM → `{ pairing: { qr: string; at: ms } | null; whatsappState: string }`.

### Ambient context (workstream 18)

Context errors (`Refused`):
- 409 when the login is not linked: `{error}` message about linking.
- 403 for a guest (`"Guests don't share location with Magzi."`) or a switch that is off (`"<Location|Activity|Workout|Live location|Presence> sharing is off; nothing was stored."`).
- 400 for bad input.

Ingest responses: `type Report = { inserted: number; updated: number; duplicates: number; rejected: number }`. Malformed rows are counted in `rejected`. Each batch holds at most 1000 rows (400 above that).

**48. POST `/mobile/v1/me/context/visits`** A
- Body `{ visits: { clientId: string; lat: number; lng: number; arrivedAt: ms /* alias "at" */; departedAt?: ms|null; source?: string }[] }`.
- 200 `Report`. 400 `{error:"visits must be an array"}`.

**49. POST `/mobile/v1/me/context/activities`** A
- Body `{ activities: { clientId: string; kind: string; at: ms /* alias "startedAt" */ }[] }`.
- 200 `Report`.

**50. POST `/mobile/v1/me/context/workouts`** A
- Body `{ workouts: { clientId: string; kind: string; startedAt: ms; endedAt: ms; calories?: number|null }[] }`.
- 200 `Report`.

**51. POST `/mobile/v1/me/context/location`** A
- Body `{ lat: number; lng: number; expiresAt: ms; at?: ms }`.
- 200 `{ ok: true; expiresAt: ms }`.
- 400 `{error:"lat and lng are required"}` or `{error:"expiresAt is required (live window only)"}`. Per the OpenAPI doc, `expiresAt` must be at most 2 h ahead.

**52. POST `/mobile/v1/me/context/presence/heartbeat`** A
- Body `{ state: "home"|"away"|"moving"|"work"|"school"|"gym"; at?: ms }`.
- 200 `{ ok: true; state: string /* normalized */ }`.

**53. GET `/mobile/v1/me/context/sharing`** A → `{ sharing: Sharing }`.

**54. PUT `/mobile/v1/me/context/sharing`** A
- Body `Sharing`. Missing keys take the **defaults**, not the stored values, so always send the full object. A guest is forced to the defaults.
- 200 `{ sharing: Sharing; personId: string }`.

**55. GET `/mobile/v1/me/places`** A
```ts
type PlaceView = { id: number; name: string; kind: string /* "home"|"work"|…|"sensitive" */; shared: boolean; mine: boolean; learned: boolean; confirmed: boolean; visits: number }
{ places: PlaceView[] }
```

**56. PUT `/mobile/v1/me/places/:id`** A
- Body `{ name?: string; kind?: "home"|"work"|"school"|"gym"|"restaurant"|"cafe"|"shop"|"gp"|"family"|"other"|"sensitive"; shared?: boolean }`.
- 200 `{ place: PlaceView }`.
- 400 `{error:"unknown place kind"}` or `{error:"This place stays private."}`. 403. 404 `{error:"place not found"}`.

**57. GET `/mobile/v1/me/timeline`** A
- Query `?day=YYYY-MM-DD` (default today in the person's timezone).
- 200:
```ts
{ day: string;
  episodes: { id: number; kind: string; label: string; startedAt: ms; endedAt: ms|null; place: string; placeKind: string;
              with: string[]; confidence: number; confirmed: boolean }[];
  visits: { arrivedAt: ms; departedAt: ms|null; place: string; placeKind: string }[] }
```
- 400 `{error:"day must be YYYY-MM-DD"}`.

**58. POST `/mobile/v1/me/timeline/:id/confirm`** A → `{ ok: true }`. 404 `{error:"episode not found"}`.

**59. POST `/mobile/v1/me/timeline/:id/correct`** A
- Body `{ kind: "gym"|"eating_out"|"at_work"|"at_school"|"school_run"|"errand"|"commute"|"home"|"away"|"sensitive"; placeName?: string }`.
- 200 `{ episode: { id: number; kind: string; confirmed: boolean } }`.
- 400 `{error:"unknown episode kind"}`. 404.

---

## 3. Mobile WebSocket `GET /mobile/v1/ws`

- Auth is the **Authorization header only**, never the query string:
  ```rust
  // MOB-1: the token moves to the Authorization header — never in the URL.
  let Some(tok) = bearer(&headers) else { return unauth(); };
  let Ok(Some(ctx)) = shared.store.check_bearer(&tok, now_ms()) else { return unauth(); };
  ```
  On iOS use `URLRequest` with `Authorization: Bearer <token>` and `URLSessionWebSocketTask(with: request)`. A bad token gets HTTP 401 `{"error":"unauthorized"}` before the upgrade.
- All server frames are **text JSON**.
- The server sends no pings and no heartbeats. Client frames (text, ping, anything) are read and ignored; tungstenite answers Ping with Pong automatically. A close or error ends the loop.
- If the broadcast channel (capacity 1024) lags, events are **silently dropped**. Backfill through the REST history after a reconnect.
- The first frame after connect:
  ```json
  {"type":"connection.ready","userId":"<userId>"}
  ```
- Every other frame uses this envelope. Only events whose owner `user_id` matches this socket's user are delivered.
  ```ts
  { type: string; conversationId: string; payload: object; cursor: 0 /* always 0 in current code */; timestamp: string /* RFC3339 send time, e.g. "2026-10-10T09:00:00.123456789+00:00" */ }
  ```

| `type` | `conversationId` | `payload` |
|---|---|---|
| `message.accepted` | `mobile:<userId>` | `{ messageId: "in:<clientMessageId>", text: string, direction: "in" }` |
| `typing` | turn conversation id (`mobile:<userId>`) | `{ state: "composing" \| "paused" }` |
| `message.delta` | `mobile:<userId>` | `{ delta: string, round: number /* ≥1, one per model call */, seq: number /* monotonic per turn */ }` |
| `message.done` (reply) | `mobile:<userId>` | `{ messageId: "out:…", text: string, direction: "out", createdAtMs: ms }` |
| `message.done` (proactive) | `mobile:<userId>` | `{ messageId, text, direction: "out", createdAtMs, proactive: true, meta: { source: "neuro_helper", kind: string, householdId: string, proactive: true } }` |
| `thread.line` | householdId | `{ householdId: string, line: ThreadLine }` |
| `reality.changed` | householdId | `{ householdId: string }`. Refetch `/households/:id/reality`. |
| `person.line` | `person:<pid>` | `{ line: Message }` — a WhatsApp line (`channel: "whatsapp"`, `direction: "in"|"out"`) in my own private chat, same shape as `/conversations/person:<pid>/messages` rows. Upsert into the unified thread. |

Delta semantics:
- Within a round, the deltas in `seq` order concatenate to that model call's text.
- A new `round` replaces the preview.
- Placeholders like `<PARTNER_1>` show as `…`.
- `[SILENT]` replies never stream.
- `message.done` carries the authoritative final text.

`thread.line`, `reality.changed` and `person.line` are polled server-side every 3 s. They go to the household's linked app users whose role is not child or guest.

Example delta frame:
```json
{"type":"message.delta","conversationId":"mobile:usr_ab12","payload":{"delta":"Sure — ","round":1,"seq":3},"cursor":0,"timestamp":"2026-10-10T09:00:01.5+00:00"}
```

---

## 4. Cockpit routes (21)

**C1. POST `/api/login`** (no auth, no body)
- 200 `{ sent: boolean }`, or `{ sent: true; throttled: true }` when within 15 s of the last code.
- The 5-minute code is delivered to the owner over the primary channel (WhatsApp), not in the response.

**C2. POST `/api/verify`** (no auth)
- Body `{ code: string }`.
- 200 `{ token: string /* 64 hex */ }`.
- 401 `{error:"invalid or expired code"}`. 429 `{error:"too many attempts; try again later"}` (lockout for 5 min after 5 consecutive failures).

**C3. POST `/api/logout`** (Bearer optional; revokes the token if present) → `{ ok: true }`.

**C4. GET `/api/state`** A
```ts
{ agentProfile: "personal"|"family"|"front-desk"|"coworker"|string;   // NOTE: key is agentProfile; there is NO "profile" key
  mode: "ShadowReadonly"|"StagingActive"|"ProductionActive";           // Debug format
  ownerId: string;
  primaryChannel: string | null;
  paused: boolean;
  features: { name: string; state: "on"|"off"|"attention"; note: string }[];
     // names include "WhatsApp channel","Telegram channel","Email","Conversational memory (STM/MTM)",
     // "Long-term memory (knowledge graph)","Knowledge base (RAG)","Embeddings","External tools (MCP)"
  allowlist: string[];
  allowlistGrants: { [recipient: string]: { reason: string; grantedAt: string }[] };
  whatsappSends: { lastHour: { all: number; proactive: number; ceiling: number };
                   lastDay:  { all: number; proactive: number; ceiling: number } } | null;
  capabilities: CapabilityRecord[];                // includes disabled ones
  honesty: { householdId: string; name: string; honesty: Honesty }[];
  config: object | null }                          // raw config.json as on disk (camelCase keys); null if unreadable/not JSON

type CapabilityRecord = {
  id: string; toolName: string; extensionPath: string;
  status: "draft"|"validation_failed"|"validated"|"approval_required"|"approved"|"active"|"disabled";
  createdAt: string; validatedAt: string|null; sourceUserNeed: string;
  riskLevel: "low"|"medium"|"high";
  checksum: string; sourceChecksum: string; validatedChecksum: string|null; activatedChecksum: string|null;
  approvedAt: string|null; approvedBy: string|null; approvalReason: string|null; approvalRecordId: string|null;
  activatedAt: string|null }
```
The full `config` shape is UNKNOWN. It is whatever `config.json` holds; there is no fixed schema in the handler.

**C5. GET `/api/usage`** A
- Query `?limit` (default 50, 1–500).
- 200 `{ summary: UsageSummary; recent: UsageRecord[] /* == summary.recent */; host: HostMetrics }`.
```ts
type UsageRecord = { at: ms; channel: string; conversationId: string; provider: string; model: string;
  inputTokens: number; outputTokens: number; totalTokens: number; iterations: number;
  status?: string; cacheReadTokens?: number; cacheWriteTokens?: number; costTotal?: number;
  errorKind?: string; errorMessage?: string; contextBreakdown?: [string, number][];
  codeMode?: boolean; coreToolCount?: number; personId?: string; householdId?: string }   // ? = skip_serializing_if None
type UsageSummary = { turns: number; inputTokens: number; outputTokens: number; totalTokens: number;
  avgContextTokens: number; maxContextTokens: number;
  byProvider: [string /*provider*/, number /*turns*/, number /*totalTokens*/][];
  byModel: [string /*"provider/model"*/, number /*turns*/, number /*totalTokens*/][];
  byHousehold: { household: string; turns: number; totalTokens: number; costTotal: number; people: number }[];
  costTotal: number; recent: UsageRecord[] }
type HostMetrics = { memTotalMb: number; memUsedMb: number; memAvailableMb: number; memUsedPct: number; procRssMb: number;
  cpuCores: number; load1: number; load5: number; load15: number; cpuLoadPct: number }   // 0 when /proc missing
```

**C6. GET `/api/sessions`** A
- Query `?limit` (default 60, 1–500).
- 200 `{ sessions: { conversation: string; lastInput: string; lastReply: string; ts: ms; turns: number }[]; count: number }`.

**C7. GET `/api/session`** A
- Query `?conversation=<id>` (required, otherwise 400 `{error:"conversation required"}`) and `&limit` (default 200, 1–2000).
- 200:
```ts
{ conversation: string;
  pages: { input: string; reply: string; ts: ms; summary: string|null }[];
  events: AuditFrame[];          // WITHOUT "source" key
  usage: { at: ms; provider: string; model: string; inputTokens: number; outputTokens: number; totalTokens: number;
           cacheReadTokens: number|null; iterations: number; status: string|null; contextBreakdown: [string,number][]|null;
           codeMode: boolean|null; coreToolCount: number|null; costTotal: number|null }[] }
type AuditFrame = { time: string /* audit created_at */; session: string|null; run: string|null; scope: string; action: string;
                    status: "ok"|"error"|"skipped"; summary: string }
```

**C8. GET `/api/watch`** A
- Query `?session&run&scope&errors=1|true&limit` (default 50, 1–500).
- 200 `{ events: (AuditFrame & { source: "audit" })[]; count: number }` (most recent, oldest first).

**C9. POST `/api/allow`** and **C10. POST `/api/deny`** A
- Body `{ recipient: string }`.
- 200 `{ changed: boolean; allowlist: string[] }`.
- 400 `{error:"recipient required"}`. 500.

**C11. POST `/api/pause`** A
- Body `{ on?: boolean /* default false */ }`.
- 200 `{ paused: boolean }`.

**C12. POST `/api/capability`** A
- Body `{ tool: string; action: "disable" }`.
- 200 `CapabilityRecord` (bare, not wrapped).
- 400 `{error:"tool + action=disable required"}` or a store error. 500.

**C13. POST `/api/config`** A
- Body `{ key: string; value: any }`. Only these keys are allowed:
  - `"timezone"` (an IANA zone)
  - `"agentProfile"` (`personal|family|front-desk|coworker`)
  - `"turnConcurrency"` (1–16)
  - `"updateCheck.intervalHours"` (1–168)
  - `"backups.retentionDays"` (1–365)
- 200 `{ ok: true; restartRequired: true; rollbackHash: string }`.
- 400 `{error:"key + value required"}` or `{error:"unknown, wrong-type or risky key: explicit operator-reviewed config change required"}` (and others).

**C14. POST `/api/config/rollback`** A
- Body `{ expectedHash: string }`.
- 200 `{ ok: true; restartRequired: true }`. 409 `{error}`.

**C15. GET `/api/admin-instructions`** A
```ts
type Instruction = { id: string; instruction: string; acceptance: string; scope: string[];
  status: "queued"|"awaiting_setup"|"coding"|"verifying"|"awaiting_approval"|"pull_request"|"awaiting_deploy"|"awaiting_acceptance"|"completed"|"failed";
  detail: string; branch: string|null; worktree: string|null; head: string|null; pr: number|null;
  mergeCommit: string|null; approvedHead: string|null; createdAt: ms; updatedAt: ms; notificationQueued: boolean }
{ requests: Instruction[] }
```
- 500 `{error}`.

**C16. POST `/api/admin-instructions`** A
- Body (deny_unknown_fields): `{ idempotencyKey: string /* ≤128 */; instruction: string /* ≤16000 */; acceptance: string /* ≤4000 */; scope: string[] /* 1–14 relative paths [A-Za-z0-9_./-] */ }`.
- 202 `{ request: Instruction; queued: true; completed: false }`. 400 `{error}`.

**C17. POST `/api/admin-instructions/approve`** A
- Body `{ id: string; head: string }`.
- 200 `{ approved: true }`. 409 `{error}`.

**C18. POST `/api/admin-instructions/accept`** A
- Body `{ id: string; commit: string }`.
- 200 `{ accepted: true; notification: "pending durable scheduler enqueue" }`. 409 `{error}`.

**C19. POST `/api/restart`** A → `{ restarted: boolean; service: string }`.

**C20. GET `/metrics/usage`** — **no auth**
- Query `?limit` (default 20, 1–200).
- 200:
```ts
{ turns: number; totalTokens: number; inputTokens: number; outputTokens: number; avgContextTokens: number; maxContextTokens: number;
  byModel: [string, number, number][];
  recent: { at: ms; channel: string; provider: string; model: string; inputTokens: number; outputTokens: number;
            totalTokens: number; iterations: number; status: string|null; costTotal: number|null }[];
  host: HostMetrics }
```

**C21. GET `/ws`** (cockpit live stream) — see §5.

---

## 5. Cockpit WebSocket `GET /ws?token=<token>`

- Auth is the **query string**, not a header:
  ```rust
  // WS auth: token via ?token= (browsers can't set Authorization on WS).
  if !is_authed(&shared, q.get("token").map(|s| s.as_str())).await { return unauth(); }
  ```
  A bad token gets HTTP 401 `{"error":"unauthorized"}`.
- All frames are text JSON. There are no pings or heartbeats. Client frames are drained and ignored. Lagged events are silently skipped.
- There is no envelope `type` field. Tell frames apart by the `source` key:
  1. **Backfill** on connect: the ring buffer, up to 1000 most recent `CockpitEvent`s, oldest first. These have **no `source` key**.
  2. **Live bus**: a `CockpitEvent` with `source: "bus"`.
  3. **Live audit**: `AuditFrame` with `source: "audit"`.

```ts
type CockpitEvent = {
  seq: number;            // monotonic per process; dedupe backfill vs live
  at: ms;
  session: string;        // conversation id
  run: string;            // episode id, "" if not turn-scoped
  kind: "turn_start"|"layer"|"tool"|"llm"|"message"|"reply"|"turn_end"|string;
  layer: "channel"|"auth"|"deterministic"|"memory"|"dialogue"|"cognee"|"governor"|"core"|"llm"|"tools"|"reply"|string|null;
  name: string|null;      // tool name / model id / path label
  status: "ok"|"error"|"running"|string|null;
  text: string|null;
  data?: object;          // omitted when null
  source?: "bus";         // only on live frames
}
// audit frame
{ source: "audit"; time: string; session: string|null; run: string|null; scope: string; action: string; status: "ok"|"error"|"skipped"; summary: string }
```

---

## 6. Gotchas for the Swift client

1. `Person` in `/me` uses snake_case keys (`person_id`, `display_name`). Every other struct is camelCase.
2. `mode` is Rust Debug (`"ProductionActive"`), not the kebab-case config value.
3. The cockpit state has `agentProfile`, not `profile`.
4. Cockpit `features` is an **array** of `{name, state, note}`. Mobile bootstrap `features` is an **object** of booleans.
5. WS `cursor` is always 0. Resync after a reconnect through `/conversations/mobile:<uid>/messages` (newest 50) or `person:<pid>` with `before=<ms>`.
6. `HouseholdEvent.payload` is a JSON string. Decode it twice.
7. All ids are `Int64` except user, session, person and household ids (strings).
8. The mobile WS uses header auth; the cockpit WS uses `?token=`.
9. Cockpit tokens do not survive a daemon restart. Treat a 401 as "log in again".

## UNKNOWN
- The full `config` object shape in `/api/state` (it is the raw `config.json`).
- How to page the `mobile:<uid>` history: `before` is an internal row id that no response exposes.
- Whether a retried `POST /messages` with the same `clientMessageId` is deduped by the turn pipeline (the HTTP layer re-queues it).
- The exact phone normalization at provisioning. Only verify's `digits = phone.trim().replace('+','')` is confirmed.
- The exact value sets for `Item.status`/`kind` and `ThreadLine.channel` beyond those seen in code. They are free strings.
- The format of `time` in audit frames: a string from audit `created_at`, assumed ISO-8601.
