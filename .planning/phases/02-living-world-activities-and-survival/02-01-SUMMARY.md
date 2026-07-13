---
phase: 02-living-world-activities-and-survival
plan: "01"
subsystem: world
tags: [world-clock, map, current-scope, liveview, presence]
provides:
  - "Canonical 13-month world calendar"
  - "Scoped world-hub read model"
  - "Truthful scoped realm map overlays"
requirements-completed: [WORLD-01, WORLD-02, WORLD-03]
completed: 2026-07-10
---

# Phase 2 Plan 01 Summary

- Added `Clock.world_time/2`, a deterministic server-time projection for the GDD's 13×28 calendar and seasons.
- Added a stationary-nearby-character Accounts query and `Play.world_hub_state/1`, composing own realm, map state, supplies, notifications, nearby players, and open encounters.
- Replaced MapLive's default-realm and fixture overlays with the current scope's world state; map now has real clock, location, activity, nearby, notification, and travel IDs.
- Added tests proving a non-default scoped realm does not leak another realm's actors.

## Verification

- `mix test test/mmgo/travel/clock_test.exs test/mmgo/play_test.exs test/mmgo_web/live/map_live_test.exs test/mmgo_web/play_demo_loop_test.exs` — 24 passed.
- `mix format` for changed files — passed.

## Task Commits

No task commit was created because git-index escalation remains unavailable; the work is intentionally left in the shared working tree.
