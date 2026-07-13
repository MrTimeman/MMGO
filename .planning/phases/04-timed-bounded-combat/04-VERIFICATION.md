---
phase: 04-timed-bounded-combat
verified: 2026-07-11
status: passed
---

# Phase 4 Verification

## Automated evidence

- Focused lifecycle, snapshot, orchestration, narration, mode, and Telegram command suites — **32 passed**.
- Project-wide `mix test` — **381 passed** (1 property, 380 tests).
- Project-wide `mix precommit` — **381 passed** (1 property, 380 tests).
- `git diff --check` — passed.

## Must-have evidence

| Requirement | Evidence |
|---|---|
| COMBAT-01 | `MMGO.Combat` records opened/deadline/locked/claimed/resolved lifecycle data, exact-turn resolution rejects stale snapshots, and `ResolveTurnWorker` materializes only missing waits at deadline. A normal resolver rejects an open turn. |
| COMBAT-02 / COMBAT-03 | `ActionSnapshot` validates ownership, prepared spells, targets, incantations, item actions, inventory reservations, and flee policy before persistence. `Engine` rehydrates only immutable snapshots and applies deterministic modes, HP, states, cooldowns, fatigue, and settlement. |
| MAGIC-03 / COMBAT-04 / QUALITY-02 | `Orchestrator`, `CombatTurnPrompt`, and `Narrator` constrain runtime AI to stored envelopes, audit provider output, and persist a Russian fallback without granting mechanical authority. README documents the same boundary. |
| COMBAT-05 | `Play`, `CombatLive`, and `DuelLive` provide scoped participant controls, read-only spectators, durable turn/narration/outcome display, real flee, and idempotent duel/dungeon/overworld/club finalization. |

## Deliberate implementation detail

The sandbox denied the migration generator's filesystem lock, so lifecycle timestamps are stored durably in the existing `combat_turns.resolution["lifecycle"]` map rather than a hand-authored migration. This preserves durable worker/retry semantics without bypassing project migration conventions.
