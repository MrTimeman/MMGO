---
phase: 01-secure-player-identity
plan: "03"
subsystem: auth
tags: [telegram-mini-app, phoenix-liveview, session-security, router, javascript-hooks]
requires:
  - "Verified Telegram init-data validation from 01-01"
  - "Account-owned GameAuth scope from 01-02"
provides:
  - "Verified Telegram Mini App login endpoint"
  - "Safe public Mini App entry screen and bundled bridge hook"
  - "One shared authenticated game LiveView session"
affects: [game-entry, router-auth, map, spellbook, pvp, academy, organisations]
tech-stack:
  added: []
  patterns:
    - "Submit raw Telegram WebApp init data through a CSRF-protected browser form"
    - "Write only server-derived current account and character IDs after verification"
    - "Protect game LiveViews through one GameAuth live_session"
key-files:
  created:
    - lib/mmgo_web/controllers/telegram_auth_controller.ex
    - lib/mmgo_web/live/game_entry_live.ex
    - assets/js/hooks/telegram-auth.js
    - assets/js/telegram-web-app.js
    - test/mmgo_web/controllers/telegram_auth_controller_test.exs
    - test/mmgo_web/live/game_entry_live_test.exs
  modified:
    - lib/mmgo/play.ex
    - lib/mmgo_web/router.ex
    - assets/js/hooks/index.js
key-decisions:
  - "The browser receives a generic Russian failure message; raw init data and verification causes are never exposed."
  - "The Telegram bridge is loaded by a bundled hook rather than an inline or layout script tag."
  - "New verified identities receive a one-time playable-character bootstrap before entering protected routes."
patterns-established:
  - "Public entry routes remain outside GameAuth; every game LiveView shares the :game session boundary."
requirements-completed: [AUTH-01, AUTH-02, AUTH-03]
completed: 2026-07-10
---

# Phase 1: Secure Player Identity Summary

**Verified Telegram Mini App entry backed by an account-owned game scope**

## Accomplishments

- Added the Telegram login controller: it verifies `init_data`, provisions or reuses the Telegram identity, prepares a new character exactly once, renews the browser session, and stores only `current_account_id` and `current_character_id`.
- Added `/play`, a Russian mobile-first entry state that explains normal-browser restrictions and lets a bundled hook submit Mini App init data without an automatic demo fallback.
- Routed all current gameplay LiveViews through one `GameAuth` live session while retaining the entry and local-demo routes for the next migration plan.
- Added focused controller and LiveView coverage for a verified login, idempotent re-entry, tamper rejection, and the entry-screen contract.

## Verification

- `mix test test/mmgo/telegram/web_app_auth_test.exs test/mmgo_web/controllers/telegram_auth_controller_test.exs test/mmgo_web/live/game_entry_live_test.exs test/mmgo_web/live/game_auth_test.exs` — 12 passed.
- `mix format` for the changed Plan 03 Elixir files — passed.
- `git diff --check` — passed.

## Task Commits

No task commit was created: the environment previously denied git index writes due to an escalation usage limit. The work remains uncommitted in the shared working tree; no workaround was attempted.

## Deviations from Plan

### Auto-fixed issues

**1. Controller fixture used an expired signed timestamp**

- **Found during:** focused controller test.
- **Issue:** the fixture signed `auth_date` with a fixed time while production verification correctly enforces the five-minute validity window.
- **Fix:** build the test signature with the current UTC timestamp.
- **Verification:** verified, replay-safe controller flow passes with 12 focused tests.

**2. Entry contract was missing the planned root element**

- **Found during:** acceptance-criteria review.
- **Fix:** added the stable `telegram-auth-root` wrapper and its LiveView assertion.
- **Verification:** entry-screen LiveView test passes.

## Next Phase Readiness

The production entry and router boundary are in place. Plan 04 can now replace legacy `demo_character_id` consumers with the `current_scope` character and isolate local demo endpoints behind configuration.
