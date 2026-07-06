# First Playable Demo Loop

Purpose: remove ambiguity before heavy implementation. The primary playable surface is LiveView. JSON endpoints stay secondary for hooks, browser clients, and test probes.

## Route Audit

- `/`
  - Status: marketing/bootstrap page only.
  - Ready for loop: no.
  - Role: entry point should link to `/demo/start` once the loop is implemented.

- `/demo/start`
  - Status: creates or reuses demo player and bot accounts/characters, funds both economy accounts, stores `demo_character_id` and `demo_opponent_id` in session, redirects to `/spellbook`.
  - Ready for loop: partial.
  - Missing: place both characters at the starter location and grant starter travel food.

- `/map`
  - Status: LiveView map shell with JS hook and seeded locations/routes pushed to the browser.
  - Ready for loop: partial.
  - Missing: load session character, show actual current location, show reachable routes from that location, start journeys through `Travel.start_journey/2`, and show active journey state.

- `/spellbook`
  - Status: LiveView loads demo character, lists spells, and compiles via `Spells.Compiler.compile_and_store/2`.
  - Ready for loop: mostly.
  - Missing: wrap root content with `Layouts.app`, add stable element IDs/tests, and ensure the default compile payload is valid from the hook.

- `/pvp`
  - Status: LiveView loads demo character and bot, challenges bot through `PVP.challenge_duel/3`, and can accept/reject/cancel.
  - Ready for loop: partial.
  - Missing: demo characters must share a current location before duel acceptance can work. Bot challenge is enough for first loop if "challenge bot" means creating a pending challenge; accepting/settling can come next.

- `/api/play/state`
  - Status: returns demo character identity only.
  - Ready for loop: partial.
  - Missing: include current location, reachable routes, active journey, known spells, and open duel summary if hooks need JSON.

- `/api/play/journeys`
  - Status: stub returning `%{ok: true}`.
  - Ready for loop: no.
  - Missing: accept destination or route id, resolve from current location, call `Travel.start_journey/2`, and return journey or validation errors.

## Backend Context Readiness

- Accounts: ready for demo identity and character loading. Demo setup currently creates accounts/characters directly; acceptable for internal demo, but should set character status/location explicitly.
- Worlds: ready. Seed data has default canonical realm, `capital-city`, and reachable routes.
- Travel: ready. `Travel.start_journey/2` and active journey queries exist. Requires character `current_location_id` and enough food inventory.
- Spells: ready for first compile. `Spells.Compiler.compile_and_store/2` is wired through AI provider and persists spells.
- PVP: ready for challenge creation and duel lifecycle. Acceptance requires both characters in the same location and enough funds.
- Economy: ready. Demo setup already creates/funds character accounts; PVP escrow and transfers are implemented.
- Inventory: ready. Food templates and grants exist; demo setup needs a deterministic starter ration grant.

## Exact First Playable Loop

1. Start demo
   - `/demo/start` creates/reuses player and bot.
   - Both characters are active, in `capital-city`, funded, and supplied with travel rations.
   - Redirect to the primary first surface: `/map`.

2. Load character
   - LiveViews load `demo_character_id` from session.
   - Missing session redirects to `/demo/start`.

3. Show current location
   - `/map` displays the character's actual `current_location`.
   - No placeholder player state.

4. Show reachable routes
   - `/map` lists `Worlds.list_routes_for_location/1` for the current location.
   - Each route shows destination, travel days, risk, and required food.

5. Start journey
   - Route click or route action calls the LiveView event first.
   - LiveView resolves route by destination slug or route id and calls `Travel.start_journey/2`.

6. Show active journey
   - `/map` shows `Travel.active_journey/1` with origin, destination, arrival time, food consumed, and status.
   - While active, route start actions are disabled or show the existing journey error.

7. Compile spell
   - `/spellbook` remains a LiveView surface.
   - Successful compile persists the spell and updates the known spell list.

8. Challenge bot
   - `/pvp` creates a pending bot duel through `PVP.challenge_duel/3`.
   - For this first loop, "challenge bot" is complete when the pending duel is visible. Acceptance/settlement is follow-up unless needed for demo credibility.

## Implementation Checklist

- Update demo setup to place player and bot in the realm entry location or `capital-city`.
- Update demo setup to grant/replenish starter food using an idempotent ration template.
- Make `/demo/start` redirect to `/map` so travel is the first interaction.
- Replace `/map` placeholder player with the session character.
- Add map assigns for current location, reachable routes, active journey, food, and form/action state.
- Implement LiveView journey start event using `Worlds.route_from_location_to_slug/2` or route id plus `Travel.start_journey/2`.
- Refresh map state after journey start and push updated hook data.
- Add `/api/play/state` parity only for hook/client needs.
- Implement `/api/play/journeys` only if the map hook cannot use LiveView events directly.
- Wrap new/updated LiveView templates in `<Layouts.app flash={@flash}>`.
- Add focused LiveView/controller tests using stable DOM IDs for demo start, map route visibility, journey start, spell compile presence, and bot challenge.

## Decision

LiveView is the primary frontend surface for the first playable loop. The JSON API remains secondary and should not drive the main UI unless a JS hook needs a compact state/action endpoint.
