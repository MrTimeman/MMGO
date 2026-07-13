# Architecture

## System shape

- MMGO is a Phoenix modular monolith: domain operations live under `lib/mmgo/`, while HTTP and LiveView delivery live under `lib/mmgo_web/`.
- `lib/mmgo/application.ex` supervises telemetry, `MMGO.Repo`, DNS clustering, `MMGO.PubSub`, Oban, and `MMGOWeb.Endpoint` with a one-for-one strategy.
- `lib/mmgo/repo.ex` is the single Ecto/PostgreSQL repository. The project configures binary IDs globally in `config/config.exs`; domain schemas declare associations and changesets in their owning folders.
- `config/config.exs` configures Oban queues (`:default` and `:telegram`), Phoenix/Bandit, and the AI, Telegram, PvP, and federation boundaries.

## Domain layers

- Root context modules such as `lib/mmgo/accounts.ex`, `lib/mmgo/worlds.ex`, `lib/mmgo/travel.ex`, `lib/mmgo/combat.ex`, and `lib/mmgo/economy.ex` are the command/query APIs for their domains.
- Their child modules hold schemas and specialized logic, for example `lib/mmgo/accounts/character.ex`, `lib/mmgo/travel/journey.ex`, `lib/mmgo/combat/engine.ex`, and `lib/mmgo/economy/ledger_entry.ex`.
- Contexts own validation, transactions, locks, and cross-context coordination; `Repo.transaction/1` plus `FOR UPDATE` locking appears in travel, PvP, scavenging, and other state-transition paths.
- `lib/mmgo/play.ex` is a web-facing orchestration/read-model boundary for the playable demo. It composes state from Accounts, Worlds, Travel, Survival, Inventory, Grimoires, Spells, PvP, Combat, and Economy instead of moving those rules into controllers or LiveViews.
- `lib/mmgo/world_map.ex` is deliberately separate from `MMGO.Worlds`: the former owns terrain JSON, caching, sprites, and hex placement; the latter owns persisted realms, locations, and routes.

## Primary data flows

```text
browser / LiveView / webhook
  -> MMGOWeb router, controller, or LiveView
  -> MMGO context or MMGO.Play orchestration facade
  -> Ecto schemas + PostgreSQL transactions
  -> optional Oban job / Telegram notification
  -> refreshed LiveView or JSON response
```

- Demo bootstrap runs `MMGOWeb.PlayDemoController` in `lib/mmgo_web/controllers/play_demo_controller.ex`, calls `MMGO.Play`, stores demo character IDs in the signed session, then redirects to `MMGOWeb.MapLive`.
- Map state flows from `lib/mmgo_web/live/map_live.ex` through `MMGO.Play.state_for_character/1`; journey requests use `MMGO.Play.start_journey/2`, which checks a `MMGO.Worlds.Route` and delegates scheduling to `MMGO.Travel`.
- `lib/mmgo/travel.ex` consumes food through `MMGO.Survival`, persists a `MMGO.Travel.Journey`, and schedules `lib/mmgo/travel/complete_journey_worker.ex`; that worker completes the transition and queues a notification.
- Duel flow is `MMGOWeb.DuelLive` -> `MMGO.Play` -> `MMGO.PVP` -> `MMGO.Economy` escrow and `MMGO.Combat`. `lib/mmgo/combat/engine.ex` deterministically resolves persisted turns/actions, while `lib/mmgo/combat/resolution.ex` finalizes outcomes and lets PvP settle a finished duel.
- Spell authoring flows through `lib/mmgo/spells/compiler.ex` and `lib/mmgo/ai.ex`; the resulting validated `MMGO.Spells.Spell` is consumed by the deterministic combat engine rather than asking an LLM to decide a cast at runtime.

## Web entry points

- `lib/mmgo_web/router.ex` separates browser pages/LiveViews, unauthenticated JSON API endpoints, and session-backed `/api/play` JSON endpoints.
- `lib/mmgo_web/controllers/play_api_controller.ex` exposes demo state and journey creation as JSON but delegates to `MMGO.Play`; it does not accept a client-supplied character ID.
- `lib/mmgo_web/controllers/telegram_webhook_controller.ex` verifies the Telegram secret before delegating update processing to `MMGO.Telegram`.
- `lib/mmgo_web/controllers/federation_controller.ex` exposes realm manifests and guards imports with a bearer token before using `MMGO.Federation`.
- `lib/mmgo_web/live/map_live.ex`, `lib/mmgo_web/live/travel_live.ex`, `lib/mmgo_web/live/inventory_live.ex`, and `lib/mmgo_web/live/duel_live.ex` use the demo session and `MMGO.Play` for server-authoritative playable-loop state.
- Other screen-oriented LiveViews are also routed from `lib/mmgo_web/router.ex`; several are explicitly marked as design-pass/demo-data surfaces in that router and in their modules, so their visual state is not uniformly backed by the same context layer yet.
- `lib/mmgo_web/live/map_editor_live.ex` is development-routed and directly coordinates `MMGO.WorldMap.Editor` with `MMGO.Worlds` for map editing.

## Jobs, persistence, and integrations

- Scheduled completion workers live beside their domains: `lib/mmgo/travel/complete_journey_worker.ex`, `lib/mmgo/scavenging/complete_attempt_worker.ex`, `lib/mmgo/crafting/complete_craft_job_worker.ex`, `lib/mmgo/alchemy/complete_brew_job_worker.ex`, `lib/mmgo/bases/complete_base_build_worker.ex`, `lib/mmgo/academy/complete_enrollment_worker.ex`, and `lib/mmgo/academia/complete_project_worker.ex`.
- Dungeon and notification boundaries are represented by `lib/mmgo/dungeons/complete_extraction_worker.ex`, `lib/mmgo/dungeons/maintenance_worker.ex`, `lib/mmgo/academia/thesis_defense_worker.ex`, and `lib/mmgo/notifications/delivery_worker.ex`; the last uses the dedicated `:telegram` queue.
- Database history is append-only migration files under `priv/repo/migrations/`; `priv/repo/seeds.exs` supplies seed data, while `priv/realms/starter_realm_manifest.json` supports realm import/export tooling.
- Telegram outbound requests are encapsulated by `lib/mmgo/telegram/client.ex`; `lib/mmgo/notifications.ex` persists an outbox record before the delivery worker calls it.
- AI provider selection and request auditing live in `lib/mmgo/ai.ex`, with provider implementations under `lib/mmgo/ai/providers/` and prompt contracts under `lib/mmgo/ai/prompts/`.
- Federation exchange/import logic remains in `lib/mmgo/federation.ex` and `lib/mmgo/federation/`, with its public HTTP boundary intentionally kept in the controller layer.

## Client boundary

- `assets/js/app.js` creates the LiveSocket and imports hooks from `assets/js/hooks/index.js`.
- The `HexMap` hook in `assets/js/hooks/hex-map.js` owns canvas interaction and receives server-pushed map state; it does not calculate authoritative routes or travel outcomes.
- `assets/css/app.css` imports Tailwind and screen-family CSS, while per-screen styles live in `assets/css/screens/`.
