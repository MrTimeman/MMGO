---
phase: 02-living-world-activities-and-survival
verified: 2026-07-10
status: passed
---

# Phase 2 Verification

## Automated evidence

- Canonical clock, scoped map, event lifecycle, survival, scavenging, overworld, and affected LiveViews:
  `mix test test/mmgo/travel/clock_test.exs test/mmgo/play_test.exs test/mmgo/events_test.exs test/mmgo/survival_test.exs test/mmgo/travel_test.exs test/mmgo/travel_survival_test.exs test/mmgo/scavenging_test.exs test/mmgo/overworld_test.exs test/mmgo_web/live/map_live_test.exs test/mmgo_web/live/action_hub_live_test.exs test/mmgo_web/live/travel_live_test.exs test/mmgo_web/live/inventory_live_test.exs`
  — 61 passed.
- Project-wide test suite completed after the event-copy expectation update; `mix test --failed` reports no failed tests.
- Formatting and diff validation have been run during the phase. The sandbox can intermittently deny Mix's TCP filesystem lock when invoking the aggregate alias; this is an environment limitation, not a test failure.

## Must-have evidence

| Requirement | Evidence |
|---|---|
| WORLD-01 / WORLD-02 | `Clock.world_time/2`, scoped `Play.world_hub_state/1`, and `MapLiveTest` cover canonical clock, scoped realm/location, routes, and journey state. |
| WORLD-03 / WORLD-05 | Current-location nearby query, scope-safe encounter facade, persistent Overworld responses, realm PvP rule and safe-zone tests. |
| WORLD-04 | Persistent text event lifecycle, server-owned actions, current-location ActivityHub, and explicit city/base/Tower/wilderness/dungeon-entrance templates. |
| SURV-01 (travel portion) | Underfed travel records movement delay and day-two-plus non-lethal drain, applies it once at arrival, and resets after a food grant. |
| SURV-02 | Scoped cache start, active-attempt state, worker completion, durable loot/XP result, and ActivityHub tests. |
| SURV-03 | Realm-shaped capacity, inventory/grimoire weight, real food, overload, and flee availability are exposed in map/activity/travel/inventory read models. |

## Remaining cross-phase integration

- Dungeon expedition food depletion will call the Phase 2 reusable survival API during Phase 7 instead of pretending an unfinished expedition loop is complete here.
