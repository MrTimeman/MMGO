# Phase 3: Real Spellbook and Loadouts - Context

**Gathered:** 2026-07-10
**Status:** Ready for planning
**Mode:** Autonomous continuation; decisions derived from the GDD, Phase 1/2 scope rules, and current code audit.

<domain>
## Phase Boundary

Turn the existing persistent spell, library, grimoire, and compiler contexts into a player-owned browser workflow. A scoped caster must see only their own library/loadouts, select an owned base spell, submit a valid 1–6 word incantation at a permitted location, receive a durable compiler result, and explicitly inscribe/activate owned grimoires.

</domain>

<decisions>
## Implementation Decisions

### Authority and eligibility
- Every spell, base spell, grimoire, inscription, and active-loadout command derives the character from `current_scope`; browser IDs are selection hints only and are looked up under that character and realm.
- Recheck allowed location and absence of an active journey in every server command, not only at LiveView mount.
- Permit composition at the Tower and at the player’s active owned base, matching GDD §5.3 and §5.4; casting remains governed by combat-zone rules.

### Composition contract
- Require a real owned base spell and normalize a Latin incantation to 1–6 words before invoking AI/compiler work.
- Route production composition through the persisted `MMGO.Spells.Compiler` path, including source lineage, owned-library duplicate context, constrained result validation, and deterministic/mock fallback.
- Invalid ownership, school, location, travel, or word-count input must create neither a spell nor an AI request.

### Loadout lifecycle
- Inscription takes an explicit owned spell ID; it never silently chooses the first uninscribed spell.
- Preserve write-once, capacity, duplicate, ownership, and one-active-grimoire rules under transactional locking.
- Grimoires are purchased physical items. This phase never creates a free grimoire; it only operates books the player already owns.
- Surface capacity, inscription entries, weight, and active state in the read model and use stable server-rendered controls rather than hook-only mutation.

### Player surface
- Retain the project’s Russian in-world presentation, but make composition, errors, empty states, and loadout actions ordinary testable LiveView events/forms with stable DOM IDs.
- Keep decorative hooks optional; no business action depends on client-generated state.

### the agent's Discretion
- Choose concise Russian copy, bounded compiler fallback behavior, and exact component layout so long as all state remains current-scope-owned and testable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Magic and location rules
- `docs/MMGO_GDD.md` — §2.2 Spell Creation, §5.3 Bases, §5.4 The Tower & Magic Zones, §7 Spell Library & Grimoires.
- `.planning/REQUIREMENTS.md` — MAGIC-01 and MAGIC-02 acceptance criteria.

### Project boundaries
- `AGENTS.md` — Phoenix/LiveView, form, test, and migration rules.
- `.planning/STATE.md` — current scope/phase decisions and environment limits.
- `.planning/phases/02-living-world-activities-and-survival/02-VERIFICATION.md` — current player-boundary and survival behavior.

</canonical_refs>

<specifics>
## Specific Ideas

No additional aesthetic direction beyond the established Russian diegetic UI and direct, account-owned actions.

</specifics>

<deferred>
## Deferred Ideas

- Full simultaneous combat AI orchestration and casting resolution belong to Phase 4.
- Base acquisition/building UI belongs to Phase 5; this phase only honours an already active owned base as a composition location.

</deferred>
