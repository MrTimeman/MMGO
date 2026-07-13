---
phase: 01-secure-player-identity
plan: "04"
subsystem: auth
tags: [phoenix-liveview, current-scope, session-security, local-demo, play-api]
requires:
  - "Verified Mini App entry and GameAuth from 01-03"
provides:
  - "Scope-owned map, travel, inventory, duel, spellbook, academy, and organisation routes"
  - "Scope-owned browser Play API"
  - "Explicit local-demo configuration boundary"
affects: [map, travel, inventory, pvp, spellbook, academy, organisations, play-api]
tech-stack:
  added: []
  patterns:
    - "Read gameplay actors from current_scope rather than a demo session identifier"
    - "Derive API actor authority from matching signed account and character session values"
    - "Gate local demo creation/reset behind one runtime configuration flag"
key-files:
  created: []
  modified:
    - lib/mmgo_web/live/map_live.ex
    - lib/mmgo_web/live/travel_live.ex
    - lib/mmgo_web/live/inventory_live.ex
    - lib/mmgo_web/live/duel_live.ex
    - lib/mmgo_web/live/spellbook_live.ex
    - lib/mmgo_web/live/bulletin_board_live.ex
    - lib/mmgo_web/live/study_desk_live.ex
    - lib/mmgo_web/live/exam_live.ex
    - lib/mmgo_web/live/club_event_live.ex
    - lib/mmgo_web/live/organizations_live.ex
    - lib/mmgo_web/controllers/play_api_controller.ex
    - lib/mmgo_web/controllers/play_demo_controller.ex
key-decisions:
  - "Only local-play characters may use the local demo opponent marker, and only when local demos are enabled."
  - "The local demo sets a real scoped session so protected screens exercise the same ownership boundary as Telegram players."
  - "API requests verify matching account and character ownership before loading or mutating state."
patterns-established:
  - "Protected LiveViews use socket.assigns.current_scope.character and pass current_scope to Layouts.app."
requirements-completed: [AUTH-02, AUTH-03, AUTH-04]
completed: 2026-07-10
---

# Phase 1: Secure Player Identity Summary

**The existing browser loop now belongs to a verified player scope, with local demos isolated from production identity**

## Accomplishments

- Replaced legacy `demo_character_id` reads in map, travel, inventory, duel, spellbook, Academy, club, and organisation screens with the GameAuth current scope.
- Updated all affected `Layouts.app` calls to receive `current_scope`; unauthenticated visitors now flow through the Telegram entry route rather than the former demo continuation path.
- Scoped exam terms to the player’s active enrollment and club events to the player’s realm before rendering them.
- Moved the browser Play API to signed, ownership-verified `current_account_id` and `current_character_id` values, ignoring demo-only and client-supplied character IDs.
- Made local demo endpoints/reset explicitly configurable: enabled for dev/test, disabled by default and in production, returning 404 without creating demo records when disabled.
- Preserved the local smoke loop by giving it the same current-scope session contract as a real player, while preventing real scoped players from inheriting the local bot opponent.

## Verification

- `mix test test/mmgo_web/play_demo_loop_test.exs test/mmgo_web/live/game_auth_test.exs test/mmgo_web/live/spellbook_live_test.exs test/mmgo_web/live/travel_live_test.exs test/mmgo_web/live/inventory_live_test.exs test/mmgo_web/live/duel_live_test.exs test/mmgo_web/live/organizations_live_test.exs test/mmgo_web/controllers/telegram_auth_controller_test.exs test/mmgo_web/controllers/telegram_webhook_controller_test.exs` — 36 passed.
- `mix format --check-formatted` — passed.
- `git diff --check` — passed.
- `mix precommit` — 319 passed (318 tests and 1 property).

## Task Commits

No task commit was created: the environment previously denied git index writes due to an escalation usage limit. The work remains uncommitted in the shared working tree; no workaround was attempted.

## Deviations from Plan

### Auto-fixed issues

**1. Duel identity markup was not formatter-idempotent**

- **Found during:** final formatting verification.
- **Issue:** an inline Cyrillic text/interpolation span accumulated whitespace on repeated HEEx formatting passes.
- **Fix:** rendered the opponent label across separate template lines.
- **Verification:** `mix format --check-formatted` passes.

**2. Cross-realm Academy and club navigation needed explicit ownership checks**

- **Found during:** scope-migration review.
- **Fix:** Exam terms are resolved from the scoped character’s enrollment; club events must match the scoped realm.
- **Verification:** affected LiveViews compile and the focused authenticated-screen suite passes.

## Next Phase Readiness

The application has one authoritative player identity boundary. Phase 02 can now turn the map and local activities into durable player-owned world/survival loops without preserving legacy shared-demo authorization.
