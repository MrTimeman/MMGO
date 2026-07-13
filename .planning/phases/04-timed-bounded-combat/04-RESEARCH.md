---
phase: 04-timed-bounded-combat
researched: 2026-07-10
---

# Phase 4 Research: Timed, Bounded Combat

## Existing foundation

- `MMGO.Combat` already persists combats, sides with shared HP, participants, turns, actions, and append-only events. `resolve_turn/1` locks the combat row and the pure-ish `MMGO.Combat.Engine` applies seeded variance, cooldowns, fixed state primitives, effects, environment tags, and winner detection.
- `MMGO.Combat.Engine` already enforces many mechanical rules at resolution time: selected grimoire entries, spell ownership, magic-zone suppression, status blocks, item ownership/action definitions, shield/exposed interactions, state ticks, and shared-side damage.
- `MMGO.PVP` creates escrowed duels and `MMGO.Combat.Resolution` already dispatches completed duel and dungeon combats to settlement/sync functions. `Overworld` and `Dungeons` can both create combat rows; dungeons can create NPC `actor_template` participants.
- `MMGO.Spells.Incantation.normalize/1`, `SpellEffect.supported_states/0`, compiled spells, `Inventory.ItemAction`, and `Inventory.available_quantity/1` provide the bounded inputs needed for action snapshots.
- `MMGO.AI` has provider-neutral structured/text calls, auditable `ai_requests`, mock/Gemini/DeepSeek providers, and `Combat.Narrator` can persist turn narration. Oban already schedules durable travel/scavenging completions and test configuration runs workers manually.

## Concrete gaps

1. `combat_turns` has no opening/deadline/claim/resolve timestamps and no `:resolving` state. `Combat.create_combat_instance/3` creates an open turn with no deadline.
2. `submit_action/3` fetches an unlocked current turn, trusts action shape until later engine resolution, and has no deadline or durable timeout wait. `maybe_lock_turn/2` counts records after the fact.
3. `resolve_turn/1` selects `runtime_combat.turn_number` after acquiring the lock. A caller that originally intended a prior turn can therefore resolve a fresh next turn if it arrives late. It needs an expected-turn argument and a stale rejection path.
4. Actions store raw payload plus foreign keys but no immutable normalized source/cost/target snapshot. A mutable spell, item template, inventory reservation, or target can change between submit and resolve.
5. The engine makes direct seeded spell decisions from compiled spell rows; it does not build a runtime AI-constrained cast request, does not persist an orchestration token, and `Narrator.narrate_turn/3` is not part of normal turn completion. Current `AI.Request` only permits `:spell_compile` and `:turn_narration`.
6. `/combat` is explicitly a scripted hard-coded design pass. `/pvp` is a Tower-only local-demo-bot flow that submits and resolves immediately, and its active cancellation refunds a wager rather than representing GDD flee/forfeit behavior.
7. Club events exist, but there is no combat link/mode; overworld combat escalates into a row but has no post-combat result adapter. Dungeon finalization exists but no shared scoped browser combat surface reaches it.
8. `README.md` still states that spells are not run through an LLM at combat time, while the GDD and project contract require bounded runtime orchestration. This is the explicit QUALITY-02 documentation gap.

## Recommended architecture

### 1. Durable lifecycle first

Generate a migration (never hand-name it) that adds `opened_at`, `deadline_at`, `locked_at`, `resolution_claimed_at`, and `resolved_at` to `combat_turns`, plus an index for due open turns. Extend the turn enum to `:open | :locked | :resolving | :resolved`.

Use a one-shot `ResolveTurnWorker` carrying `combat_id` and **turn_id**, scheduled from the persisted deadline. The worker and an all-actions-locked fast path call the same domain resolver. The resolver locks the combat and exact requested turn, verifies the requested turn is still the current unresolved turn, creates missing durable `:wait` actions at timeout, marks one claim, and rejects all stale/duplicate calls. This makes retry/worker behavior independent of a LiveView process.

### 2. Normalize before sealing; resolve snapshots only

Add an `ActionSnapshot` boundary. It validates all browser selections against the locked combat/participant and produces a map that captures only server-approved facts:

- cast: selected participant grimoire/owned base spell, canonical one-to-six-word formula, caster level, spell effects/budgets, allowed targets, cooldown/fatigue;
- tool: owned carried inventory item, item-template action key/effects/costs, legal target, and quantity/durability reservation;
- wait/flee: actor, mode policy, and legal target-free payload.

Persist the snapshot separately from display payload. Replacement while open releases the previous reservation before reserving the new one. Resolve from that snapshot, never from mutable client values. The engine should continue to own turn ordering and all side/state updates, but its deterministic phase should expose an intermediate bounded input for runtime caster orchestration.

### 3. Treat runtime AI as a bounded substep

Claim/persist the immutable turn input under lock, then call each caster request outside the transaction with `Task.async_stream/3`, bounded concurrency, and stable action-order reassembly. A new structured prompt/schema must enumerate the only allowed state primitives, target IDs, durations, intensity ceilings, environment result types, cooldown/fatigue ceilings, and Russian narrative field.

Validate every response against a server-owned result schema. On provider/schema/timeout failure, derive a deterministic result from the stored spell snapshot and seeded engine RNG, record a failed audit row, and persist a Russian fallback narration. Store/reuse a resolution token in `ai_requests.metadata` so retry does not make a second authoritative result for the same cast. Apply the resolved mechanical map in a second locked transaction, then narrate outside the write transaction and persist it if absent.

### 4. Thin facade and mode adapters

Create a scoped `Play.combat_state/2` plus submit/flee/duel-lobby commands. It is the only Web-facing composition layer; LiveViews must not query combat, PVP, inventory, or dungeon contexts directly for rules.

Use mode adapters around existing sources:

| Mode | Existing source | Phase 4 adapter contract |
|------|-----------------|--------------------------|
| duel | `PVP` + escrow | same-location non-safe-zone duels; flee forfeits instead of refunds; settlement pays the recorded winner |
| overworld | `Overworld` escalation | resolve linked encounter outcome and authorize same-location observers |
| dungeon | `Dungeons.start_encounter_combat/1` | keep existing encounter/sacrifice finalizer; authorize linked expedition members |
| club match | `Clubs.Event` metadata | bounded no-wager match from an active dueling event; active club members/attendees can observe; no brackets/ladders |

Replace static CombatLive with a `:id` route, ordinary `to_form/2`/`<.input>` action forms, server-selected controls, and read-only spectator mode. Preserve `/pvp` as the scoped challenge/pending lobby and route an active combat to `/combat/:id`.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| A delayed resolver runs after a new turn exists | pass expected `turn_id`; lock and reject stale rather than reading `combat.turn_number` as a new target |
| AI/network latency holds a database lock | split claim, external orchestration, and apply into short transactions; worker retries tokenized work |
| Duplicate jobs/reconnects double-spend a potion or resolve twice | unique action per participant, row locks, reservation release/consume inside final apply, one claimed token, and idempotency tests |
| Runtime model invents an effect or changes combat math | strict schema plus server validation against snapshot budgets and deterministic fallback |
| Mode work turns into party/dungeon/club roadmap work | adapter only existing combat records; creation/brackets/expeditions stay explicitly deferred |
| Migration generator remains sandbox-blocked | invoke `mix ecto.gen.migration` as required, report the environmental lock failure, and do not manually create a migration |

## Validation Architecture

- Domain lifecycle: `test/mmgo/combat_test.exs` and a new `test/mmgo/combat/resolve_turn_worker_test.exs` use injected `now`/direct worker calls, no sleeps, and concurrent sandbox-permitted tasks.
- Action/engine: `test/mmgo/tool_actions_test.exs`, `test/mmgo/combat/engine_test.exs`, and a new `test/mmgo/combat/action_snapshot_test.exs` prove normalized ownership/target/item constraints and immutable deterministic inputs.
- AI: new `test/mmgo/combat/orchestrator_test.exs` plus `test/mmgo/combat/narrator_test.exs` prove structured validation, fallback, audit linkage, token reuse, and Russian persisted output.
- Browser/modes: new `test/mmgo_web/live/combat_live_test.exs`, existing `duel_live_test.exs`, `action_hub_live_test.exs`, `dungeon_combat_integration_test.exs`, and `clubs_test.exs` prove scope, participant/spectator access, all action controls, settlement/flee, and each existing mode adapter.
- Final: focused Phase 4 suite, `mix format --check-formatted`, `git diff --check`, then `mix precommit` after shared changes stabilize.
