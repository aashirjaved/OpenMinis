# Magzi iOS — engineering brief for screen work

App: src/ios (target Minis, iOS 16.0 deployment, Xcode 27, Swift 5 mode). `src/ios/Magzi/**` is a
filesystem-synchronized group: new .swift files there compile automatically. NEVER edit project.pbxproj.

Read before coding:
- docs/magzi-design-spec.md — visual + per-screen spec (sections 1, 3, 4, 5, 6). Section 2 is already implemented.
- src/ios/Magzi/Design/*.swift — tokens/components. Use only: MagziDesign.{background,surface,surfaceSecondary,
  surfaceElevated,hairline,hairlineStrong,label,labelSecondary,labelTertiary,mint,onAccent,mintSoft,blue,amber,rose,
  violet,success,warning,danger,info}, Spacing/Radius/Typography/Shadows/Motion, .magziCard(), .magziShadow(),
  .magziScreenBackground(), MagziPill, MagziSectionHeader, MagziEmptyState, MagziStatus/MagziStatusDot,
  MagziIconBadge, MagziMetricCard, MagziRow, MagziRing, MagziPrimary/Secondary/CompactButtonStyle.
  Do NOT use legacy names (glass, solid, appBackground, primaryGradient, ink, obsidian, graphite, text, secondary, tertiary, line, lineStrong).
- src/ios/Magzi/Core/*.swift — networking/state. Use MagziAPI.shared (mobile routes), MagziCockpitAPI.shared,
  MagziHub.shared (bootstrap/me/households/selectedHouseholdId/status/isAdmin/pendingApprovalsCount/today()/householdChanged),
  MagziChatStore.shared, MagziWebSocket.shared, MagziAuthStore.shared, MagziCockpitAuth.shared, MagziCockpitSocket.shared,
  MagziConnectView(), MagziCockpitLoginView(), JSONValue, MagziError.
- src/ios/Magzi/Views/Shell/MagziRouter.swift — MagziRouter.shared: `tab`, `askMagzi(_ prompt:, send:)`, `chatDraft`.
  The spec's "MagziAppModel" == MagziHub.shared + MagziRouter.shared (do not create MagziAppModel).
- docs/magzi-api-contract.md — wire truth. If the design spec mentions an endpoint/event not in the contract
  (e.g. ws `message.final`, `tool.*`, `approval.requested`), the contract wins: degrade gracefully.
  Approve/deny returns 403 for non-admins (they map to role guest) — hide those buttons unless MagziHub.shared.isAdmin
  or show an inline explanation on 403.

Rules:
- iOS 16 APIs. Any iOS 17+ API must be guarded by `if #available` in plain (non-@ViewBuilder) code; Xcode 27 rejects
  `if #available` inside result builders when the guarded API isn't used directly — wrap in a helper ViewModifier with
  `@ViewBuilder func body` using `if #available` only around simple modifier calls, or avoid the API.
- Every screen: loading skeleton (.redacted), .refreshable, inline error card with Try again, empty state.
- Never log tokens. No third-party deps. No print().
- Name types with a unique prefix per area to avoid collisions with other engineers working in parallel
  (other folders: Shell, Chat, Household, Me, Ops). Only touch files in your own folder unless your brief says otherwise.
  If you need a small shared helper, define it fileprivate in your folder.
- Build: `/private/tmp/claude-501/-Users-aashirjaved-Coding-homelab-apps-OpenMinis/9e4e27e7-3518-405b-ac06-db2d42aafc01/scratchpad/build.sh <yourname>`
  (prints EXIT + errors; few minutes). Others build concurrently; errors in files you don't own → ignore/report, don't edit.
  Iterate until your files have zero errors and ideally BUILD SUCCEEDED.
- Final reply: files created + public view type names + anything stubbed/unfinished. Concise.
