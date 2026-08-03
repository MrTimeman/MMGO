# MMGO — Ministry of MaGic Online

A server-authoritative magic MMO roleplay engine built with Elixir/Phoenix, Telegram Mini App frontend, and AI-compiled spells.

> **Статус:** `0.1.0-alpha.8` — закрытая альфа с Telegram-аутентификацией, устойчивым созданием заклинаний и разбираемой по категориям игровой почтой. Производственные секреты хранятся вне репозитория.

## Architecture

MMGO is a deterministic, server-authoritative game server. Spells and ingredient mixtures are interpreted into validated schemas; during combat, a bounded runtime-AI layer may describe only already-approved snapshot effects and Russian narration. It cannot alter targets, costs, rewards, shared HP, or state primitives, and deterministic fallbacks are persisted when a provider fails. Game state is persisted via Ecto/PostgreSQL, with Oban for deferred work.

```
┌──────────────────────┐     ┌──────────────────────┐
│  Telegram companion  │     │  Phoenix LiveView    │
│ /status /routes ...  │────▶│ Map, actions, items  │
│  + Mini App launch   │     │  Mobile-first (375px)│
└──────────────────────┘     └──────────────────────┘
         │                            │
         ▼                            ▼
┌──────────────────────────────────────────────┐
│              Game Engine                      │
│  Combat · Economy · Travel · Dungeons · PvP  │
│  Spells · Grimoires · Academy · Alchemy       │
│  Scavenging · Reputation · Black Market       │
│  Parties · Clubs · Organizations              │
└──────────────────────────────────────────────┘
         │                            │
         ▼                            ▼
┌────────────────┐          ┌────────────────┐
│  PostgreSQL    │          │  Oban Workers  │
│  (Ecto)        │          │  Journeys,     │
│                │          │  Brewing,      │
│                │          │  Construction  │
└────────────────┘          └────────────────┘
```

## Domain map

- **Accounts** — account, identity, character provisioning with Telegram linking
- **World** — realms, locations, routes, scheduled journey completions
- **Combat** — deterministic timed turn engine, immutable action snapshots, bounded AI orchestration, Russian narration
- **Spells** — compiled schemas from player-authored descriptions, runtime validation
- **Grimoires** — loadouts of prepared spells per character
- **Economy** — append-only ledgers, treasury accounts, exchange rates, migration
- **Inventory** — item templates, carry capacity, encumbrance
- **Market & Black Market** — realm-taxed listings, escrow, untaxed deals with detection/default risk
- **Dungeons** — graph-based runs with links, nodes, encounters, resources, loot
- **PvP** — duel challenges, wager escrow, settlement
- **Academy** — enrollments, specializations, timed completion
- **Academia** — research, publications, professor progression
- **Alchemy** — fixed ingredient primitives, schema-bounded AI interpretation, durable brewing jobs
- **Bases** — taxed purchase, coin/material construction, ownership, storage, protection
- **Academy Clubs & Organizations** — social groups, hierarchies, travel networks
- **Overworld** — road encounters, ambushes, scavenging
- **Survival** — food consumption, carry capacity
- **Reputation** — crime records, fines, market sanctions
- **Notifications** — outbox delivery via Telegram
- **AI** — provider abstraction (Gemini, DeepSeek, Mock), bounded prompt pipelines, audit logs
- **Operator** — live reports, maintenance sweeps, observability

## Requirements

- **Elixir** 1.20.x
- **Erlang/OTP** 29.x
- **PostgreSQL** 16 (Docker compose provided)
- **Docker Desktop** or local PostgreSQL

## Quick start

```bash
# Start PostgreSQL
docker compose up -d postgres

# Optionally copy and edit local env
cp .env.example .env

# Install deps, create DB, run migrations
mix setup

# Start the Phoenix server
mix phx.server
```

Then open **http://localhost:4000**.

### Useful commands

| Command | What it does |
|---|---|
| `mix test` | Run the test suite |
| `mix precommit` | Full check: compile, format, test |
| `mix format` | Format all Elixir sources |
| `iex -S mix phx.server` | Dev server with IEx shell |

### Realm manifest tools

```bash
mix mmgo.realm.validate priv/realms/starter_realm_manifest.json
mix mmgo.realm.apply priv/realms/starter_realm_manifest.json --set-default
mix mmgo.realm.export canonical priv/realms/canonical_export.json
```

## Key endpoints

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Health check |
| `GET /livez` | Process liveness check |
| `POST /api/telegram/webhook` | Telegram bot webhook handler |
| `GET /` | Phoenix LiveView frontend |

## AI configuration

By default the app uses a mock AI provider for local development and tests. The
supported production provider is DeepSeek and production startup requires a
nonblank `DEEPSEEK_API_KEY`, unless the operator explicitly enables the
fallback-only escape hatch. Empty or whitespace-only AI variables are treated
as unset, so a blank model override cannot shadow the production default.

Telegram Mini App entry validates `Telegram.WebApp.initData` with Telegram's
documented `WebAppData` HMAC derivation. A verified login creates or resumes the
account and refreshes the signed Telegram profile name, username, locale, and
avatar URL.

| Env var | Default |
|---|---|
| `DEEPSEEK_API_KEY` | _(required in production)_ |
| `AI_SPELL_MODEL` | `deepseek-chat` with DeepSeek |
| `AI_ALCHEMY_MODEL` | `deepseek-chat` with DeepSeek |
| `AI_COMBAT_MODEL` | `deepseek-chat` with DeepSeek |
| `AI_NARRATION_MODEL` | `deepseek-chat` with DeepSeek |
| `GEMINI_API_KEY` | _(optional for local development)_ |
| `GEMINI_API_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta` |
| `GEMINI_SPELL_MODEL` | `gemini-3-flash` |
| `GEMINI_ALCHEMY_MODEL` | `gemini-3-flash` |
| `GEMINI_COMBAT_MODEL` | `g3f-lite` |
| `GEMINI_NARRATION_MODEL` | `g3f-lite` |

## Alpha release

The checked-in `Dockerfile` builds an OTP release with compiled assets. See [Alpha scope](docs/ALPHA_SCOPE.md) for the acceptance boundary and [Deployment](docs/DEPLOYMENT.md) for required variables, migrations, seeding, health checks, and rollback guidance.

## Project structure

```text
lib/
├── mmgo/              # Core domain logic
│   ├── accounts/      # Accounts, identities, characters
│   ├── academy/       # Education, specializations
│   ├── academia/      # Research, publications
│   ├── actors/        # Enemy/NPC templates
│   ├── ai/            # AI provider abstraction
│   ├── alchemy/       # Potion brewing
│   ├── bases/         # Property, construction
│   ├── black_market/  # Untaxed deals
│   ├── clubs/         # Social clubs
│   ├── combat/        # Deterministic combat engine
│   ├── dungeons/      # Dungeon graph & runs
│   ├── economy/       # Treasury, ledgers
│   ├── events/        # Non-combat text events
│   ├── federation/    # Inter-realm travel
│   ├── grimoires/     # Spell loadouts
│   ├── inventory/     # Items, templates
│   ├── market/        # Taxed listings
│   ├── notifications/ # Telegram delivery
│   ├── npc_shops/     # Shop, tuition
│   ├── operator/      # Reports, sweeps
│   ├── organizations/ # Hierarchy, roles
│   ├── overworld/     # Road encounters
│   ├── parties/       # Party system
│   ├── progression/   # XP, milestones
│   ├── pvp/           # Duels, wagers
│   ├── reputation/    # Crime, sanctions
│   ├── scavenging/    # Resource caches
│   ├── spells/        # Compiled spell schemas
│   ├── survival/      # Food, carry capacity
│   ├── telegram/      # Bot commands & webhook
│   ├── travel/        # Journey engine
│   └── worlds/        # Realms, locations, routes
└── mmgo_web/          # Phoenix web layer
    ├── controllers/   # HTTP controllers
    └── live/          # LiveView pages & components
```

## Design conventions

- **Server-authoritative** — all game logic runs on the server; the frontend is a thin client
- **Bounded runtime AI** — combat mechanics use immutable server snapshots; AI may only produce schema-validated manifestations/narration within those limits, with deterministic fallback
- **Append-only** — combat logs and economy ledgers are append-only for auditability
- **Mobile-first** — the LiveView frontend targets Telegram Mini App at ~375px touch viewport
- **Location-gated** — actions live at physical map locations, not in global nav bars

## License

See [`LICENSE`](LICENSE) (if present) or contact the project owner.
