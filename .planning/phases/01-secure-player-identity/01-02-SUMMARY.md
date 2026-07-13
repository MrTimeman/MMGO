---
phase: 01-secure-player-identity
plan: "02"
subsystem: auth
tags: [phoenix-liveview, current-scope, session-ownership, ecto, authorization]
requires: []
provides:
  - "Account-owned active character lookup"
  - "Reusable GameAuth current scope and LiveView on_mount guard"
  - "Cross-account and status regression coverage"
affects: [game-entry, router-auth, map, travel, inventory, duel, academy, organisations]
tech-stack:
  added: []
  patterns:
    - "Derive actor authority from matching account and character session keys"
    - "Assign one current_scope map from a shared LiveView on_mount boundary"
key-files:
  created:
    - lib/mmgo_web/game_auth.ex
    - test/mmgo_web/live/game_auth_test.exs
  modified:
    - lib/mmgo/accounts.ex
    - test/mmgo/accounts_test.exs
key-decisions:
  - "An active character lookup filters by both account and character IDs before returning any playable actor."
  - "GameAuth redirects invalid scopes to /play and never accepts a request parameter as identity."
patterns-established:
  - "Use Accounts.get_active_character_for_account/2 before assigning a game scope."
requirements-completed: [AUTH-02]
duration: 24min
completed: 2026-07-10
---

# Phase 1: Secure Player Identity Summary

**Account-owned active-character lookup and a reusable LiveView current-scope authorization guard**

## Performance

- **Duration:** 24 min
- **Started:** 2026-07-10T00:25:00+03:00
- **Completed:** 2026-07-10T00:49:00+03:00
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added a domain-level lookup that requires both account and character IDs and refuses cross-account, inactive-character, and suspended-account access.
- Added `MMGOWeb.GameAuth` with one `current_scope/1` and `on_mount(:require_character, ...)` contract for all game LiveViews.
- Added focused tests covering valid scopes, missing session state, cross-wired IDs, inactive characters, and the on-mount assignment path.

## Task Commits

No task commits were created: the environment previously denied git index writes due to an escalation usage limit. Files remain uncommitted in the shared working tree; no workaround was attempted.

## Files Created/Modified

- `lib/mmgo/accounts.ex` — account-owned active character authorization query.
- `lib/mmgo_web/game_auth.ex` — LiveView scope loading and redirect guard.
- `test/mmgo/accounts_test.exs` — ownership/status regression coverage.
- `test/mmgo_web/live/game_auth_test.exs` — current-scope/on-mount coverage.

## Decisions Made

- Scope rejects `:new` characters until the next wave supplies a real player bootstrap path; that prevents partially initialized users from issuing gameplay commands.
- Account status and character status are checked in the Accounts context rather than only in the router.

## Deviations from Plan

### Auto-fixed Issues

**1. Character-per-account-per-realm constraint changed inactive fixture shape**
- **Found during:** Task 1 test run
- **Issue:** A fixture attempted to insert active and inactive characters for the same account in one realm, violating the existing unique constraint.
- **Fix:** Used a separate inactive owner for the inactive-character case while retaining a suspended-owner case for active-character verification.
- **Files modified:** `test/mmgo/accounts_test.exs`, `test/mmgo_web/live/game_auth_test.exs`
- **Verification:** Focused Accounts/GameAuth tests pass.

**2. Minimal LiveView socket needed internal change tracking assign**
- **Found during:** Task 2 test run
- **Issue:** `Phoenix.Component.assign/3` requires `:__changed__` in a directly constructed socket.
- **Fix:** Added `%{__changed__: %{}, flash: %{}}` to the test-only socket fixture.
- **Files modified:** `test/mmgo_web/live/game_auth_test.exs`
- **Verification:** `on_mount` assignment test passes.

---

**Total deviations:** 2 auto-fixed test-correctness issues.
**Impact on plan:** No scope expansion; both fixes model existing constraints/framework behavior accurately.

## Issues Encountered

None after focused test corrections.

## User Setup Required

None.

## Next Phase Readiness

- The controller/entry flow can now provision a user, initialize their playable character, write scoped session IDs, and let GameAuth protect routes.
- The player bootstrap must activate/seed a real character before redirecting it to a protected map because new accounts currently have `:new` characters.

---
*Phase: 01-secure-player-identity*
*Completed: 2026-07-10*
