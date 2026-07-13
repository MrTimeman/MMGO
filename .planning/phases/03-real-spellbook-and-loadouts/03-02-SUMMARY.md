---
phase: 03-real-spellbook-and-loadouts
plan: "02"
subsystem: grimoires
tags: [grimoires, loadouts, locking, transactions]
provides:
  - "Locked explicit inscription"
  - "Owner-wide serialized loadout activation"
  - "Write-once and capacity-safe grimoire lifecycle"
requirements-completed: [MAGIC-02]
completed: 2026-07-10
---

# Phase 3 Plan 02 Summary

- Wrapped inscription in a transaction that locks the selected grimoire and reloads its entries before enforcing ownership, draft status, capacity, and duplicate rules.
- Activation now locks all grimoires owned by the caster before sealing a prior active loadout and activating the selected book.
- The browser-facing flow now relies on explicit spell selection rather than silently taking the first available library entry.

## Verification

- `mix test test/mmgo/grimoires_test.exs` — 5 passed.
- Coverage includes foreign ownership, duplicate/full/sealed rejection, and exactly-one-active replacement.

