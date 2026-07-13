# Phase 2: Living World, Activities, and Survival — Research

## Summary

MMGO already has durable domain support for travel, resource caches, scavenging jobs, XP, notifications, text events, overworld encounters, and carrying calculations. The primary gap is a server-owned browser read model and a handful of missing invariants: a canonical calendar, world/survival state visibility, PvP ruleset enforcement, and persistent starvation consequences. Phase 2 should extend the existing `MMGO.Play` facade rather than rebuild those contexts.

## Existing reusable behavior

- `MMGO.Travel.Clock` maps one real day to 364 game days; it needs a calendar projection but not a new time engine.
- `MMGO.Travel.start_journey/3` locks the character and route, snapshots load, schedules worker completion, and currently consumes all required food immediately.
- `MMGO.Survival` already computes carried weight, active-grimoire weight, capacity, overload delay, food units, and transactional food consumption.
- `MMGO.Scavenging` locks cache/character state, reserves resources, persists timer attempts, schedules a worker, grants loot/XP, and queues notifications.
- `MMGO.Events` persists location text events and trusted action keys for city, Tower, base, and wilderness locations.
- `MMGO.Overworld` persists encounter/response choices and escalates unsafe attacks to a combat instance, but no browser surface invokes it and it does not yet read the realm PvP rule.
- `MMGO.Notifications` can list a character's real delivery history; map fixture notifications should be replaced by this read.

## Required additions

1. Extend `Travel.Clock` with a deterministic `world_time/1` projection: 13 months × 28 days, 4 seasons, stable epoch/year, and testable fixed `now`.
2. Add `Play.world_hub_state/1`, `activity_hub_state/1`, and scoped command wrappers for event resolution, scavenging, and overworld encounters. These wrappers own all identity/location/event lookup checks.
3. Add a small typed `Survival.State` schema + migration to persist hunger days, movement penalty, health penalty, and recovery timestamp. Keep values conservative and visible, and expose one reusable function that Phase 7 can call for expedition food consumption.
4. Change journey allocation to use the realm's `travel_food_units_per_day`; reserve available food, allow a computed shortage, and persist the plan/consequences in the journey. Completion applies the survival state once/idempotently.
5. Use existing realm rules for `carry_capacity_scale_bps` and `overworld_pvp_enabled`; these are currently validated but not applied.

## Browser approach

- `MapLive` uses the scoped character's realm, a world-hub state refresh, and actual map-state payload (`others` included) rather than a default realm and fixture overlays.
- `ActionHubLive` is a real form/action surface with stable IDs. It never permits browser-controlled location or actor selection; cache, event, target, and encounter IDs are validated in `MMGO.Play`.
- `TravelLive` and `InventoryLive` display the new survival/mobility summary rather than redesigning their established truthful read models.
- Use existing `LocationGate` and routes for physically legal actions; do not make later-phase pages appear implemented just because an activity link can reach their location.

## Tests

- Unit: world calendar boundaries, realm ruleset food/capacity modifiers, starvation/recovery transitions, and idempotent journey completion.
- Context: scoped event/cached-resource/nearby/encounter wrappers reject foreign IDs, wrong location, safe-zone attack, and disabled realm PvP.
- LiveView: map shows a scoped realm/clock/profile/activity link; hub starts a real scavenging attempt and records an event option; nearby actors/encounters render only for a matching location; travel/inventory show real survival state.
- Full phase gate: focused Phase 2 suite then `mix precommit`.

## Risks

- Do not mutate player survival state in a read-only LiveView mount. Apply/clear state only via explicit journey, scavenging reward, or shared survival command paths.
- Existing event creation needs one-active-event correctness under concurrent hub mounts. Add an index/lock or a transaction-backed lookup before exposing it broadly.
- Keep food shortages deterministic at journey start; avoid recursive time/food calculations.
- Do not turn in-app event choices into controller-side free-form routes; trusted `action_key` maps to a fixed server table.
