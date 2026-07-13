---
phase: 03-real-spellbook-and-loadouts
researched: 2026-07-10
---

# Phase 3 Research: Real Spellbook and Loadouts

## Existing foundation

- `MMGO.Spells`, `MMGO.Grimoires`, and their schemas already persist personal spell ownership, source lineage, grimoire entries, capacity/weight, sealing, and a single active grimoire.
- `MMGO.Spells.Compiler.compile_and_store/3` already normalizes 1–6 word incantations, persists AI request audit data, supports failed outcomes, validates generated effects, and uses the project AI provider/mocks.
- Combat already checks selected grimoire ownership and only accepts inscribed spells; `Survival` includes the active grimoire’s real weight.

## Gaps to close

1. `Play.compile_spell/2` bypasses the compiler and creates handcrafted deterministic effects. It accepts missing/foreign bases as `nil`, does not enforce word count, permitted school, location, or journey state.
2. Compiler requests have only a base ID, not the owned base spell/library context needed for true revamp/duplicate-aware behavior.
3. `Grimoires.inscribe_spell/3` checks capacity from an unlocked loaded struct. `Play.inscribe_next_spell/2` silently chooses a spell instead of accepting an explicit owned spell ID.
4. `SpellbookLive` is Tower-gated only and uses hook-delayed compilation plus hook-owned shelf actions. It lacks normal forms, stable action IDs, comprehensive errors, explicit spell selection, and base support.
5. `Academy.school_permitted?/2` is unused. New characters can have starter spells without an Academy specialization, so the compatible fallback is: specialization schools when present; otherwise schools represented by the owned library.

## Recommended implementation slices

### Plan 03-01 — compiler and authority boundary

- Add owned/same-realm base lookup in `Spells`/`Compiler`; require it before AI work.
- Normalize/lock formula + school server-side, feed a bounded owned-library/base summary into the compiler prompt, and force formula/school/source lineage from accepted input into persisted result.
- Add a `Play` composition eligibility boundary: Tower or active owned base, no active journey, permitted school as specialization-or-library fallback.
- Add compiler and Play tests proving no AI request/spell exists after invalid/foreign/wrong-place/travelling input.

### Plan 03-02 — transactional grimoire lifecycle and read model

- Lock grimoire/entries inside `Grimoires.inscribe_spell/3` before writable/capacity/duplicate checks.
- Add explicit `Play.inscribe_spell/3`; keep all foreign/non-owned IDs rejected.
- Enrich `spellbook_state/1` with composition eligibility, permitted schools, library/base choices, grimoire slots, and active loadout summary.
- Add ownership, capacity, duplicate, sealed, and active-loadout tests.

### Plan 03-03 — real LiveView player flow

- Replace hook-driven composition with normal Phoenix form/input controls and server events; visual hooks may stay decorative only.
- Render server-owned library, draft grimoire spell pickers, activation/inscription actions, stable IDs, and Russian empty/error/pending state from the UI contract.
- Test scoped Tower/base access, form submission, foreign IDs, explicit inscription, activation, and visible failure states.

## Risks and constraints

- Do not call the AI provider from inside a long database lock. Validate ownership/location first, then use the existing compiler audit path.
- The current base UI is not a composition surface; Phase 3 may only recognize an existing `Bases.active_base_at_location/2`, not invent base acquisition UI.
- `String.to_existing_atom/1` in current view helpers should not receive browser input; prefer safe map lookup for database/user-facing strings.
- Existing compiler tests must be updated with an owned base spell because the GDD requires every formula to build from the personal library.

## Validation Architecture

- Domain: `test/mmgo/spells/compiler_test.exs`, `test/mmgo/grimoires_test.exs`, `test/mmgo/play_test.exs`.
- Browser: `test/mmgo_web/live/spellbook_live_test.exs` with distinct scoped accounts, Tower/base/city/travelling fixtures, and stable selector assertions.
- Final: focused Phase 3 suite, then `mix precommit` and `git diff --check`.
