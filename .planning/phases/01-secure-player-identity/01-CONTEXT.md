# Phase 1: Secure Player Identity - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning
**Mode:** Auto-generated after the user's explicit instruction to finish the full GDD without per-phase approval gates.

<domain>
## Phase Boundary

Replace shared browser demo authority with a verified Telegram Mini App entry flow and a server-derived LiveView scope. Keep a narrow, clearly labelled development/demo path so local gameplay and tests remain usable without live Telegram credentials. This phase establishes identity, ownership, and error/entry UX; it does not wire every game screen's domain data yet.

</domain>

<decisions>
## Implementation Decisions

### Session Ownership
- Verify Telegram Web App `initData` on the server with the configured bot token, constant-time hash comparison, and a bounded auth-date age before calling `MMGO.Accounts.provision_from_telegram/1`.
- Store only server-derived account/character identifiers in the signed session and derive the actor from `current_scope` for browser gameplay.
- Place player LiveViews in an authenticated `live_session` with an `on_mount` guard that redirects missing/invalid sessions to the game entry screen.
- Never allow a browser event/query parameter to choose a character, account, or owner.

### Entry and Demo UX
- Add a real Mini App entry endpoint/page that accepts verified init data and redirects a successfully authenticated player to the map.
- Provide explicit loading, invalid/expired authorization, and unavailable-config states; do not silently create a demo account for a failed production login.
- Preserve demo entry only as a local/test-only fixture route or explicitly flagged local mode, with each test creating independent scoped state.
- The first signed-in destination remains the existing map; its full live-data rewrite belongs to Phase 2.

### Web Architecture
- Introduce a focused auth/session module under `MMGOWeb` and a Telegram init-data verifier under the Telegram/account boundary rather than putting cryptographic logic in a controller or LiveView.
- Use Phoenix sessions, routers, and LiveView `on_mount`; do not add OAuth, a SPA, a new authentication dependency, or client-side authority.
- Update existing core game LiveViews to receive `current_scope` through the shared authenticated session before their later data-wiring phases.
- Maintain the Phoenix 1.8 layout contract: every revised LiveView uses `<Layouts.app flash={@flash} current_scope={@current_scope}>`.

### Deployment and Safety
- Production Telegram webhook access fails closed when webhook handling is configured; local/test values retain explicit safe behavior.
- All verification has deterministic local tests for valid, tampered, expired, missing-token, and cross-character cases.
- Live credentials, bot tokens, and raw `initData` values never appear in logs, test fixtures, or user-facing error messages.

### the agent's Discretion
- Choose exact module/file names, route names, and session key names based on established Phoenix conventions.
- Decide how broadly to move existing screen routes into the authenticated live session in this phase, provided no protected game page can execute a command without a scoped character.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and requirements
- `docs/MMGO_GDD.md` — §1 and §16.4 define Telegram Mini App + bot as the technical platform.
- `.planning/REQUIREMENTS.md` — AUTH-01 through AUTH-04 acceptance requirements.
- `.planning/ROADMAP.md` — Phase 1 goal and success criteria.

### Existing identity and web boundaries
- `lib/mmgo/accounts.ex` — existing Telegram account/character provisioning transaction.
- `lib/mmgo/accounts/telegram_identity.ex` — persisted identity schema and security-relevant fields.
- `lib/mmgo/telegram.ex` and `lib/mmgo/telegram/update_handler.ex` — bot/webhook identity behavior.
- `lib/mmgo_web/router.ex` — current public/demo routes and all LiveView routes to protect.
- `lib/mmgo_web/endpoint.ex` — signed session and LiveView socket configuration.
- `lib/mmgo_web.ex` and `lib/mmgo_web/components/layouts.ex` — web macros/layout/current scope contract.
- `lib/mmgo_web/controllers/play_demo_controller.ex` and `lib/mmgo_web/controllers/play_api_controller.ex` — legacy demo session flow to isolate or replace.

### Tests and conventions
- `test/mmgo/accounts_test.exs` — Telegram provisioning fixtures.
- `test/mmgo_web/controllers/telegram_webhook_controller_test.exs` — existing secret testing pattern.
- `test/mmgo_web/play_demo_loop_test.exs` — current demo-session browser loop to migrate safely.
- `AGENTS.md` — Phoenix, LiveView, test, and security rules.

</canonical_refs>

<specifics>
## Specific Ideas

- The UX should feel like entering a game, not a generic account form: a compact full-height handoff/loading panel, concise plain-language authorization error, and one clear next action.
- The new entry must work in Telegram and fail safely in a normal browser without pretending the visitor owns a character.

</specifics>

<deferred>
## Deferred Ideas

- Canonical map/player/notification data, social presence, and gameplay activity wiring — Phase 2 and later.
- Runtime combat AI and narration — Phase 4.
- Production deployment of actual Telegram Mini App URLs, bot token, and webhook secret — environment/operator work after source support exists.

</deferred>
