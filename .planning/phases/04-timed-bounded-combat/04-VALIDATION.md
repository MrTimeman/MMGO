---
phase: 04-timed-bounded-combat
slug: timed-bounded-combat
status: passed
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-10
---

# Phase 4 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit, `Phoenix.LiveViewTest`, Ecto SQL Sandbox, Oban manual testing |
| Config | `config/test.exs` uses `Oban, testing: :manual` and `MMGO.AI.Providers.Mock` |
| Turn-time control | Inject `now` into domain/worker calls; no `Process.sleep/1` |
| Concurrent test control | `Task.async_stream/3` or monitored tasks after `Ecto.Adapters.SQL.Sandbox.allow/3` |
| Full gate | `mix precommit` |

## Focused commands

- Timed lifecycle: `mix test test/mmgo/combat_test.exs test/mmgo/combat/resolve_turn_worker_test.exs`
- Normalized actions/engine: `mix test test/mmgo/combat/action_snapshot_test.exs test/mmgo/combat/engine_test.exs test/mmgo/tool_actions_test.exs`
- Runtime AI/narration: `mix test test/mmgo/combat/orchestrator_test.exs test/mmgo/combat/narrator_test.exs`
- Browser/modes: `mix test test/mmgo/play_test.exs test/mmgo_web/live/combat_live_test.exs test/mmgo_web/live/duel_live_test.exs test/mmgo_web/live/action_hub_live_test.exs test/mmgo/dungeon_combat_integration_test.exs test/mmgo/clubs_test.exs`
- Full Phase 4 suite: combine the four commands above, then `mix precommit`

## Requirement evidence

| Requirement | Plan | Automated evidence |
|-------------|------|--------------------|
| MAGIC-03 | 04-03 | constrained runtime result accepts only engine budgets; provider/schema failures persist a deterministic fallback and audit record |
| COMBAT-01 | 04-01 | stale requested turn rejects; deadline produces durable waits; concurrent submit/resolve/worker calls make one outcome and one next turn |
| COMBAT-02 | 04-02, 04-04 | owned prepared base/incantation and owned item/action/target forms are normalized server-side and rendered from scope-owned state |
| COMBAT-03 | 04-02, 04-04 | tests cover magic-zone rejection, shared HP/states/cooldowns/environment order, safe-zone/overload flee policy, and mode stakes |
| COMBAT-04 | 04-03 | mock structured AI output, invalid/failing provider fallback, persisted Russian narration, and token reuse are asserted |
| COMBAT-05 | 04-04 | scoped duel/overworld/dungeon/club participant and spectator flows show sealed/resolved outcome and correct finalizer behavior |
| QUALITY-02 | 04-03 | README test/review assertion records bounded runtime AI plus deterministic engine/fallback contract |

## Per-task verification map

| Task ID | Plan | Wave | Requirement | Test type | Automated command | File status |
|---------|------|------|-------------|-----------|-------------------|-------------|
| 04-01-01 | 01 | 1 | COMBAT-01 | migration/domain | `mix test test/mmgo/combat_test.exs test/mmgo/combat/resolve_turn_worker_test.exs` | one new test file |
| 04-01-02 | 01 | 1 | COMBAT-01 | concurrency/worker | `mix test test/mmgo/combat_test.exs test/mmgo/combat/resolve_turn_worker_test.exs` | one new test file |
| 04-02-01 | 02 | 2 | COMBAT-02, COMBAT-03 | unit/domain | `mix test test/mmgo/combat/action_snapshot_test.exs test/mmgo/tool_actions_test.exs` | one new test file |
| 04-02-02 | 02 | 2 | COMBAT-01, COMBAT-03 | engine | `mix test test/mmgo/combat/engine_test.exs test/mmgo/combat_test.exs` | existing files |
| 04-03-01 | 03 | 3 | MAGIC-03, COMBAT-04 | unit/provider | `mix test test/mmgo/combat/orchestrator_test.exs test/mmgo/combat/narrator_test.exs` | one new test file |
| 04-03-02 | 03 | 3 | QUALITY-02 | documentation/contract | `mix test test/mmgo/combat/orchestrator_test.exs` | existing/new tests |
| 04-04-01 | 04 | 4 | COMBAT-05 | domain/integration | `mix test test/mmgo/play_test.exs test/mmgo/dungeon_combat_integration_test.exs test/mmgo/clubs_test.exs` | existing files |
| 04-04-02 | 04 | 4 | COMBAT-02, COMBAT-05 | LiveView | `mix test test/mmgo_web/live/combat_live_test.exs test/mmgo_web/live/duel_live_test.exs test/mmgo_web/live/action_hub_live_test.exs` | one new test file |

## Guardrails

- A stale resolver test is mandatory before any timer UI work: calling resolution for an old turn after the combat advances must return `{:error, :turn_closed}` (or the exact documented stale error) and must not resolve the new turn.
- Never test real time with sleeps. Pass a fixed `now`, invoke `ResolveTurnWorker.perform/1` directly, and assert durable row state/events.
- No AI call may occur while a combat/turn row lock is held. Tests must prove malformed/provider-failed output does not leave a turn permanently `:resolving`.
- Assertions use stable DOM IDs with `element/2`/`has_element?/2`, not raw full HTML or translated prose.
- Every generated migration is created through `mix ecto.gen.migration`; include a domain test for its durable/idempotent state.
- Finish with `mix format --check-formatted`, `git diff --check`, and `mix precommit`; distinguish an environment-level Mix filesystem-lock failure from a code failure.

## Validation Sign-Off

- [x] All requirements map to at least one plan and focused test command.
- [x] No three-task verification gap exists.
- [x] Existing Oban/AI mock infrastructure covers all external boundaries.
- [x] `nyquist_compliant: true` is set.

**Approval:** passed 2026-07-11 — focused combat/browser suites and project-wide `mix precommit` (381 tests) passed; `git diff --check` passed.
