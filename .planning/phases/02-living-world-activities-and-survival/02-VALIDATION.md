---
phase: 2
slug: living-world-activities-and-survival
status: approved
nyquist_compliant: true
created: 2026-07-10
---

# Phase 2 — Validation Strategy

## Focused commands

- Clock/world facade: `mix test test/mmgo/travel/clock_test.exs test/mmgo/play_test.exs`
- Survival/travel: `mix test test/mmgo/survival_test.exs test/mmgo/travel_test.exs test/mmgo_web/live/travel_live_test.exs test/mmgo_web/live/inventory_live_test.exs`
- Activities/overworld: `mix test test/mmgo/events_test.exs test/mmgo/scavenging_test.exs test/mmgo/overworld_test.exs test/mmgo_web/live/action_hub_live_test.exs test/mmgo_web/live/map_live_test.exs`
- Full phase: `mix precommit`

## Requirement evidence

| Requirement | Evidence |
|-------------|----------|
| WORLD-01 | fixed-time calendar unit test plus scoped map clock assertion |
| WORLD-02 | map/travel state test uses non-default scoped realm and route/location data |
| WORLD-03 | map facade/LiveView tests exercise nearby actor, notification, and no-fixture empty state |
| WORLD-04 | hub test resolves only current-location event options and trusted routes |
| WORLD-05 | two-player context/LiveView test creates/responds to legal overworld encounter and rejects unsafe/disabled attack |
| SURV-01 | travel unit tests cover short food, first-day movement penalty, second-day health penalty, and recovery |
| SURV-02 | hub test starts/completes persisted scavenging and checks XP/loot/status |
| SURV-03 | survival/travel/inventory tests show carried load and authoritative movement/flee flags |

## Guardrails

- No `Process.sleep/1`; force worker completion with injected time or direct worker/domain call.
- Tests use two matching account/character scope sessions for player-interaction cases.
- Every new migration has a domain test proving its durable state is applied idempotently.
- `mix format --check-formatted`, `git diff --check`, and `mix precommit` are required before Phase 2 completion.
