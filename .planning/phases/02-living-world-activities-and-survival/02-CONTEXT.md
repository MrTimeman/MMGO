# Phase 2: Living World, Activities, and Survival - Context

**Gathered:** 2026-07-10
**Status:** Ready for planning
**Mode:** Autonomous delivery under the user's instruction to finish the GDD without per-phase approval gates.

<domain>
## Phase Boundary

Turn the authenticated map into a truthful player-owned world surface. The phase wires existing durable travel, event, scavenging, overworld, notification, and survival contexts into the browser; it adds only the missing canonical-clock and starvation persistence needed to satisfy the GDD. It does not implement the later market, base, party, dungeon, or combat screens beyond exposing legal location-gated entry points.

</domain>

<decisions>
## Implementation Decisions

### World state
- Derive every map, activity, notification, and actor query from `current_scope.character`; never use the default realm or a browser-provided actor/location ID.
- Add one canonical 13-month / 28-day world clock based on server time, with a fixed configurable epoch and deterministic test injection.
- Add a thin `MMGO.Play` read model for world-hub state rather than duplicating domain rules in `MapLive` or `ActionHubLive`.
- Replace all map fixture calendar, profile, notification, and nearby-actor assigns with persisted/current data. An empty real list is preferable to manufactured content.

### Activity hub and encounters
- Replace `/event` with a real scoped location hub. It derives the current location, persistent text event, legal event options, resource caches, active scavenging attempt, nearby actors, and open overworld encounter from server state.
- Resolve an event option only after verifying that the event belongs to the scoped character and current location; map its trusted action key to a route on the server.
- Wire existing `MMGO.Overworld` create/respond commands for greet, trade, attack, and avoid. Keep future market/combat depth out of this phase, but persist the legal action and show its true outcome/status.
- Enforce realm PvP configuration in the existing overworld context before unsafe attacks create combat.

### Survival
- Replace prepaid-all-or-nothing travel food with an auditable journey allocation that permits food shortage, applies the GDD day-one movement penalty and day-two-plus health penalty, and stores durable player survival state.
- Use a new typed survival-state persistence boundary rather than unvalidated character metadata. Food restored by a supported source clears recoverable starvation penalties deterministically.
- Preserve the existing load calculation (inventory + active grimoire); surface it in map, travel, inventory, and activity views. Overload remains legal but gives an authoritative movement penalty; the combat flee consequence is exposed as a state for Phase 4 to enforce.
- Reuse existing scavenging locks, cache depletion, timers, XP, item grants, and notification hooks. The web UI starts only owned/location-valid attempts and displays the real completion/overload consequence.

### Product scope
- All player-facing copy is Russian and uses the existing dark world presentation.
- Every revised LiveView starts with `<Layouts.app flash={@flash} current_scope={@current_scope}>` and uses stable element IDs.
- Action links may navigate to later-phase screens only when the activity is physically legal; they must not claim a mocked screen is a completed economic/social system.

</decisions>

<canonical_refs>
## Canonical References

### Product and requirements
- `docs/MMGO_GDD.md` — §§4, 5, 14 and 16 define canonical time, map-first activity, food, scavenging, and load trade-offs.
- `.planning/REQUIREMENTS.md` — WORLD-01 through WORLD-05 and SURV-01 through SURV-03.
- `.planning/ROADMAP.md` — Phase 2 goal and success criteria.

### Existing domain seams
- `lib/mmgo/travel/clock.ex`, `lib/mmgo/travel.ex`, `lib/mmgo/survival.ex` — compressed time, journey state, food, and carrying calculations.
- `lib/mmgo/scavenging.ex` — resource caches, timed attempts, XP, loot, and worker completion.
- `lib/mmgo/events.ex` — persisted location text-event templates/options.
- `lib/mmgo/overworld.ex` — persisted greet/trade/attack/avoid interactions and safe-zone checks.
- `lib/mmgo/notifications.ex` — persisted notification history/delivery state.
- `lib/mmgo/play.ex` — the web-facing orchestration boundary to extend.

### Existing web seams
- `lib/mmgo_web/live/map_live.ex` — current scoped but fixture-backed world overlay.
- `lib/mmgo_web/live/action_hub_live.ex` — design-pass location hub to replace.
- `lib/mmgo_web/live/travel_live.ex` and `inventory_live.ex` — real scoped read views to extend.
- `lib/mmgo_web/game_auth.ex` — authoritative browser actor boundary.
- `AGENTS.md` — Phoenix, LiveView, migration, form, and testing rules.

</canonical_refs>

<deferred>
## Deferred Ideas

- Actual player markets, base storage/building, crafting, alchemy, party management, and dungeon browser loops belong to Phases 5–7.
- Complete tool-user/caster combat and flee enforcement belongs to Phase 4; Phase 2 only provides accurate mobility/survival state and overworld handoff.
- In-app notification read receipts/history UI expansion belongs to Phase 9; Phase 2 displays truthful persisted notifications without fabricating read state.
- Realm-specific world-map asset distribution and federation controls remain Phase 9/11 work.

</deferred>
