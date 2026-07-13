---
phase: 02-living-world-activities-and-survival
plan: "04"
subsystem: survival
tags: [survival, travel, scavenging, inventory, liveview]
provides:
  - "Durable metadata-backed starvation state"
  - "Underfed journey delay and non-lethal health-drain consequences"
  - "Scoped scavenging UI with durable attempt/result state"
requirements-completed: [SURV-02, SURV-03]
requirements-advanced: [SURV-01]
completed: 2026-07-10
---

# Phase 2 Plan 04 Summary

- Replaced the old underfed-departure rejection with a transactional available-food allocation. An underfed journey now records its shortage, adds the first-day movement delay, and persists day-two-plus non-lethal health drain exactly once at arrival.
- Added `MMGO.Survival.State`, a typed state serialized in the existing durable character metadata field. This avoided manually fabricating the required migration while the project generator remained unavailable under the sandbox lock restriction.
- Food grants restore recoverable starvation state atomically with the inventory grant. Realm food-per-day and carry-capacity rules now shape the actual survival plan.
- Added scoped scavenging cache/attempt/result state through `Play` and `/event`; completion shows durable loot/XP information after the worker resolves it.
- Added truthful food, starvation, overload, grimoire-weight, and flee-availability state to the activity, travel, and inventory surfaces.

## Verification

- `mix test test/mmgo/survival_test.exs test/mmgo/travel_test.exs test/mmgo/travel_survival_test.exs test/mmgo/scavenging_test.exs test/mmgo_web/live/action_hub_live_test.exs test/mmgo_web/live/travel_live_test.exs test/mmgo_web/live/inventory_live_test.exs` — passed.
- Phase 2 focused suite — 61 passed.

## Task Commits

No task commit was created because git-index escalation remains unavailable; the work is intentionally left in the shared working tree.
