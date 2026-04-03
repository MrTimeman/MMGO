---
phase: 1
slug: telegram-access-and-player-shell
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-03
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit + Phoenix.LiveViewTest |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/mmgo/accounts_test.exs test/mmgo_web/live/telegram_entry_live_test.exs test/mmgo_web/live/player_shell_live_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~25 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/mmgo/accounts_test.exs test/mmgo_web/live/telegram_entry_live_test.exs test/mmgo_web/live/player_shell_live_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | ACCESS-01, ACCESS-02 | unit + integration | `mix test test/mmgo/accounts_test.exs test/mmgo_web/live/telegram_entry_live_test.exs` | ✅ | ⬜ pending |
| 01-01-02 | 01 | 1 | ACCESS-01, ACCESS-03 | integration | `mix test test/mmgo_web/live/telegram_entry_live_test.exs` | ✅ | ⬜ pending |
| 01-02-01 | 02 | 2 | ACCESS-03 | liveview | `mix test test/mmgo_web/live/player_shell_live_test.exs` | ✅ | ⬜ pending |
| 01-02-02 | 02 | 2 | ACCESS-04 | liveview | `mix test test/mmgo_web/live/telegram_entry_live_test.exs test/mmgo_web/live/player_shell_live_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| MMO-login atmosphere, HUD polish, and bottom-nav feel inside Telegram viewport | ACCESS-01, ACCESS-03, ACCESS-04 | Visual tone and mobile feel are better judged by a human after automated correctness passes | Launch the Mini App surface in a mobile-sized browser and verify first-open entry, quick resume, recovery card, and shell HUD align with `01-UI-SPEC.md`. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-03
