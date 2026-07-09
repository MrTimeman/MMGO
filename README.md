# MMGO — Ministry of MaGic Online

A server-authoritative magic MMO roleplay engine built with Elixir/Phoenix, Telegram Mini App frontend, and AI-compiled spells.

> **Status:** foundation complete — core game systems, Telegram bot integration, and first frontend surfaces are live.

## Architecture

MMGO is a deterministic, event-sourced game server. Spells are compiled from player descriptions into validated schemas at authoring time (not LLM-at-runtime). All game state is persisted via Ecto/PostgreSQL, with Oban for deferred job scheduling.

```
┌──────────────────────┐     ┌──────────────────────┐
│  Telegram Bot (MVP)  │     │  Phoenix LiveView    │
│  /travel /duel /shop │────▶│  Map, Spellbook, ... │
│  /party /dungeon ... │     │  Mobile-first (375px)│
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
│  (Ecto/ETS)    │          │  Journeys,     │
│                │          │  Brewing,      │
│                │          │  Construction  │
└────────────────┘          └────────────────┘
```

## Domain map

- **Accounts** — account, identity, character provisioning with Telegram linking
- **World** — realms, locations, routes, scheduled journey completions
- **Combat** — deterministic turn engine with tool-user actions, AI narration
- **Spells** — compiled schemas from player-authored descriptions, runtime validation
- **Grimoires** — loadouts of prepared spells per character
- **Economy** — append-only ledgers, treasury accounts, exchange rates, migration
- **Inventory** — item templates, carry capacity, encumbrance
- **Market & Black Market** — taxed listings, escrow, untaxed deals with default risk
- **Dungeons** — graph-based runs with links, nodes, encounters, resources, loot
- **PvP** — duel challenges, wager escrow, settlement
- **Academy** — enrollments, specializations, timed completion
- **Academia** — research, publications, professor progression
- **Alchemy** — workspaces, recipes, brewing jobs
- **Bases** — ownership, construction, protection
- **Academy Clubs & Organizations** — social groups, hierarchies, travel networks
- **Overworld** — road encounters, ambushes, scavenging
- **Survival** — food consumption, carry capacity
- **Reputation** — crime records, fines, market sanctions
- **Notifications** — outbox delivery via Telegram
- **AI** — provider abstraction (Gemini + Mock), prompt pipelines, audit logs
- **Operator** — live reports, maintenance sweeps, observability

## Requirements

- **Elixir** 1.19+ (1.20.0 used in dev)
- **Erlang/OTP** 28+
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
| `POST /api/telegram/webhook` | Telegram bot webhook handler |
| `GET /` | Phoenix LiveView frontend |

## AI configuration

By default the app uses a mock AI provider for local dev. Set `GEMINI_API_KEY` to switch to the Gemini provider at runtime.

| Env var | Default |
|---|---|
| `GEMINI_API_KEY` | _(unset — uses mock)_ |
| `GEMINI_API_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta` |
| `GEMINI_SPELL_MODEL` | `gemini-3-flash` |
| `GEMINI_NARRATION_MODEL` | `g3f-lite` |

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
- **Deterministic spells** — spells are compiled from author descriptions into validated schemas, not run through an LLM at combat time
- **Append-only** — combat logs and economy ledgers are append-only for auditability
- **Mobile-first** — the LiveView frontend targets Telegram Mini App at ~375px touch viewport
- **Location-gated** — actions live at physical map locations, not in global nav bars

## License

See [`LICENSE`](LICENSE) (if present) or contact the project owner.
