---
phase: 2
slug: living-world-activities-and-survival
status: approved
preset: MMGO map-first world shell
created: 2026-07-10
---

# Phase 2 — UI Design Contract

## Intent

The map is a truthful field journal, not a dashboard. It shows the player's actual realm, clock, location, supplies, and immediate choices. The activity hub is a short text-adventure page reached from the map; it shows only actions allowed at the current location.

## Map contract

- `#map-world-clock`: canonical 13-month date, season, and year from server time.
- `#map-current-location`: scoped character location, food runway, and overload/starvation state.
- `#map-activity-link`: one clear `Осмотреться` entry to the current real location hub.
- `#map-nearby-actors`: empty state or real nearby active players; no fabricated portraits/names.
- `#map-notifications`: persisted notification history/status; no fake accept/decline controls.
- `#map-travel-state`: active journey destination/progress/arrival when applicable.

## Activity hub contract

- `#activity-hub` is full-height, dark, and uses the actual location/event title/body.
- Trusted event options render as `#activity-option-<code>` and resolve through a real server action before navigation.
- Resource caches render as `#activity-scavenge-cache-<id>` with real remaining quantity, duration, weight consequence, and action state.
- An active attempt renders as `#activity-attempt-<id>` with time/status instead of a second start button.
- Nearby/pending encounters render as `#activity-nearby-<character-id>` and `#activity-encounter-<id>`. Buttons are present only for legal choices.
- Error and empty states are Russian, specific, and never reveal an untrusted ID or internal stack trace.

## Survival contract

- `#travel-survival-state` and `#inventory-overload-state` show food, shortage days, movement penalty, health penalty, carry/capacity, and recovery state.
- Hunger and overload use clear amber/red status labels; normal state stays quiet.
- No UI presents socket-local item tags as durable market state.

## Layout and accessibility

- Revised LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- Touch actions are at least 44px, forms use the shared `<.form>` and `<.input>` components, and all action buttons have unique IDs.
- The hub has no fake location selector or demo compass. Navigation always returns to `/map`.
