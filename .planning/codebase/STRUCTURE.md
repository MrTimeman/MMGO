# Structure

## Repository layout

```text
lib/mmgo/          domain contexts, schemas, workers, and game rules
lib/mmgo_web/      Phoenix endpoint, router, controllers, LiveViews, components
assets/            bundled JavaScript hooks and CSS source
config/            environment and runtime configuration
priv/              database migrations, seed/realm data, and served static files
test/              ExUnit domain, controller, LiveView, and support tests
docs/              product, UI, and technical reference documents
```

## Domain code organization

- A top-level context is normally named `lib/mmgo/<domain>.ex` and defines `MMGO.<Domain>`: examples include `lib/mmgo/dungeons.ex`, `lib/mmgo/market.ex`, `lib/mmgo/organizations.ex`, and `lib/mmgo/reputation.ex`.
- Domain-specific Ecto schemas are grouped in matching folders, such as `lib/mmgo/dungeons/`, `lib/mmgo/organizations/`, `lib/mmgo/parties/`, and `lib/mmgo/reputation/`.
- The common naming pattern is singular schema modules under plural contexts: `MMGO.Worlds` owns `lib/mmgo/worlds/realm.ex`, `location.ex`, and `route.ex`; `MMGO.PVP` owns `lib/mmgo/pvp/duel.ex`.
- Behavior-heavy subsystems split pure/specialized logic beside schemas: `lib/mmgo/combat/engine.ex`, `lib/mmgo/combat/rng.ex`, `lib/mmgo/combat/resolution.ex`, `lib/mmgo/spells/compiler.ex`, and `lib/mmgo/world_map/path.ex`.
- Long-running actions use a `complete_*_worker.ex` naming convention beside the relevant domain, including `lib/mmgo/crafting/complete_craft_job_worker.ex` and `lib/mmgo/alchemy/complete_brew_job_worker.ex`.
- `lib/mmgo/play.ex` is intentionally a cross-domain presentation/orchestration facade rather than another persistence family.

## Important domain locations

| Area | Primary locations |
| --- | --- |
| Identity and player state | `lib/mmgo/accounts.ex`, `lib/mmgo/accounts/account.ex`, `lib/mmgo/accounts/character.ex` |
| World graph and travel | `lib/mmgo/worlds.ex`, `lib/mmgo/worlds/`, `lib/mmgo/travel.ex`, `lib/mmgo/travel/` |
| Combat and PvP | `lib/mmgo/combat.ex`, `lib/mmgo/combat/`, `lib/mmgo/pvp.ex`, `lib/mmgo/pvp/duel.ex` |
| Spells and loadouts | `lib/mmgo/spells.ex`, `lib/mmgo/spells/`, `lib/mmgo/grimoires.ex`, `lib/mmgo/grimoires/` |
| Economy and inventory | `lib/mmgo/economy.ex`, `lib/mmgo/economy/`, `lib/mmgo/inventory.ex`, `lib/mmgo/inventory/` |
| Timed/world activities | `lib/mmgo/dungeons.ex`, `lib/mmgo/scavenging.ex`, `lib/mmgo/crafting.ex`, `lib/mmgo/alchemy.ex`, `lib/mmgo/bases.ex` |
| Education and social systems | `lib/mmgo/academy.ex`, `lib/mmgo/academia.ex`, `lib/mmgo/clubs.ex`, `lib/mmgo/organizations.ex`, `lib/mmgo/parties.ex` |
| External gateways | `lib/mmgo/telegram.ex`, `lib/mmgo/telegram/`, `lib/mmgo/ai.ex`, `lib/mmgo/ai/`, `lib/mmgo/federation.ex`, `lib/mmgo/federation/` |
| Map source and tooling | `lib/mmgo/world_map.ex`, `lib/mmgo/world_map/`, `lib/mix/tasks/mmgo.gen_map.ex` |

## Phoenix web layout

- `lib/mmgo_web.ex` defines the shared `:controller`, `:live_view`, `:html`, and verified-route imports used by web modules.
- `lib/mmgo_web/endpoint.ex` owns HTTP parsing, cookie sessions, static serving, telemetry, LiveView socket setup, and router dispatch.
- `lib/mmgo_web/router.ex` is the complete route map; it names browser, JSON API, session-backed demo API, and development-only scopes.
- HTTP controllers live in `lib/mmgo_web/controllers/`, including `play_demo_controller.ex`, `play_api_controller.ex`, `telegram_webhook_controller.ex`, `federation_controller.ex`, and `health_controller.ex`.
- Browser screens are one LiveView module per file under `lib/mmgo_web/live/`, following names such as `map_live.ex`, `spellbook_live.ex`, `duel_live.ex`, and `travel_live.ex`.
- Reusable rendered UI belongs in `lib/mmgo_web/components/`: `layouts.ex`, `core_components.ex`, and `ui_kit.ex`; the root layout template is `lib/mmgo_web/components/layouts/root.html.heex`.
- `lib/mmgo_web/live/location_gate.ex` is a shared location-aware web helper rather than a separate routeable screen.

## Client and static layout

- `assets/js/app.js` is the JavaScript bundle entrypoint; hook registration is centralized in `assets/js/hooks/index.js`.
- Interaction-specific hooks have descriptive kebab-case names in `assets/js/hooks/`, for example `hex-map.js`, `play-map.js`, `combat-log.js`, and `map-editor.js`.
- Hex rendering helpers are grouped separately in `assets/js/hex/`.
- `assets/css/app.css` is the CSS bundle entrypoint and imports design tokens plus screen-family files from `assets/css/screens/`.
- Public assets are served from `priv/static/`, with map data at `priv/static/maps/world.json`, sprite metadata at `priv/static/sprites/manifest.json`, and compiled bundles under `priv/static/assets/`.

## Configuration, data, and tests

- Base configuration is `config/config.exs`; development, test, production, and environment-variable handling are in `config/dev.exs`, `config/test.exs`, `config/prod.exs`, and `config/runtime.exs`.
- `compose.yaml` provisions local PostgreSQL; Ecto migrations are ordered timestamped files in `priv/repo/migrations/` and seed data is in `priv/repo/seeds.exs`.
- Realm manifests are stored in `priv/realms/` and are handled by `lib/mix/tasks/mmgo.realm.apply.ex`, `mmgo.realm.export.ex`, and `mmgo.realm.validate.ex`.
- Domain tests mirror contexts under `test/mmgo/`, with focused nested directories such as `test/mmgo/combat/` and `test/mmgo/world_map/`.
- Web tests mirror delivery types under `test/mmgo_web/controllers/` and `test/mmgo_web/live/`; test setup is shared by `test/support/data_case.ex` and `test/support/conn_case.ex`.
- Product and implementation references live in `docs/`, notably `docs/MMGO_GDD.md`, `docs/TECH_ARCHITECTURE.md`, `docs/UI_DESIGN_BRIEF.md`, and `docs/playable_demo_loop.md`.
