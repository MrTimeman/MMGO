# Phase 1: Telegram Access and Player Shell - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers the player-facing Telegram Mini App entry flow and first usable in-game shell. It covers first launch, returning launch, notification-driven entry, the initial shell layout, and player-facing recovery paths for bootstrap failures. It does not add travel mechanics, world interaction flows, or broader gameplay systems beyond what is needed to enter and orient the player.

</domain>

<decisions>
## Implementation Decisions

### Launch flow
- **D-01:** The Mini App is the primary first-entry path. Players should not need to run `/start` in the bot just to begin using MMGO.
- **D-02:** A first-time Mini App open should show a lightweight MMO-style entry screen before provisioning and entering the world.
- **D-03:** Returning players should see a quick resume screen on normal app open.
- **D-04:** Notification-driven deep links must bypass the resume screen and open directly into the linked context when possible.
- **D-05:** The first-entry screen should feel like a basic MMO login screen, but without clutter.
- **D-06:** The first-entry screen must include branding/atmosphere, a realm label, a character/account preview, one strong `Enter World` CTA, and a small settings cluster.

### Shell shape
- **D-07:** The Phase 1 in-game shell should be map-first rather than dashboard-first or character-first.
- **D-08:** The Phase 1 map should support pan and zoom plus marker inspection-level interaction, but must not expose travel actions yet.
- **D-09:** A compact persistent HUD should remain visible alongside the map.
- **D-10:** Core shell navigation should use a bottom action bar optimized for mobile Telegram usage.

### Recovery states
- **D-11:** Recovery screens should stay in-world and atmospheric, but must still clearly explain what happened and what the player can do next.
- **D-12:** If MMGO cannot identify or restore the player from Telegram context, show a single recovery screen with one primary retry path and a secondary bot fallback.
- **D-13:** If starter world state is missing or partially broken, auto-repair when the fix is deterministic; otherwise show an explanatory recovery screen with guidance.

### Deep-link behavior
- **D-14:** Notification links should resume directly into the relevant destination whenever that destination/context is still valid.
- **D-15:** If the target destination is no longer valid, redirect to the closest valid context and explain briefly that the original target is no longer available.

### the agent's Discretion
- Exact structure of the settings cluster on the entry screen
- Exact compact HUD contents beyond the locked essentials
- Visual treatment, animation, and typography details within the "basic MMO login screen" direction
- Exact copy for retry/fallback messaging, provided it stays atmospheric and actionable

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and phase definition
- `.planning/PROJECT.md` — Project-level product framing, Telegram-first constraint, and non-negotiable architecture decisions
- `.planning/REQUIREMENTS.md` — Phase 1 requirements `ACCESS-01` through `ACCESS-04`
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, and canonical phase refs
- `.planning/STATE.md` — Current project position and initialization notes

### Product intent
- `docs/MMGO_GDD.md` — Telegram Mini App + bot product shape, MMO tone, and target player experience
- `docs/TECH_ARCHITECTURE.md` — Mini App platform direction, account linking, deep-link intent, and LiveView-first frontend guidance

### Existing access and provisioning paths
- `lib/mmgo/accounts.ex` — Existing Telegram-driven account, identity, and starter-character provisioning behavior
- `lib/mmgo/accounts/account.ex` — Account schema constraints and registration shape
- `lib/mmgo/accounts/character.ex` — Character schema and starter-character shape
- `lib/mmgo/accounts/telegram_identity.ex` — Telegram identity model and persisted auth data shape
- `lib/mmgo/telegram.ex` — Webhook authorization and Telegram integration entry points
- `lib/mmgo/telegram/update_handler.ex` — Existing Telegram update handling and provisioning flow
- `lib/mmgo/telegram/commands.ex` — Existing `/start` and command-based player entry behavior
- `lib/mmgo_web/controllers/telegram_webhook_controller.ex` — Current API failure modes and webhook handling

### Existing web shell and frontend assets
- `lib/mmgo_web/router.ex` — Current browser and API entry points
- `lib/mmgo_web/endpoint.ex` — Existing Phoenix session/cookie and LiveView endpoint setup
- `lib/mmgo_web/components/layouts.ex` — Existing `Layouts.app/1` and `Layouts.game/1` shells
- `lib/mmgo_web/controllers/page_controller.ex` — Current root web entry behavior
- `lib/mmgo_web/controllers/page_html/home.html.heex` — Existing bootstrap landing page that Phase 1 will supersede or route beyond
- `assets/js/app.js` — LiveView bootstrapping and hook registration point
- `assets/js/hooks/index.js` — Existing frontend hook registry
- `assets/js/hooks/map.js` — Existing reusable map hook with markers, pan/zoom, and server-driven events

### Existing tests that define current behavior
- `test/mmgo/accounts_test.exs` — Current expectations for Telegram provisioning and starter-character creation
- `test/mmgo/telegram/update_handler_test.exs` — Current `/start` behavior and Telegram send-message flow
- `test/mmgo_web/controllers/telegram_webhook_controller_test.exs` — Current webhook acceptance and rejection behavior
- `test/mmgo_web/controllers/page_controller_test.exs` — Current root page behavior

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MMGO.Accounts.provision_from_telegram/1`: already creates or refreshes account, Telegram identity, and starter character from Telegram user data
- `MMGO.Telegram.UpdateHandler`: already routes Telegram updates through provisioning and command execution
- `MMGOWeb.Layouts.game/1`: existing full-screen game shell primitive for in-game LiveViews
- `assets/js/hooks/map.js`: existing Leaflet-powered map hook with pan/zoom, markers, and player-position support
- `assets/js/hooks/index.js`: central hook registration point for any new game-shell hooks

### Established Patterns
- Telegram-origin identity is already treated as the authoritative player bootstrap signal
- Phoenix endpoint already uses signed cookie sessions and LiveView as the default interactive web model
- Existing hook demos suggest UI pieces are expected to be server-driven with focused JS interop rather than client-heavy SPA state
- Current backend behavior already supports deterministic auto-repair for some bootstrap paths, such as ensuring a default character for an existing identity

### Integration Points
- Root browser entry currently goes through `PageController.home/2` and can be replaced or rerouted into the new Phase 1 shell
- API/webhook entry already exists at `/api/telegram/webhook`
- New Mini App entry and resume flows will likely connect routing, LiveView session setup, and existing account provisioning
- Notification deep-link behavior will need to connect Telegram-origin links with shell routing and valid-context fallback logic

</code_context>

<specifics>
## Specific Ideas

- The first-entry screen should feel like a basic MMO login screen, but without clutter.
- The screen should be mostly atmosphere plus one clear way to enter the world.
- Character/account preview and realm name should be visible so the screen still feels like an MMO login rather than a generic splash page.
- Normal resume and notification resume should behave differently: notification links should not force an extra stop.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-telegram-access-and-player-shell*
*Context gathered: 2026-04-03*
