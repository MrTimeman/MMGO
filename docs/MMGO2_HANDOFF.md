# MMGO-2 Frontend Handoff

Current branch: `mmgo2-main-frontend-port`

## Goal

Port `/Users/Albert/Downloads/MMGO-2.zip` into the Phoenix app, using `docs/MMGO_GDD.md` as the design authority.

## Decisions Made

- Use latest `main` backend, not the old pre-frontend commit.
- Preserve backend work and replace the frontend surface.
- `/play` should be map-first.
- Do not add global screen buttons for combat, magic, base, academy, or grimoire.
- Per GDD section 5: the map is the primary interface. To do anything, the player must physically travel there.
- Base, Academy, market, tavern, Tower library, dungeon, combat, and similar features must be accessed through location events after arriving at the relevant map location.
- Location event UI should open full-screen in the mobile shell, not as a small bottom drawer.
- Map paths/pathfinding should match the original `MMGO-2.zip` map code.
- Day/night should be wired to engine time/state, not just a local UI toggle.

## Important Local State

- Previous dirty redesign edits were stashed as `pre-mmgo2-redesign-wip`.
- Added asset: `priv/static/images/mmgo2-map.png`.
- A dev server may still be running. Check/stop with:

```sh
ps -axo pid,command | rg 'mix phx.server|beam.smp'
```

## Files Changed So Far

- `lib/mmgo_web/live/play_live.ex`
- `assets/js/hooks/map.js`
- `assets/css/app.css`
- `test/mmgo_web/live/play_live_test.exs`
- `priv/static/images/mmgo2-map.png`

## Current Implementation Status

- `PlayLive` has been reduced to a map-only shell.
- `#map-screen` mounts `phx-hook="Map"` with `phx-update="ignore"`.
- No top or bottom global screen navigation should remain.
- `MapHook` currently contains client-side MMGO-2 style locations, road paths, marker rendering, drag/zoom/recenter, night toggle, route highlight, travel animation, and location actions.
- The next step is to wire this map to the backend engine instead of static client state.

## User Requirements To Preserve

- “we don’t need those buttons to go to a screen”
- “you have to physically go to a place on the map to access its functions”
- “I can’t move, I click and I do not get departure button or anything”
- “Implement paths and path-finding from the og zip”
- “the interface of a place should open full-screen”
- “day/night switcher is nice but it should be wired into the engine”
- “Generally, wire everything to the engine according to GDD”

## Relevant GDD Notes

Read `docs/MMGO_GDD.md`, especially section 5:

- The map is the primary interface.
- Travel consumes game time and food.
- All interactions are text events at locations.
- City actions: shops, Academy, tavern, housing market.
- Base actions: store/retrieve items, craft, compose spells, rest.
- Tower actions: form/join party, enter dungeon, visit Tower library.
- Magic only works inside the Tower and dungeon.
- Overworld combat uses tools, weapons, and potions, not magic.

## Existing Backend Surface

`lib/mmgo_web/controllers/play_api_controller.ex`

- `GET /api/play/state`
- `POST /api/play/journeys` with `%{"route_id" => route_id}`
- `POST /api/play/utility-spells`
- `POST /api/play/demo/reset`

`lib/mmgo/play.ex`

- `map_state/2` returns realm, character, current location, player, supplies, active journey, available routes, map locations/routes, and client polling information.
- `start_journey/3` delegates to the travel engine.

`lib/mmgo/travel.ex`

- Creates active journeys.
- Consumes food.
- Computes arrival via compressed time.
- Completes journeys when due.

Existing old frontend reference:

- `assets/js/play-hub.js`
- It already has backend-wiring patterns and prior `ROUTE_PATHS`.

Original zip path/pathfinding reference:

- `/tmp/mmgo2-inspect/screens/Map.js`
- It defines `POIS`, `ROAD_PATHS`, `smoothPath`, `samplePath`, BFS pathfinding, and animated travel.

## Verification Passed Before Handoff

```sh
node --check assets/js/hooks/map.js
mix test test/mmgo_web/live/play_live_test.exs
mix precommit
mix assets.build
```

At that point, precommit passed with 227 tests and 1 property.

## Suggested Next Steps

1. Read current `assets/js/hooks/map.js` and `lib/mmgo_web/live/play_live.ex`.
2. Remove remaining static-only map state where appropriate.
3. Pass API endpoints into `#map-screen`:

```heex
data-state-path={~p"/api/play/state"}
data-journeys-path={~p"/api/play/journeys"}
data-demo-reset-path={~p"/api/play/demo/reset"}
```

4. In `MapHook`, fetch `/api/play/state` on mount and poll using `state.client.poll_interval_ms`.
5. Render locations/routes from backend state.
6. Preserve original zip-style pathfinding and smooth route drawing:
   - Use backend routes for route IDs and engine travel.
   - Use route metadata path points if present.
   - Fallback to MMGO-2 zip `ROAD_PATHS` keyed by slugs/names.
7. On selecting a destination:
   - If reachable via an available route, show `Отправиться →`.
   - On click, POST the route ID to `/api/play/journeys`.
   - Update UI from returned state.
8. If selected location is current location, open full-screen location event UI.
9. Location event UI should show actions based on `location.kind` and/or slug:
   - city: Academy, market, tavern, housing
   - base/farmstead: storage, craft, compose spells, rest
   - tower: party, dungeon, library
   - wilderness/road encounters: greet, trade, attack, avoid
10. Day/night should be derived from engine/game time. If missing, add a backend field in `Play.map_state/2`, for example:

```elixir
time: %{day_phase: "day" | "night", ...}
```

Use `MMGO.Travel.Clock` or a deterministic compressed-time calculation, then make the client render from that state.

