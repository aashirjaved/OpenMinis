# Magzi Mobile UI Requirements

## Decision

Keep both runtime modes:

1. **Local Agent Mode** — current OpenMinis behavior.
   - iOS app talks directly to configured LLM provider.
   - iOS app runs local tool loop, iSH, browser, files, attachments, local sessions.
   - Works offline from homecloud where possible.
   - Useful as fallback/dev/private local workspace.

2. **Magzi Homecloud Mode** — new native UI in front of Rust `magzid` running on homecloud.
   - iOS app talks to `magzid` over Tailscale-only HTTP/WebSocket.
   - `magzid` owns tools, memory, automations, scheduler, approvals, homecloud/Nextcloud/GWS connectors, alerts.
   - App is an additional channel/UI beside WhatsApp/Telegram, not a replacement for local mode.

Default product posture: **Magzi Homecloud Mode primary, Local Agent Mode preserved as fallback/power-user mode.**

## Goals

- Make iOS app a first-class Magzi communication surface beyond WhatsApp limits.
- Preserve local LLM/provider/tool loop already working in OpenMinis.
- Add remote Magzi UI without breaking local sessions.
- Support rich alerts, approvals, automations, tool timelines, media, voice, files, homecloud status.
- Keep homecloud private: Tailscale-only, no public Cloudflare exposure by default.
- Avoid putting server secrets on iPhone.

## Non-goals

- Do not remove local OpenMinis agent mode.
- Do not move all Magzi server tools into iOS.
- Do not expose `magzid` publicly.
- Do not embed Nextcloud/GWS/9router/server credentials in iOS app.
- Do not depend on WhatsApp as primary UI for rich actions.

## Architecture

```text
                       ┌─────────────────────────┐
                       │ iOS Magzi app            │
                       │                         │
                       │ Mode A: Local Agent      │
                       │  LLM provider            │
                       │  local tool loop         │
                       │  local sessions          │
                       │                         │
                       │ Mode B: Homecloud Magzi  │
                       │  REST/WebSocket client   │
                       │  alerts/approvals UI     │
                       └───────────┬─────────────┘
                                   │ Tailscale-only HTTPS/WS
                                   ▼
                       ┌─────────────────────────┐
                       │ magzid on homecloud      │
                       │ Rust runtime             │
                       │ memory/tools/scheduler   │
                       │ automations/approvals    │
                       │ WhatsApp/Telegram        │
                       └─────────────────────────┘
```

## Runtime modes

### Local Agent Mode

Keep current capabilities:

- Provider configuration UI.
- Direct LLM calls through existing provider abstraction.
- Local chat/session DB.
- Local iSH shell/tool integrations.
- Local file/browser/media tools.
- Local attachments and share extension.
- Local debug/server tools for development.

Required additions:

- Clear mode indicator: `Local` badge.
- Per-session mode stored in session metadata.
- Settings toggle/default: `Default Runtime = Homecloud | Local`.
- No local provider/key deletion during Magzi Homecloud onboarding.
- Local mode can still use 9router provider when configured.

### Magzi Homecloud Mode

New behavior:

- iOS app becomes a native channel for `magzid`.
- A user message is sent to `magzid` as `channel = mobile`.
- Rust runtime handles it through existing Magzi turn pipeline.
- Replies/tool/progress events stream back to app.
- App renders rich UI, not just WhatsApp-style text.

Required session identity:

```text
channel: mobile
sender_id: mobile:<device_id>
conversation_id: mobile:<device_id>:<thread_id>
message_id: client-generated UUID
```

## Server requirements (`magzi-agent`)

### Config

Add:

```json
{
  "mobile": {
    "enabled": true,
    "host": "100.x.y.z",
    "port": 8766,
    "publicUrl": "http://100.x.y.z:8766",
    "pairing": {
      "ttlSecs": 300
    },
    "push": {
      "apnsEnabled": false,
      "bundleId": "com.aashirjaved.openminis.local",
      "keyEnv": "MAGZI_APNS_KEY",
      "teamIdEnv": "MAGZI_APNS_TEAM_ID",
      "keyIdEnv": "MAGZI_APNS_KEY_ID"
    }
  }
}
```

Notes:

- Bind to Tailscale IP or localhost behind Tailscale proxy only.
- `apnsEnabled=false` until paid Apple Developer setup exists.
- Existing `admin.enabled` cockpit remains separate.

### New server modules

Suggested files:

```text
crates/magzid/src/mobile_server.rs
crates/magzi-core/src/mobile_auth.rs
crates/magzi-core/src/mobile_device_store.rs
crates/magzi-core/src/mobile_channel.rs
```

### Pairing

Requirements:

- Owner requests pairing via existing trusted channel or admin panel.
- Server returns QR/link containing short-lived pairing code.
- iOS app generates device keypair.
- iOS sends pairing code + public key + device metadata.
- Server stores device record.
- Server returns short-lived session token + refresh mechanism.
- Tokens stored in iOS Keychain.

Device record fields:

```json
{
  "deviceId": "uuid",
  "deviceName": "Ashu Rockx Phone",
  "publicKey": "base64",
  "platform": "ios",
  "bundleId": "com.aashirjaved.openminis.local",
  "apnsTokenHash": "optional",
  "createdAt": "iso",
  "lastSeenAt": "iso",
  "revokedAt": null
}
```

### Auth/security

- All mobile endpoints require auth after pairing.
- Request signing preferred:
  - `x-magzi-device-id`
  - `x-magzi-timestamp`
  - `x-magzi-nonce`
  - `x-magzi-signature`
- Reject replayed nonce.
- Reject stale timestamp, default 60s window.
- Token expiry and revocation required.
- Device revocation in admin/cockpit.
- Never return secrets/env values to app.
- Audit all device pair/revoke/send/approve actions.

### Multi-user accounts

Magzi Mobile must support multiple users, not only the owner/admin.

Admin requirements:

- Owner/admin can create users from the admin UI by email address.
- Owner/admin can assign role and scopes per user.
- Owner/admin can disable/revoke users.
- Owner/admin can view user sessions/devices, last login, active tokens, and audit summary.
- Owner/admin can reset a user's login state without deleting their data.

User login requirements:

- User enters email in Magzi iOS app.
- Rust backend verifies the email exists and is enabled.
- Backend sends one-time login code to that email.
- User enters OTP in app.
- Backend creates authenticated user session.
- App stores token in Keychain.
- OTPs are short-lived, one-use, rate-limited, and audited.
- Login must not reveal whether an arbitrary email exists; app shows generic “If enabled, a code was sent.”

User data model:

```json
{
  "userId": "uuid",
  "email": "person@example.com",
  "displayName": "Person",
  "role": "admin|family|user|guest",
  "scopes": ["chat", "alerts", "approvals", "nextcloud", "homecloud"],
  "createdBy": "admin-user-id",
  "createdAt": "iso",
  "disabledAt": null
}
```

Session/device model:

```json
{
  "sessionId": "uuid",
  "userId": "uuid",
  "deviceId": "uuid",
  "deviceName": "iPhone",
  "createdAt": "iso",
  "lastSeenAt": "iso",
  "expiresAt": "iso",
  "revokedAt": null
}
```

Backend responsibilities:

- Keep authoritative users, sessions, devices, and per-user data ownership in Rust backend.
- Bind every mobile message to authenticated `userId` and `deviceId`.
- Store conversations with user ownership metadata.
- Enforce per-user scopes before exposing tools/data.
- Keep each user's chat history, alerts, approvals, files, and settings separate unless explicitly shared.
- Audit all user login, logout, OTP, session refresh, device registration, user create/update/disable events.
- Support admin data export/delete per user later.

Channel identity mapping:

```text
channel: mobile
sender_id: mobile:user:<user_id>:device:<device_id>
conversation_id: mobile:user:<user_id>:thread:<thread_id>
message_id: client-generated UUID
```

Access control defaults:

- `admin`: full mobile admin/user management plus owner capabilities.
- `family`: chat, alerts, allowed approvals, scoped Nextcloud/homecloud tools.
- `user`: personal chat plus explicitly granted tools.
- `guest`: limited chat only, no sensitive tools by default.

Email delivery:

- Use backend email provider/SMTP config, not iOS mail.
- Email OTP contents must contain code, expiry, device/location hint if available, and security warning.
- Never send API tokens in email.

### REST API

Minimum Phase 1:

```http
POST /mobile/v1/pair/start
POST /mobile/v1/pair/complete
GET  /mobile/v1/bootstrap
GET  /mobile/v1/sessions
GET  /mobile/v1/sessions/{id}/messages
POST /mobile/v1/sessions
POST /mobile/v1/messages
WS   /mobile/v1/ws
```

Phase 2:

```http
GET  /mobile/v1/alerts
POST /mobile/v1/alerts/{id}/ack
POST /mobile/v1/alerts/{id}/snooze
POST /mobile/v1/alerts/{id}/done
GET  /mobile/v1/approvals
POST /mobile/v1/approvals/{id}/approve
POST /mobile/v1/approvals/{id}/deny
GET  /mobile/v1/automations
POST /mobile/v1/automations/{id}/pause
POST /mobile/v1/automations/{id}/resume
GET  /mobile/v1/homecloud
GET  /mobile/v1/tools
GET  /mobile/v1/health
```

Phase 3:

```http
POST /mobile/v1/push/register
POST /mobile/v1/push/unregister
POST /mobile/v1/files/upload/init
PUT  /mobile/v1/files/upload/{id}
GET  /mobile/v1/files/{id}
POST /mobile/v1/audio/transcribe
POST /mobile/v1/audio/speak
```

### Message injection

`POST /mobile/v1/messages` maps to existing runtime:

```rust
NormalizedInboundMessage {
    channel: "mobile".into(),
    conversation_id: format!("mobile:{device_id}:{thread_id}"),
    sender_id: format!("mobile:{device_id}"),
    message_id: client_message_id,
    text,
    received_at,
    metadata,
}
```

Then:

```text
ChannelRouter.route
→ MagziRuntime.handle_inbound
→ OutboundMessageRequest
→ MobileChannel.send_message
→ WebSocket/APNs/mobile store
```

### WebSocket events

Required event types:

```json
{ "type": "connection.ready" }
{ "type": "message.accepted", "clientMessageId": "...", "serverMessageId": "..." }
{ "type": "message.delta", "sessionId": "...", "text": "..." }
{ "type": "message.final", "sessionId": "...", "message": {} }
{ "type": "tool.start", "runId": "...", "tool": "...", "argsPreview": "..." }
{ "type": "tool.update", "runId": "...", "tool": "...", "status": "running" }
{ "type": "tool.result", "runId": "...", "tool": "...", "success": true, "summary": "..." }
{ "type": "approval.requested", "approvalId": "..." }
{ "type": "alert.created", "alertId": "..." }
{ "type": "automation.fired", "jobId": "..." }
{ "type": "health.changed", "component": "whatsapp", "state": "degraded" }
```

Use existing `CockpitBus` + audit stream where possible. Add mobile-specific events only where needed.

### Mobile channel adapter

Add `MobileChannel` implementing Magzi channel semantics:

- `start`: loads paired devices/sessions, starts fanout bus.
- `send_message`: persists outbound message, publishes WebSocket event, optionally sends APNs push.
- `health`: connected if server running; degraded if no active devices/push failure.
- `set_typing`: publishes typing event to WebSocket.

### Push notifications

Important constraint:

- Reliable APNs likely requires paid Apple Developer Program.
- Free local signing hack likely cannot ship Push Notifications entitlement.

Required once Apple Developer is available:

- App registers APNs token.
- Server stores token hash + encrypted token.
- APNs payload contains opaque IDs only.
- No PII/message text in payload by default.
- Notification tap fetches details over Tailscale.

Notification categories:

```text
MAGZI_MESSAGE
MAGZI_ALERT
MAGZI_APPROVAL
MAGZI_AUTOMATION
MAGZI_HEALTH
```

Actions:

```text
Reply
Approve
Deny
Snooze 15m
Mark Done
Open
```

Fallback before APNs:

- WebSocket foreground updates.
- Pull on app open.
- Local notification only for app-known local events.
- WhatsApp/Telegram remain fallback alert channels.

## iOS requirements

### New Swift modules

```text
src/ios/MagziRemote/MagziRemoteClient.swift
src/ios/MagziRemote/MagziAuthStore.swift
src/ios/MagziRemote/MagziWebSocket.swift
src/ios/MagziRemote/MagziRemoteModels.swift
src/ios/MagziRemote/MagziSessionSync.swift
src/ios/MagziRemote/MagziPushRegistry.swift
src/ios/MagziRemote/MagziRuntimeMode.swift
```

### Mode selection

Requirements:

- App-level default runtime mode.
- Per-session runtime mode persisted.
- New session menu:
  - `New Magzi Homecloud Chat`
  - `New Local Agent Chat`
- Visible badge in chat header:
  - `Homecloud`
  - `Local`
- If homecloud unreachable, offer:
  - retry
  - open local fallback session
  - continue offline draft

### Data model additions

Session fields:

```swift
runtimeMode: "local" | "homecloud"
remoteThreadId: String?
remoteConversationId: String?
lastRemoteSyncAt: Date?
remoteStatus: "synced" | "pending" | "failed"
```

Message fields:

```swift
remoteMessageId: String?
clientMessageId: String
deliveryState: "queued" | "sent" | "delivered" | "failed"
source: "local" | "homecloud" | "push" | "websocket"
```

### Remote chat behavior

- User sends message.
- App writes optimistic local row.
- App sends to `/mobile/v1/messages`.
- App receives ack.
- App subscribes to WebSocket events.
- Tool events render as rich blocks.
- Final reply replaces/finishes assistant message.
- Offline send queues until Tailscale/server reachable.

### UI surfaces

Tabs/sections:

```text
Chats
Alerts
Approvals
Automations
Homecloud
Settings
```

Chat UI must support:

- streaming assistant text
- tool timeline cards
- approval cards with buttons
- alert cards
- file/audio/image attachments
- delivery status
- connection state
- remote/local badge

Alerts UI:

- unread/active/resolved sections
- severity
- source automation/tool/service
- ack/snooze/done
- deep link to related chat/run

Approvals UI:

- pending write/send/tool approvals
- clear risk explanation
- approve/deny buttons
- optional “approve once” vs “always allow” if server policy supports it

Automations UI:

- list schedules/workflows
- next run
- last run status
- pause/resume
- recent failures
- dead-lettered jobs

Homecloud UI:

- services from `homecloud_services`
- health from `homecloud_service_status`
- node/service grouping
- links to relevant dashboards
- read-only initially

Settings UI:

- Pair/unpair homecloud Magzi
- device name
- runtime default
- notification settings
- Tailscale reachability test
- server health
- local provider settings retained

### Live Activities

Use for long-running remote turns:

- research/task running
- media/watch processing
- homecloud operation
- large file processing
- automation run

Show:

- task title
- current tool
- elapsed time
- progress text
- tap to open session

### App Intents / Shortcuts

Required intents:

- `Ask Magzi` — sends to default runtime.
- `Ask Homecloud Magzi` — force remote.
- `Ask Local Magzi` — force local.
- `Show Alerts`.
- `Approve Magzi Action` where safe/identified.
- `Run Magzi Automation` for allowlisted automations.

### Files/media/voice

Homecloud mode:

- Upload attachments to `magzid`, not directly to provider.
- Server decides tool visibility/storage.
- Voice note can be transcribed server-side using Magzi media/life tools.
- Support image/PDF/document uploads.
- Support generated files returned by Magzi.

Local mode:

- Preserve current local attachment/iSH behavior.

## Integration with existing Magzi tools

Homecloud mode must expose UI for these server-side capabilities:

- Google Workspace: Gmail/Drive/Docs/Sheets/Calendar/Contacts.
- Nextcloud: search/list/read per sender account.
- Homecloud catalog/status.
- Media watch/transcribe/OCR.
- Finance/market/trader alerts.
- Wallet/research/life tools.
- Scheduler/reminders/workflows.
- Approvals/governor/write policy.
- Self-healing/skills status where safe.

Tool execution stays on server. iOS renders state/results.

## Privacy rules

- No raw secrets in app logs.
- APNs payloads opaque by default.
- Redact PII in diagnostics.
- Do not sync Magzi server memory wholesale to iPhone.
- Fetch only session/alert/tool details needed for UI.
- Respect per-sender Nextcloud bindings on server.
- Device revocation must cut off all API/WS access.

## Reliability requirements

- Offline outbox.
- Idempotent client message IDs.
- Server dedupe by `(device_id, client_message_id)`.
- WebSocket reconnect with resume cursor.
- Pull-to-refresh reconciliation.
- Local cache should survive app restart.
- If WebSocket drops during turn, REST fetch reconstructs current state.
- WhatsApp/Telegram remain fallback for critical alerts until APNs proven.

## Observability requirements

Server:

- audit events for mobile auth, message send, delivery, push send, approvals.
- metrics for connected devices, WS connections, push success/fail, mobile turns.
- health endpoint includes mobile gateway.

App:

- debug screen with server URL, auth state, WS state, last sync, queued messages.
- export redacted diagnostics.
- never export tokens/secrets/raw APNs token.

## Migration/rebrand requirements

- User-visible strings must say `Magzi`, not `Minis`.
- Internal file names/paths may remain `Minis` until safe rename phase.
- UI must clearly look Magzi-branded.
- Preserve bundle ID during local hack unless paid account/new App ID is ready.

## Phased implementation

### Phase 0 — Requirements + design

- This document.
- Decide server URL/Tailscale host.
- Decide Apple Developer/APNs timing.

### Phase 1 — Homecloud chat MVP

Server:

- `mobile.enabled`
- pairing
- mobile device store
- `POST /mobile/v1/messages`
- `WS /mobile/v1/ws`
- mobile channel adapter

App:

- pairing screen
- remote auth store
- remote client
- remote chat session mode
- send message, receive final reply
- render basic tool events

Acceptance:

```text
iPhone sends message → magzid processes → reply appears in app.
Local Agent Mode still works.
```

### Phase 2 — Rich live events

- streaming text deltas
- tool cards
- typing/progress
- reconnect/resume
- server session history sync

Acceptance:

```text
Long Magzi task shows live tool timeline in iOS.
App restart can reconstruct session.
```

### Phase 3 — Alerts + approvals

- alert inbox
- approval inbox
- ack/snooze/done
- approve/deny
- automation list

Acceptance:

```text
A Magzi approval request appears in app and can be approved/denied safely.
```

### Phase 4 — Push notifications

Requires Apple Developer.

- APNs token registration
- push provider in `magzid`
- notification categories/actions
- deep links to chat/alert/approval

Acceptance:

```text
Homecloud automation fires while app closed → iPhone receives notification → tap opens exact Magzi alert.
```

### Phase 5 — Homecloud power UI

- homecloud dashboard
- Nextcloud browser/search/read
- GWS action screens
- Live Activities
- voice/media upload
- App Intents

Acceptance:

```text
Most WhatsApp-limited workflows have richer native UI alternatives.
```

## Open questions

- Apple Developer account timing for APNs?
- Use existing admin cockpit port or separate mobile port? Recommendation: separate mobile port.
- Should mobile conversations mirror into existing `AssistantStore` exactly or have a mobile session table plus audit? Recommendation: reuse existing store where possible, add mobile indexes only.
- Should app support multiple Magzi servers? Recommendation: model supports it, UI starts with one.
- Should remote mode become default for all new chats after pairing? Recommendation: yes.
