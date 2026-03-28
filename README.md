# MMGO

MMGO is a Phoenix-based foundation for Ministry of MaGic Online.

This repository currently includes:

- Phoenix + LiveView application scaffold
- PostgreSQL + Ecto setup
- Oban background jobs
- Telegram Bot API client and webhook endpoint
- foundational game data models for realms, accounts, Telegram identities, and characters
- grimoires and prepared spell loadouts
- compiled spell schemas and runtime validation
- deterministic combat state, turn, action, and event foundations
- inventory items, item templates, and deterministic tool-user combat actions
- append-only economy accounts, treasury, and ledger transfers
- world locations, routes, and scheduled journey completion
- parties, memberships, and expedition state snapshots
- dungeon graphs, run progression, and expedition node state
- dungeon encounter, resource, and loot state tied to runs
- dungeon encounters can now spawn real combat instances and resolve back into run state
- expedition XP reward shares tied to encounters and run completion
- academy enrollments, completion scheduling, and specialization state
- overworld scavenging, resource caches, and scheduled harvest completion
- notification outbox and Telegram delivery hooks for timed system completions
- food consumption, carry capacity, and encumbrance-aware travel planning
- legal market listings, taxed purchases, and inventory escrow reservations
- black market offers and unsafe untaxed delivery deals
- duel wagers, escrow, and taxed PvP settlement
- Telegram command handlers for exercising backend systems without the frontend
- operator reports and maintenance sweeps for observability and recovery
- AI request logging plus spell compiler and turn narrator interfaces
- automated tests for core account provisioning and webhook behavior

## Requirements

- Elixir 1.19+
- Erlang/OTP 28+
- Docker Desktop or another local PostgreSQL instance

## Local setup

1. Start PostgreSQL:

   ```bash
   docker compose up -d postgres
   ```

2. Copy local environment values if you want to override defaults:

   ```bash
   cp .env.example .env
   ```

3. Install dependencies and set up the database:

   ```bash
   mix setup
   ```

4. Start the Phoenix server:

   ```bash
   mix phx.server
   ```

Then open `http://localhost:4000`.

## Useful commands

```bash
mix test
mix precommit
iex -S mix phx.server
```

## Key endpoints

- `GET /healthz`
- `POST /api/telegram/webhook`

## AI configuration

- default local development uses the mock AI provider
- set `GEMINI_API_KEY` to switch the runtime to the Gemini provider automatically
- optional overrides:
  - `GEMINI_API_BASE_URL`
  - `GEMINI_SPELL_MODEL`
  - `GEMINI_NARRATION_MODEL`

## Project structure

- `lib/mmgo/accounts` - account, identity, and character domain logic
- `lib/mmgo/grimoires` - prepared spellbooks and combat loadouts
- `lib/mmgo/inventory` - item templates, inventory state, and tool action definitions
- `lib/mmgo/economy` - treasury accounts, cached balances, and append-only ledger entries
- `lib/mmgo/academy` - education progression, timed enrollments, and specialization state
- `lib/mmgo/survival` - food consumption, carry capacity, and supply calculations
- `lib/mmgo/market` - legal listings, escrowed inventory, and taxed settlement
- `lib/mmgo/black_market` - untaxed unsafe deals with manual delivery and scam/default risk
- `lib/mmgo/pvp` - duel challenges, wager escrow, and PvP settlement workflows
- `lib/mmgo/notifications` - notification queueing, formatting, and Telegram delivery
- `lib/mmgo/operator` - live reports, maintenance sweeps, and operator audit events
- `lib/mmgo/telegram/commands.ex` - command-driven access to travel, academy, party, dungeon, and combat loops
- `lib/mmgo/scavenging` - location resource caches and timed scavenging attempts
- `lib/mmgo/parties` - party formation, active memberships, and expeditions
- `lib/mmgo/dungeons` - dungeon graphs, runs, links, and per-node expedition state
- `lib/mmgo/dungeons` - encounter, resource, and loot state for dungeon runs
- `lib/mmgo/travel` - compressed-time helpers, journeys, and completion workers
- `lib/mmgo/spells` - compiled spells and runtime rules
- `lib/mmgo/combat` - deterministic combat engine and persistence
- `lib/mmgo/ai` - provider abstraction, prompts, Gemini client, and audit logs
- `lib/mmgo/worlds` - realms, locations, and route graph bootstrap
- `lib/mmgo/telegram` - Telegram client and webhook update handling
- `lib/mmgo_web` - web controllers, router, layouts, and HTTP entrypoints
- `docs/TECH_ARCHITECTURE.md` - current technical direction

## Current conventions

- server-authoritative simulation
- compiled deterministic spells later, not LLM-driven runtime combat
- append-only combat and ledger systems planned from the start
- `Req` for outbound HTTP requests
- `mix precommit` as the main local verification command
