---
phase: 01-telegram-access-and-player-shell
plan: "01"
subsystem: ui
tags: [phoenix, liveview, telegram, routing, session]
requires: []
provides:
  - LiveView Telegram Mini App entry gate at `/`
  - Server-owned Telegram restore/bootstrap classification in `MMGO.Accounts`
  - Routed resume, deep-link, and recovery coverage for the entry flow
affects: [01-02, player-shell, telegram]
tech-stack:
  added: []
  patterns: [server-owned entry restore classification, routed LiveView entry gate, adjacent HEEx LiveView template]
key-files:
  created:
    - lib/mmgo_web/live/telegram_entry_live.ex
    - lib/mmgo_web/live/telegram_entry_live.html.heex
    - test/mmgo_web/live/telegram_entry_live_test.exs
  modified:
    - lib/mmgo/accounts.ex
    - lib/mmgo_web/router.ex
    - lib/mmgo_web/controllers/page_controller.ex
    - test/mmgo/accounts_test.exs
    - test/mmgo_web/controllers/page_controller_test.exs
key-decisions:
  - "Centralized entry classification in `MMGO.Accounts.restore_telegram_entry/2` so the browser never becomes the source of truth for account or character state."
  - "Reserved `/` for the Mini App LiveView gate and moved the old bootstrap controller page to `/bootstrap`."
  - "Treated bare `telegram_user_id` route params as restore hints and only used full Telegram user payloads for provisioning or identity refresh."
patterns-established:
  - "Use `MMGO.Accounts.restore_telegram_entry/2` as the single restore/bootstrap API for entry-facing LiveViews."
  - "Keep player-facing entry UI in an adjacent HEEx template while mount logic stays in the LiveView module."
requirements-completed: [ACCESS-01, ACCESS-02, ACCESS-03]
duration: 21 min
completed: 2026-04-03
---

# Phase 01 Plan 01: Telegram Identity, Linking, and Deep-Link Routing Summary

**LiveView Telegram entry gate with server-owned account restore, quick resume, deep-link classification, and recovery rendering at `/`**

## Performance

- **Duration:** 21 min
- **Started:** 2026-04-03T16:31:38Z
- **Completed:** 2026-04-03T16:52:26Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- Added `MMGO.Accounts.restore_telegram_entry/2` to classify `:first_open`, `:resume`, `:deep_link`, and `:recovery` from Telegram entry hints while restoring authoritative account and character state.
- Added `MMGOWeb.TelegramEntryLive` plus `telegram_entry_live.html.heex` for the first-open, resume, deep-link, and recovery entry surfaces.
- Routed `/` to the new LiveView gate and moved the old bootstrap controller page to `/bootstrap`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Mini App bootstrap and restore helpers for entry gating**
   - `ded13cb` (test)
   - `b5865a9` (feat)
   - `feee8e4` (fix)
2. **Task 2: Route the browser entry into the LiveView gate and preserve refresh/deep-link restore**
   - `a3df256` (test)
   - `563582b` (feat)
   - `60804e2` (refactor)

**Plan metadata:** pending

_Note: TDD tasks used separate red/green commits._

## Files Created/Modified
- `lib/mmgo/accounts.ex` - Restore/bootstrap classification for Telegram entry params and session hints.
- `lib/mmgo_web/router.ex` - Root LiveView route and `/bootstrap` controller route.
- `lib/mmgo_web/controllers/page_controller.ex` - Bootstrap page title moved to the non-player path.
- `lib/mmgo_web/live/telegram_entry_live.ex` - Entry gate mount logic and state helpers.
- `lib/mmgo_web/live/telegram_entry_live.html.heex` - First-open, resume, deep-link, and recovery entry UI.
- `test/mmgo/accounts_test.exs` - Restore-oriented account coverage for first-open and repaired resume behavior.
- `test/mmgo_web/live/telegram_entry_live_test.exs` - Isolated and routed entry LiveView coverage.
- `test/mmgo_web/controllers/page_controller_test.exs` - Bootstrap smoke test moved to `/bootstrap`.

## Decisions Made
- Used Telegram identity hints only to select or provision the player; account and character context is always reloaded from the database before rendering.
- Kept deep-link validation in the restore result so the LiveView only renders state and notices instead of duplicating target resolution logic.
- Preserved the old static bootstrap page as a secondary route for operators and development context instead of deleting it outright.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved first-open state across the LiveView disconnected and connected mounts**
- **Found during:** Task 1 (Add Mini App bootstrap and restore helpers for entry gating)
- **Issue:** The static mount provisioned the account, and the connected mount immediately reclassified the same visit as `:resume`.
- **Fix:** Classified fresh first-open visits from the newly created account and character timestamps instead of relying only on a pre-provision identity check.
- **Files modified:** `lib/mmgo/accounts.ex`
- **Verification:** `mix test test/mmgo/accounts_test.exs test/mmgo_web/live/telegram_entry_live_test.exs`
- **Committed in:** `feee8e4`

**2. [Rule 1 - Bug] Treated bare `telegram_user_id` route params as restore-only hints**
- **Found during:** Task 2 (Route the browser entry into the LiveView gate and preserve refresh/deep-link restore)
- **Issue:** Routed resume requests with only `telegram_user_id` were being treated like a fresh Telegram payload, which risked unnecessary identity refresh with partial data.
- **Fix:** Changed bootstrap normalization so only params with actual Telegram profile fields take the provisioning path; bare IDs now use the restore path.
- **Files modified:** `lib/mmgo/accounts.ex`
- **Verification:** `mix test test/mmgo_web/live/telegram_entry_live_test.exs` and `mix precommit`
- **Committed in:** `563582b`

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both fixes were correctness issues discovered during TDD. No scope creep.

## Issues Encountered
- Mix test runs needed escalation because Mix.PubSub could not open its local socket inside the default sandbox.
- Parallel git activity briefly left transient `.git/index.lock` contention; retrying after the lock cleared was sufficient.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `/` now resolves to a tested Telegram entry gate with first-open, resume, deep-link, and recovery UI states.
- `01-02` can focus on wiring `Enter World` and `Resume Journey` into the actual player shell rather than re-solving entry routing.

## Self-Check: PASSED
- FOUND: `.planning/phases/01-telegram-access-and-player-shell/01-01-SUMMARY.md`
- FOUND: `ded13cb`
- FOUND: `b5865a9`
- FOUND: `feee8e4`
- FOUND: `a3df256`
- FOUND: `563582b`
- FOUND: `60804e2`

---
*Phase: 01-telegram-access-and-player-shell*
*Completed: 2026-04-03*
