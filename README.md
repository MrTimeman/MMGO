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
- `lib/mmgo/spells` - compiled spells and runtime rules
- `lib/mmgo/combat` - deterministic combat engine and persistence
- `lib/mmgo/ai` - provider abstraction, prompts, Gemini client, and audit logs
- `lib/mmgo/worlds` - realm setup and world bootstrap
- `lib/mmgo/telegram` - Telegram client and webhook update handling
- `lib/mmgo_web` - web controllers, router, layouts, and HTTP entrypoints
- `docs/TECH_ARCHITECTURE.md` - current technical direction

## Current conventions

- server-authoritative simulation
- compiled deterministic spells later, not LLM-driven runtime combat
- append-only combat and ledger systems planned from the start
- `Req` for outbound HTTP requests
- `mix precommit` as the main local verification command
