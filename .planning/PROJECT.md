# MMGO — Ministry of MaGic Online

## What This Is

MMGO is a server-authoritative, text-first MMO played through a Telegram Mini App and bot. Players inhabit persistent realms: they travel a hex world, study or craft, build spell libraries and loadouts, form parties, trade, descend into a living dungeon, and eventually create organisations that shape the realm.

The Phoenix application is now an alpha-complete, account-owned player product built on substantial persisted domain logic. Demo-only screens have been replaced by real gameplay, and the GDD mechanics selected for the alpha contract are implemented and verified.

## Core Value

A player can make meaningful, account-owned decisions in a persistent social magical world—from travel and preparation through combat, dungeon expeditions, trade, and long-term organisations—and see the consequences reflected immediately in the game.

## Requirements

### Validated

- ✓ Server-authoritative persisted worlds, characters, inventory, economy, travel, and background work exist — existing codebase.
- ✓ The map renders an interactive hex world and can start real server-timed journeys — existing codebase.
- ✓ A thin `MMGO.Play` orchestration facade can supply a browser gameplay loop without moving rules into LiveViews — existing codebase.
- ✓ Core backend contexts exist for combat, spells, grimoires, survival, crafting, alchemy, academy, dungeon, party, organisations, notifications, and federation — existing codebase.

### Alpha Milestone Validated

- [x] A real Telegram Mini App player can enter an account-owned, location-gated game session instead of a shared demo session.
- [x] Every GDD player activity has an authoritative command/read model and a playable LiveView surface.
- [x] Combat supports the GDD's simultaneous timed turns, caster and tool-user inputs, runtime AI orchestration/narration, and meaningful combat locations.
- [x] The map reflects live player, event, realm, calendar, and organisation information rather than hard-coded demo overlays.
- [x] Social systems, economy, survival, dungeon expeditions, Academy careers, and organisations work as connected player loops.
- [x] The product remains testable locally using mock AI and deterministic fixtures, with external credentials only required for deployment.

### Out of Scope

- Purchasing, storing, or distributing copyrighted soundtrack recordings — the code will provide semantic audio cues and a legal asset interface, while actual licensed recordings remain an operations/content decision.
- Pay-to-win, premium currency, loot boxes, and real-money gameplay advantages — prohibited by the GDD.
- Committing secrets, Telegram credentials, AI keys, or deployment-only federation tokens — production configuration remains environment-owned.

## Context

- The product specification is `docs/MMGO_GDD.md`; it is the source of truth for the completion target, including the organisation v2–v4 roadmap because the user explicitly requested that everything be finished.
- `docs/playable_demo_loop.md` and the current `MMGO.Play` surface describe a useful but intentionally limited real slice: map → travel → inventory → local duel.
- The codebase map in `.planning/codebase/` documents a Phoenix 1.8 / LiveView / Ecto / PostgreSQL / Oban modular monolith with broad domain coverage.
- The major gap is product integration, not a lack of domain contexts. New browser flows must consume thin application facades or explicit context APIs.
- The GDD asks for runtime AI spell resolution and narration, while the current README describes author-time compilation plus deterministic resolution. The completion effort resolves that divergence by preserving deterministic validation/limits while adding provider-backed runtime orchestration behind an injectable boundary.

## Constraints

- **Architecture**: Preserve context ownership and the `MMGO.Play`-style thin orchestration boundary — LiveViews must not become domain-rule containers.
- **Platform**: Remain Phoenix LiveView, PostgreSQL/Ecto, Oban, Tailwind, and the existing bundled JS pipeline — avoid needless dependencies.
- **Security**: Browser actions must derive character ownership from an authenticated session; never trust player IDs, opponent IDs, or realm IDs from the client.
- **AI reliability**: AI outputs must remain schema-constrained, auditable, mockable, and bounded by deterministic engine rules.
- **Quality**: Add focused domain and LiveView integration tests per vertical slice; run `mix precommit` once shared changes stabilize.
- **Scope**: Implement the literal GDD target in phases, including organisations v2–v4, while marking unresolved narrative/content tuning choices as configurable defaults rather than blockers.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Treat `docs/MMGO_GDD.md` as the completion contract | The user asked to finish everything after a GDD audit | ✓ Good |
| Prioritize real account ownership before visual rewrites | Shared demo sessions make every other browser loop unsafe or non-persistent | ✓ Good |
| Wire existing contexts through small facades | Preserves server authority and prevents web-layer sprawl | ✓ Good |
| Keep deterministic engine limits around AI decisions | The GDD requires AI flavor and orchestration without permitting arbitrary state mutation | ✓ Good |
| Ship a semantic audio system before content recordings | It delivers GDD state-driven behavior without unsafe licensing assumptions | ✓ Good |
| Tax rate is realm-configurable, canonical default 5% | Owner decision 2026-07-13; consistent with §6.1 operator customization; matches current `Play` default | ✓ Good |
| Black market uses probabilistic NPC detection (catch chance scales with deal size; fine = multiple of evaded tax + reputation hit) | Owner decision 2026-07-13; deterministic and testable for Phase 5; org enforcement layers on later | ✓ Good |
| Bases: city purchase is coins-only; building requires coins + materials + game-time construction | Owner decision 2026-07-13; full GDD fidelity, Phase 5 must design material requirements | ✓ Good |
| Alchemy is AI-interpreted brewing over fixed per-item primitives, ingredients picked from inventory | Owner decision 2026-07-13; mirrors spell compiler boundary — AI composes within constant item properties, never invents effects | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-22 after alpha 0.1.0-alpha.1 implementation and release verification*
