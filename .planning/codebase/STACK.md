# Technology Stack

## Snapshot

- MMGO is a server-authoritative web game built primarily in Elixir; the Mix application is `:mmgo` in `mix.exs`.
- The declared Elixir requirement is `~> 1.15`; the OTP supervision tree starts telemetry, the Ecto repo, DNS clustering, Phoenix PubSub, Oban, and the web endpoint in `lib/mmgo/application.ex`.
- The source is split between domain contexts under `lib/mmgo/` and Phoenix delivery code under `lib/mmgo_web/`.

## Backend and web runtime

- Phoenix `~> 1.8.5` supplies routing, controllers, HTML rendering, and request plugs; the router is `lib/mmgo_web/router.ex`.
- Phoenix LiveView `~> 1.1.0` drives the interactive game screens. The endpoint exposes the `/live` WebSocket and long-poll socket in `lib/mmgo_web/endpoint.ex`.
- Bandit `~> 1.5` is the configured HTTP server adapter (`config/config.exs`), rather than Cowboy.
- `Phoenix.PubSub` is started as `MMGO.PubSub`; no custom Phoenix Channel modules are currently wired in `assets/js/app.js`.
- JSON encoding/decoding is Jason `~> 1.2`, configured as Phoenix's JSON library in `config/config.exs`.
- Internationalization is provided by Gettext `~> 1.0` with translations under `priv/gettext/`.
- `Phoenix.HTML`, `phoenix_live_reload`, `phoenix_live_dashboard`, and Heroicons are included as Phoenix support dependencies in `mix.exs`.

## Persistence and background work

- Data storage is PostgreSQL through Ecto SQL `~> 3.13`, Phoenix Ecto `~> 4.5`, Postgrex, and `MMGO.Repo` (`lib/mmgo/repo.ex`).
- The project generator config uses UTC timestamps and binary IDs; account and character schemas explicitly use `:binary_id` in `lib/mmgo/accounts/account.ex` and `lib/mmgo/accounts/character.ex`.
- The repository has 35 Ecto migrations under `priv/repo/migrations/`, covering game state, accounts, notifications, federation, AI request logs, and Oban tables.
- Local development infrastructure is PostgreSQL 16 only, declared in `compose.yaml`; the app itself is started through Mix/Just rather than a checked-in application container.
- Oban `~> 2.20` persists jobs in the same repo. `config/config.exs` defines `default` (10) and `telegram` (5) queues plus the pruning plugin.
- Job workers include travel, crafting, alchemy, academia, and Telegram notification delivery, for example `lib/mmgo/notifications/delivery_worker.ex`.

## Frontend and asset pipeline

- Browser code is plain JavaScript, using Phoenix's `phoenix_html`, `phoenix`, and `phoenix_live_view` packages from `assets/js/app.js`.
- Bespoke LiveView hooks live in `assets/js/hooks/`; they cover map, combat, spell-circle, guild, travel, and editor interactions.
- esbuild `0.25.4` bundles to `priv/static/assets/js`; its config and ES2022 target are in `config/config.exs`.
- Tailwind `4.1.12` compiles `assets/css/app.css` to `priv/static/assets/css/app.css`; the file uses Tailwind v4 `@import` and `@source` syntax.
- UI styling is custom CSS plus Tailwind, split into screen-family files under `assets/css/screens/`.
- `assets/package.json` currently declares no npm dependencies; browser libraries are resolved from Phoenix assets/deps or committed vendor files.

## Configuration, operations, and observability

- Base configuration is in `config/config.exs`, with development, test, production, and release-time overrides in `config/dev.exs`, `config/test.exs`, `config/prod.exs`, and `config/runtime.exs`.
- Runtime configuration reads `PORT`, `PHX_SERVER`, `PHX_HOST`, `DATABASE_URL`, `POOL_SIZE`, `ECTO_IPV6`, `SECRET_KEY_BASE`, and `DNS_CLUSTER_QUERY` without storing production values in source.
- Production enables HTTPS enforcement and digested static assets in `config/prod.exs`; releases start the server when `PHX_SERVER` is set in `config/runtime.exs`.
- DNSCluster is installed for distributed-node discovery, but uses `:ignore` unless `DNS_CLUSTER_QUERY` is configured (`lib/mmgo/application.ex`).
- Telemetry Metrics and Telemetry Poller are installed. `lib/mmgo_web/telemetry.ex` polls every 10 seconds and defines Phoenix, repo, and VM metrics; no active external metrics reporter is configured there.
- A JSON health endpoint is available at `/healthz` through `lib/mmgo_web/controllers/health_controller.ex`.

## Tooling and test stack

- Mix aliases in `mix.exs` provide setup, database setup/reset, asset build/deploy, and `precommit` (`compile --warnings-as-errors`, unused-dependency unlock, format, test).
- `justfile` wraps the normal developer workflow: `just up` starts PostgreSQL, `just dev` runs `mix phx.server`, and `just check` runs `mix precommit`.
- Tests use ExUnit with Ecto SQL Sandbox (`config/test.exs`), Phoenix LiveViewTest/LazyHTML, StreamData, and Bypass. Test helpers are under `test/support/`.
- Map terrain and sprite catalog data are local JSON/static assets in `priv/static/maps/world.json` and `priv/static/sprites/`; `lib/mmgo/world_map.ex` caches parsed maps in `:persistent_term`.
