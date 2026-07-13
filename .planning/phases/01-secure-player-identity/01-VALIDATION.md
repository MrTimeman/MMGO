---
phase: 1
slug: secure-player-identity
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-09
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for secure player identity work.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit + Ecto SQL Sandbox + Phoenix LiveViewTest |
| **Config file** | `config/test.exs` |
| **Quick run command** | `mix test test/mmgo/telegram/web_app_auth_test.exs test/mmgo_web/controllers/telegram_auth_controller_test.exs test/mmgo_web/live/game_auth_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~30 seconds for focused tests; longer for full suite |

---

## Sampling Rate

- **After every task commit:** Run the focused auth suite.
- **After every plan wave:** Run the focused auth suite plus affected existing browser tests.
- **Before `$gsd-verify-work`:** `mix precommit` must be green.
- **Max feedback latency:** 60 seconds for focused test feedback.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | AUTH-01 | unit | `mix test test/mmgo/telegram/web_app_auth_test.exs` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 2 | AUTH-02 | controller/live | `mix test test/mmgo_web/controllers/telegram_auth_controller_test.exs test/mmgo_web/live/game_auth_test.exs` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 2 | AUTH-03 | controller/live | `mix test test/mmgo_web/controllers/telegram_auth_controller_test.exs test/mmgo_web/play_demo_loop_test.exs` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 3 | AUTH-04 | unit/controller | `mix test test/mmgo/telegram_test.exs test/mmgo_web/controllers/telegram_webhook_controller_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/mmgo/telegram/web_app_auth_test.exs` — signature, expiry, malformed-data fixtures for AUTH-01.
- [ ] `test/mmgo_web/controllers/telegram_auth_controller_test.exs` — endpoint/session outcomes for AUTH-01 through AUTH-03.
- [ ] `test/mmgo_web/live/game_auth_test.exs` — scoped session and protected-route behavior for AUTH-02.
- [ ] Existing infrastructure covers SQL sandbox, Phoenix connection, and LiveView mounting; no new framework installation is needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Telegram client sends `initData` through the actual Mini App webview | AUTH-01 | Requires an operator-configured bot and a Telegram client | Configure a test bot, open `/play` as its Mini App, confirm the authorization handoff reaches `/map`, and verify normal browser shows safe fallback. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-07-09
