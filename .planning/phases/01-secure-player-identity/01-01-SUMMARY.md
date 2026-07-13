---
phase: 01-secure-player-identity
plan: "01"
subsystem: auth
tags: [telegram-mini-app, hmac, otp-crypto, webhook, security, exunit]
requires: []
provides:
  - "Server-side Telegram Mini App initData validation with HMAC, freshness, and JSON-user checks"
  - "Explicit webhook insecure-mode policy that fails closed by default"
  - "Deterministic auth and webhook regression tests"
affects: [game-entry, current-scope, router-auth, production-configuration]
tech-stack:
  added: []
  patterns:
    - "Use OTP :crypto plus Plug.Crypto.secure_compare for Telegram verification"
    - "Return tagged auth failures without logging raw init data"
key-files:
  created:
    - lib/mmgo/telegram/web_app_auth.ex
    - test/mmgo/telegram/web_app_auth_test.exs
    - test/mmgo/telegram_test.exs
  modified:
    - lib/mmgo/telegram.ex
    - config/config.exs
    - config/runtime.exs
    - config/test.exs
    - test/mmgo_web/controllers/telegram_webhook_controller_test.exs
key-decisions:
  - "Telegram initData uses the official two-stage WebAppData HMAC construction and a 300-second max age."
  - "Missing webhook secrets are rejected unless an explicit insecure local/test allowance is configured."
patterns-established:
  - "Pass fixed `now` and token options to crypto tests instead of sleeping or relying on external services."
requirements-completed: [AUTH-01, AUTH-04]
duration: 25min
completed: 2026-07-10
---

# Phase 1: Secure Player Identity Summary

**Telegram Mini App HMAC verification with freshness checks and a default fail-closed webhook policy**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-10T00:00:00+03:00
- **Completed:** 2026-07-10T00:25:00+03:00
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Added `MMGO.Telegram.WebAppAuth`, which validates Telegram’s signed raw init-data query using OTP crypto, constant-time comparison, auth-date bounds, and JSON user parsing.
- Added deterministic unit coverage for valid, tampered, expired/future, missing-hash/date/token, and malformed-user cases.
- Made webhook secret acceptance fail closed unless `allow_insecure_webhook?` is explicitly enabled, with production-style controller coverage.

## Task Commits

No task commits were created: the workspace’s git index writes were denied by the environment’s usage-limit escalation. The implementation and planning artifacts remain uncommitted in the working tree; no workaround was attempted.

## Files Created/Modified

- `lib/mmgo/telegram/web_app_auth.ex` — server-side Mini App auth verifier.
- `lib/mmgo/telegram.ex` — explicit insecure-webhook policy check.
- `config/config.exs`, `config/runtime.exs`, `config/test.exs` — auth age and webhook mode configuration.
- `test/mmgo/telegram/web_app_auth_test.exs` — deterministic HMAC/freshness coverage.
- `test/mmgo/telegram_test.exs` — webhook secret policy coverage.
- `test/mmgo_web/controllers/telegram_webhook_controller_test.exs` — production-style missing-secret rejection coverage.

## Decisions Made

- Used the existing OTP/Plug stack rather than adding an authentication dependency.
- Reject future as well as expired `auth_date` values; this prevents replay/clock ambiguity from granting access.

## Deviations from Plan

### Auto-fixed Issues

**1. Test fixture needed explicit nil removal and token override**
- **Found during:** Task 1
- **Issue:** A merge retained the default auth date when testing missing data, and test config supplied a token unless the option explicitly overrode it.
- **Fix:** Applied nil removal after merging fixture overrides and passed `bot_token: nil` in the missing-token case.
- **Files modified:** `test/mmgo/telegram/web_app_auth_test.exs`
- **Verification:** Focused test suite passes.

---

**Total deviations:** 1 auto-fixed correctness issue.
**Impact on plan:** No scope expansion; it made the intended negative cases real.

## Issues Encountered

- Global `mix format --check-formatted` reports a pre-existing formatting discrepancy in committed `lib/mmgo_web/live/duel_live.ex`; only Phase 1 files were formatted to avoid changing unrelated work.

## User Setup Required

None for local implementation. An operator later needs a bot token, registered Mini App URL, and production webhook secret to exercise the live integration.

## Next Phase Readiness

- The auth primitive is ready for the scoped session and controller/entry flow.
- Keep raw init data and credentials out of logs/flash messages.
- Commit planning/code work when git index writes become available; do not rewrite existing committed gameplay work.

---
*Phase: 01-secure-player-identity*
*Completed: 2026-07-10*
