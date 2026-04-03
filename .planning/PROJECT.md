# MMGO

## What This Is

MMGO is a Telegram-native, text-forward online RPG built as a Phoenix and LiveView application with a companion Telegram bot. It combines a server-authoritative simulation layer with AI-assisted spell authoring, long-running progression systems, and a player-driven social economy. The current codebase already contains a large portion of the backend world model; the remaining product work is to turn that foundation into a coherent, playable Mini App experience.

## Core Value

Players can inhabit a persistent magical world where creative spell expression, meaningful trade-offs, and social interdependence feel deeper than a typical chat game while remaining fair, deterministic, and operable.

## Requirements

### Validated

- [x] Phoenix, LiveView, PostgreSQL, Oban, and Req are already in place as the runtime foundation for MMGO.
- [x] Server-authoritative backend domains already exist for travel, spells, economy, dungeons, parties, organizations, reputation, and PvP systems.
- [x] Telegram webhook handling, command flows, and notification delivery hooks already exercise core gameplay systems without the Mini App UI.

### Active

- [ ] Ship a player-facing Telegram Mini App shell that turns existing account, travel, and recovery flows into a usable session.
- [ ] Expose spellcraft, progression, economy, and expedition systems as end-to-end player workflows rather than backend-only capabilities.
- [ ] Harden notifications, federation, and operator recovery paths for live-service readiness.

### Out of Scope

- Native iOS and Android apps - Telegram Mini App is the launch client and keeps scope focused.
- Microservice decomposition - the simulation model is still evolving and a modular monolith is simpler to operate.
- Runtime LLM authority over combat turns - runtime resolution must stay deterministic, fair, and cheap.
- Pay-to-win monetization - the design pillars explicitly reject mechanical advantage for real-money spend.

## Context

The repository already includes a substantial brownfield backend for the MMGO world model: travel, dungeons, economy, organizations, crafting, alchemy, notifications, PvP, federation, and operator tooling are represented in code and migrations. Product intent is documented in `docs/MMGO_GDD.md`, while `docs/TECH_ARCHITECTURE.md` locks the major architectural choices around server authority, deterministic runtime behavior, and AI-assisted authoring.

The current browser surface is still thin. The main web entry is a bootstrap landing page plus a hook-driven component showcase, while Telegram commands remain the practical way to exercise many gameplay loops. The immediate project need is not new invention at the data-model layer; it is integrating the existing systems into a usable Telegram Mini App experience with clear player flows, failure states, and live-service readiness.

## Constraints

- **Tech stack**: Phoenix 1.8, LiveView, PostgreSQL, Oban, and Req - the current codebase and project instructions lock these in.
- **Platform**: Telegram Mini App plus Telegram bot first - primary player flows must work inside Telegram.
- **Simulation model**: Server-authoritative, timestamp-driven world progression - travel, jobs, and long-running actions must remain auditable and recoverable.
- **AI usage**: AI assists spell authoring and narration, not turn-by-turn runtime authority - combat and world resolution must remain deterministic.
- **Product**: Free-to-play with donation-only support - no premium gameplay shortcuts or pay-to-win mechanics.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Telegram Mini App plus Telegram bot is the primary client surface | It matches the intended audience and supports asynchronous world interactions, reminders, and deep links | Pending |
| MMGO stays a modular monolith in Phoenix and LiveView | The existing simulation domains are tightly coupled and benefit from OTP supervision and lower operational overhead | Good |
| AI is used at authoring and narration boundaries, not as runtime combat authority | This preserves fairness, replayability, and predictable cost while keeping AI as a product differentiator | Good |
| Time-based world progression is modeled with persisted timestamps and scheduled jobs | Travel, study, crafting, and other long-running actions are cheaper and easier to audit this way than with a global tick loop | Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-03 after initialization*
