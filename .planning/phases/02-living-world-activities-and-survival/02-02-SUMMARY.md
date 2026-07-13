---
phase: 02-living-world-activities-and-survival
plan: "02"
subsystem: world-events
tags: [events, current-scope, liveview, authorization]
provides:
  - "Scoped durable arrival-event facade"
  - "Trusted server-owned event action routing"
  - "Russian current-location activity hub"
requirements-completed: [WORLD-04]
completed: 2026-07-10
---

# Phase 2 Plan 02 Summary

- Made `Events.current_event/1` serialize per-character event creation and resolve a stale active arrival event before a new location event is created.
- Added `Play.activity_hub_state/1` and `Play.resolve_activity_option/3`, which prove event ownership, active status, realm, and current location before resolving an option.
- Replaced the static `/event` location selector with the scoped event instance, actual current location, canonical date, persisted options, and trusted navigation/availability responses.
- Added explicit city, base, Tower, wilderness, and dungeon-entrance event templates; the hub never takes a route or actor from browser input.
- Added focused facade and LiveView tests for current event rendering, foreign-event rejection, real route navigation, and transit redirection.

## Verification

- `mix test test/mmgo/events_test.exs test/mmgo/play_test.exs test/mmgo_web/live/action_hub_live_test.exs test/mmgo_web/live/map_live_test.exs` — passed.
- `mix format` for changed files — passed.

## Task Commits

No task commit was created because git-index escalation remains unavailable; the work is intentionally left in the shared working tree.
