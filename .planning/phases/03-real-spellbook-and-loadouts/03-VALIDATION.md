---
phase: 3
slug: real-spellbook-and-loadouts
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-10
---

# Phase 3 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit + Phoenix.LiveViewTest |
| Config | `mix.exs` |
| Quick run | `mix test test/mmgo/spells/compiler_test.exs test/mmgo/grimoires_test.exs test/mmgo/play_test.exs test/mmgo_web/live/spellbook_live_test.exs` |
| Full suite | `mix precommit` |
| Estimated runtime | ~30 seconds |

## Sampling Rate

- After Plan 03-01: compiler tests.
- After Plan 03-02: grimoire tests.
- After Plan 03-03: Play + LiveView tests.
- Before phase verification: focused suite, `mix precommit`, and `git diff --check`.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | MAGIC-01 | unit | `mix test test/mmgo/spells/compiler_test.exs` | yes | passed |
| 03-02-01 | 02 | 1 | MAGIC-02 | unit | `mix test test/mmgo/grimoires_test.exs` | yes | passed |
| 03-03-01 | 03 | 2 | MAGIC-01, MAGIC-02 | integration | `mix test test/mmgo/play_test.exs test/mmgo_web/live/spellbook_live_test.exs` | yes | passed |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

## Manual-Only Verifications

All core behavior is covered with domain and scoped LiveView tests. Decorative spell-circle hooks are explicitly non-authoritative and do not require manual validation for this phase.

## Validation Sign-Off

- [x] All tasks have automated verification.
- [x] Sampling continuity has no three-task gap.
- [x] No watch-mode flags are used.
- [x] `nyquist_compliant: true` is set.

**Approval:** ready 2026-07-10
