# Phase 4: Timed, Bounded Combat - Context

**Gathered:** 2026-07-10  
**Status:** Ready for planning  
**Mode:** Autonomous continuation; decisions derived from GDD §2.3 and §3, the account-owned Phase 1/2 boundary, the Phase 3 spell/loadout contract, and the current combat audit.

<domain>
## Phase Boundary

Turn the existing persisted combat engine into the real, scoped combat loop described by the GDD: a durable timed simultaneous turn, server-normalized caster and tool actions, deterministic bounded resolution, runtime AI orchestration/narration with a safe fallback, and a player/spectator LiveView for the existing duel, overworld, dungeon, and club-match contexts.

This phase connects existing combat records. It does not build party formation, dungeon navigation/extraction UI, tournament brackets, equipment acquisition, or club progression loops; later phases own those sources of combat.

</domain>

<decisions>
## Implementation Decisions

### Timed-turn authority and concurrency
- A turn is durable state, not a LiveView timer: store `opened_at`, `deadline_at`, `locked_at`, `resolution_claimed_at`, and `resolved_at` on `combat_turns`; add `:resolving` to the turn state machine.
- New turns receive `45 + 10 * max(active_participants - 2, 0)` seconds, capped at 120 seconds. This is the Phase 4 concrete interpretation of GDD §3.2's participant-scaled timer; only the persisted `deadline_at` is authoritative.
- A submitted action may be replaced only while the current turn is `:open` and before its deadline. When every ready participant has one durable action, atomically lock the turn; when the deadline arrives, atomically materialize durable `:wait` actions for missing ready participants before locking.
- A resolver always receives the **expected turn ID**. After it obtains the combat lock, it must reject that request as stale when the requested turn is no longer the combat's current unresolved turn; it must never fall through and resolve a newly-created next turn. This is required for retries, duplicated Oban jobs, and concurrent browser requests.
- Use PostgreSQL row locks and an Oban worker scheduled from the persisted deadline. Browser polling/countdown may refresh display state but can neither lock nor resolve a turn.
- If new schema is needed, generate it with `mix ecto.gen.migration ...`; never hand-author a migration filename. Phase 2's sandbox may deny the generator through its filesystem-lock policy, in which case report the environmental block rather than bypassing the rule.

### Legal action snapshots
- All player commands derive their actor from `current_scope`; combat ID, item ID, spell ID, target ID, action key, and incantation are untrusted selection values.
- Caster actions require the participant's selected owned grimoire, an inscribed owned base spell, and `MMGO.Spells.Incantation.normalize/1` for a one-to-six-word incantation. The stored snapshot fixes the accepted spell/base fields, normalized formula, legal target set, cooldown/fatigue limits, and deterministic bounds before the turn locks.
- Tool actions require a current carried item owned by that participant, a real item-template action, legal action/targeting mode, available quantity/durability, and a server-created snapshot of effects/costs. Quantity-consuming actions reserve their quantity while an open turn can still be replaced, then consume or release that reservation during finalization; a later market/inventory command cannot steal an already sealed combat resource.
- The engine receives only server-generated snapshots. It never derives mechanical effect data, costs, or targets from raw LiveView params and it preserves GDD §3.6's effect ordering: locked actions, fatigue/cooldowns, caster orchestration, deterministic tools, direct effects, environment updates/ticks, break/expiry, then shared HP.

### Runtime AI safety boundary
- Runtime spell AI is advisory within deterministic engine limits, not an authority over persistence. It receives the immutable turn snapshot, current states/environment, allowed target IDs, state primitive allowlist, and per-effect intensity/duration/range budgets.
- The provider may choose only valid outcomes inside those budgets. It cannot invent state IDs, targets, environment-result types, fatigue/cooldowns, action cancellations, rewards, or raw shared-HP values.
- Claim the turn and persist its immutable resolution input inside a short database transaction; call AI outside that lock; then lock again to apply exactly the claimed token. Retries reuse an audited successful response for that token or use the deterministic fallback, never double-apply a turn.
- Caster requests run with `Task.async_stream/3` outside the database transaction and preserve a deterministic action-order application. Tool actions never call AI.
- Provider, schema, timeout, or narration failure must produce a deterministic Russian fallback and an audited failed request; player-visible resolution never waits indefinitely for an external provider.

### Combat modes, stakes, and access
- Keep one `MMGO.Combat` engine with mode adapters for `:duel`, `:overworld_encounter`, `:dungeon_encounter`, and a bounded no-wager `:club_match` linked through existing club-event metadata. Brackets, ladders, rewards, party creation, and expedition creation remain Phases 6–8.
- Duels reject safe-zone initiation, settle the existing wager on defeat/flee, and no longer refund an active fight as a cancellation. Club matches have no wager/loot. Overworld and dungeon outcomes delegate to their existing encounter/run finalizers; dungeon failure continues through the existing sacrifice path.
- Flee is a sealed action, not a client navigation. It is unavailable while the character's current survival state says `flee_available? == false`; mode policy turns a legal flee into the documented forfeit/outcome.
- `Play.combat_state/2` and all combat commands must scope the actor. Participants can act; authorized spectators receive read-only state only: same-location/realm observers for duel and overworld, linked club members/attendees for club matches, and linked expedition members for dungeon combat.

### Player surface
- Replace `/combat`'s hard-coded design-pass script with a real `CombatLive` combat-ID route and server-rendered waiting, sealed, resolving, narration, outcome, error, and spectator states. Keep the Russian in-world tone but make every game command a normal LiveView form/button with stable IDs.
- `DuelLive` becomes a scoped duel lobby/pending-challenge surface and navigates an active combat to its ID route; it must not rely on `demo_opponent_id` or resolve a player turn immediately after a click.
- Required stable controls include `combat-screen`, `combat-turn-<id>`, `combat-deadline`, `combat-action-form`, `combat-action-kind`, `combat-cast-spell`, `combat-incantation`, `combat-tool-item`, `combat-tool-action`, `combat-target-<id>`, `combat-seal`, `combat-awaiting`, `combat-resolving`, `combat-narration-<turn-id>`, `combat-outcome`, `combat-flee`, and `combat-spectator`.

### the agent's Discretion
- Exact Russian copy, visual layout, responsive styling, Oban retry/backoff details, and test fixture names are discretionary provided the server-authoritative contracts above remain intact.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### GDD combat and runtime-AI rules
- `docs/MMGO_GDD.md` — §2.3 AI Spell Resolution and §3 Combat define the fixed state primitives, bounded AI role, modes, simultaneous turns, action UIs, resolution order, stakes, and win/flee rules.
- `.planning/REQUIREMENTS.md` — MAGIC-03, COMBAT-01 through COMBAT-05, and QUALITY-02 acceptance criteria.
- `.planning/PROJECT.md` — explains the intentional GDD/README runtime-AI reconciliation and the thin facade rule.

### Existing authority and persistence patterns
- `lib/mmgo/combat.ex`, `lib/mmgo/combat/engine.ex`, `lib/mmgo/combat/turn.ex`, `lib/mmgo/combat/action.ex`, and `lib/mmgo/combat/resolution.ex` — current combat lifecycle, locks, state ordering, and post-resolution hooks.
- `lib/mmgo/travel.ex` and `lib/mmgo/travel/complete_journey_worker.ex` — durable timed state plus idempotent Oban completion pattern.
- `lib/mmgo/spells/incantation.ex`, `lib/mmgo/spells/runtime.ex`, `lib/mmgo/spells/spell_effect.ex`, and Phase 3 artifacts — canonical incantation normalization, state primitive allowlist, compiled-spell bounds, and ownership/loadout contract.
- `lib/mmgo/ai.ex`, `lib/mmgo/ai/request.ex`, `lib/mmgo/combat/narrator.ex`, and `lib/mmgo/ai/providers/mock.ex` — provider abstraction, audit rows, narration, and local-test fallback conventions.

### Web and mode sources
- `lib/mmgo/play.ex`, `lib/mmgo_web/live/combat_live.ex`, `lib/mmgo_web/live/duel_live.ex`, and `lib/mmgo_web/router.ex` — current browser facade/routes and demo-only gaps.
- `lib/mmgo/pvp.ex`, `lib/mmgo/overworld.ex`, `lib/mmgo/dungeons.ex`, and `lib/mmgo/clubs.ex` — existing duel wager, overworld, dungeon, and club-event settlement sources.
- `AGENTS.md` — LiveView/form/test/migration rules.

</canonical_refs>

<specifics>
## Specific Ideas

- Preserve the existing seeded engine and event log rather than introduce a second combat simulator.
- Treat an AI narration/result as a durable turn artifact, not an ephemeral toast, so spectators and reconnecting players see the same resolved outcome.
- Keep the combat UI text-first and Russian; its timer is explanatory only, while the worker/database governs the deadline.

</specifics>

<deferred>
## Deferred Ideas

- Party creation/readiness, coordinated party UI, and live broadcasts are Phase 6.
- Dungeon run entry, navigation, extraction, and the full sacrifice/defeat presentation are Phase 7; Phase 4 only consumes existing combat-linked encounters and invokes their current finalizer.
- Club tournament scheduling, brackets, ladder/reward progression, and Academy event-loop UI are Phase 8; Phase 4 provides only a bounded no-wager match adapter for an existing club event.
- Inventory acquisition, generic persistent equipment management, and market/base transactions are Phase 5. Phase 4 selects already owned carried combat items and does not invent an economy UI.

</deferred>

---

*Phase: 04-timed-bounded-combat*  
*Context gathered: 2026-07-10*
