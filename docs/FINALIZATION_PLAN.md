# MMGO Finalization Plan

Scope: close every GDD gap identified by the 2026-04-19 implementation audit. Phases are ordered by dependency, not by chapter. Each phase lists GDD anchor, concrete deliverables, touched modules, and acceptance signal.

Baseline: 49 DONE / 23 PARTIAL / 3 MISSING subsystems (see audit). This plan targets the 26 non-DONE items plus the AI prompt surface the GDD describes but has not been built.

---

## Phase 0 — AI Prompt Surface (prerequisite for §2.3, §3.4, §10.2)

Today only `spell_compile` and `turn_narration` prompts exist, both thin. The GDD names four AI roles. Finalize all four as versioned prompt modules under `lib/mmgo/ai/prompts/`, each with `build/1`, `system_prompt/0`, `user_prompt/1`, and (where structured) `response_schema/0`.

1. **`spell_compile_prompt.ex` — rewrite.** Full state-primitive reference table, interaction-rule catalogue, failure-profile rubric, passive/utility mode guards, `name_ru` Russian name, intensity-budget examples, edge cases (0-word, 6-word, base-spell revamp).
2. **`turn_narration_prompt.ex` — rewrite.** Russian-only output, length budget per turn-size bucket, tone matrix (duel / dungeon trash / boss / PvP ambush), must-mention hooks (environment ticks, break conditions, summoning), no-invention clause, example in/out.
3. **`combat_orchestrator_prompt.ex` — new.** Implements GDD §3.4 Stage 2: input = engine intermediate result with value ranges; output = concrete picks (damage value within range, hit/miss within probability, which break_condition fires first). Hard constraint list: cannot add states, cannot exceed ranges, cannot cancel actions. Dramatic-priority heuristics.
4. **`dungeon_tick_prompt.ex` — new.** Implements §10.2: input = floor state, recent player activity, resource saturation; output = mutation directives (shift connections, spawn table delta, anomaly injection) from a bounded schema. Drives `MMGO.Dungeons.MaintenanceWorker`.

Register versions in `config/config.exs` under `prompt_versions`. Mock provider fixtures for all four.

Acceptance: `mix ai.test` round-trips all four prompts against the mock provider.

---

## Phase 1 — Combat Resolution (GDD §2.3, §3.4)

Wires the orchestrator prompt and the Russian narrative layer into the existing engine.

- `narrative_ru` field on `spell_effects` or AI response; surface in combat log UI.
- `MMGO.Combat.Orchestrator` module: takes `EngineResult{ranges}` → calls AI → returns `FinalResult{values}`. Validates picks against ranges server-side.
- Pipeline rewire in `lib/mmgo/combat/engine.ex` resolution steps 10 → 11 (Orchestrator) → 12 (Narrator).
- Telemetry + fallback: if AI fails, deterministic midpoint-of-range pick; log degraded turn.

Acceptance: integration test of a 2v2 duel producing deterministic engine ranges, mocked dramatic picks, and Russian narration in a single resolved turn.

---

## Phase 2 — Passive & Utility Spells (GDD §2.4)

Schema + compiler mode are in; runtime is not.

- Toggling as a combat action (1 AP). `silenced` blocks toggling, not the aura itself.
- Mana reservation deduction at cast-time; reduces `max_mana` for the fight.
- Passive tick hook at Stage 6 (environment update) for aura-on-enter effects.
- Utility spell casting outside combat: exposed via map/base UI action. Effects written to `dungeon_nodes.environment_states`.
- Enforce `targeting in [:self, :zone]` for utility; reject enemy-target compiled outputs.

Acceptance: a passive ward halves damage for 3 turns at cost of 30 reserved mana; a utility `revealed` spell uncovers a hidden node.

---

## Phase 3 — Grimoires (GDD §7.2)

- Write-once inscription: `inscribed_at` locked; attempts to rewrite error.
- Single-grimoire-in-combat enforcement at combat entry; stored vs. equipped distinction.
- Weight feeds `Expedition.carry_capacity` already present.
- UI: grimoire picker in pre-combat/pre-dungeon flow; grimoire crafting shop in city.

Acceptance: player with 3 grimoires at base can only bring one into a duel; bringing a second is rejected.

---

## Phase 4 — Alchemy Completion (GDD §8.2)

- Seed the full 15-ingredient canon per §8.2 into `seeds.exs`. Current seed set is partial.
- Ingredient drop tables: attach each ingredient to overworld regions and dungeon floors per rarity.

Acceptance: each of 15 named ingredients exists as `item_templates` row with correct `qualities` array; each has at least one drop source.

---

## Phase 5 — Academy Complete (GDD §9.4–9.11)

The term system, specialization, and core schemas exist. Finish the social surface.

### 5a. Bulletin Board (§9.4, §9.7)
- Add thesis-defense schedule section, valedictorian hall-of-fame (1 real year TTL), cohort leaderboard live view.
- Course catalog: player-authored `:course` publications override seeded sections for the term they are scheduled.

### 5b. Lectures & Exams (§9.5)
- Applied challenge exam questions: wizards submit an incantation graded by the Spell Compiler; alchemists pick ingredients graded against a stated effect; masters pick materials.
- Cheating probability roll on looted crib-sheet usage; reputation penalty + nullification.

### 5c. Clubs (§9.8)
- Event loop per club kind: general, dueling (no-wager PvP with bloodless death), research (partial contribution ledger), expedition planning (plan boost for next real run).
- Attendance enforcement: ≥ 1 club event/term required for merit scholarship and top-quartile rank.
- Club founding flow + fee.

### 5d. Professor Ties (§9.9)
- Office hours event: +5 grade-ceiling buff on attendance.
- Advisor selection on Academia entry. +20% research speed modifier.
- Recommendation letter item (non-transferable, single-use), unlocks gated paths.
- Professor reputation running score with defined deltas; rivalry flag on profiles.

### 5e. Thesis Defense (§9.10)
- Panel composition: advisor + 2 others with rival-preferred matching.
- Defense event: timed Q&A text event, panel vote `{accept, accept_with_revisions, reject}`.
- Reject → +1 game-season rework; two rejects → thesis abandoned, Professor status blocked.
- Open audience mode: any city-present character can spectate.

### 5f. Careers (§9.11)
- Professor stipend per teaching term, paid from tuition pool.
- Academy Head: plurality vote every 10 real days among Professors; grants seeded-curriculum override, charity-fund allocation, Probation admission.
- Researcher Emeritus soft off-ramp: retains publication + letter rights, no teaching.

Acceptance: a Probation graduate enters Core via a Professor letter; that Professor later chairs a thesis panel that rejects, docking their reputation.

---

## Phase 6 — Dungeon Depth (GDD §10.2, §10.3, §10.4)

### 6a. Dungeon AI tick (§10.2)
- Wire `dungeon_tick_prompt` into `MaintenanceWorker`: periodic mutation of node graph connections, spawn table weights, anomaly events driven by recent player activity windows.
- Mutation budget caps to prevent overactive shifts.

### 6b. Communities (§10.3)
- Micro-village nodes on floors 1–2: rest stops with `:shop`, `:tavern`, `:trading_post` interactions. Use existing events system.
- NPC traders carrying dungeon-rare stock.

### 6c. Deep Return Ritual components (§10.4)
- Floor-gated component requirements on Return Ritual: floors 1–3 free, 4–5 require one rare component, 6–7 require two.

Acceptance: a deep-floor party cannot return without the required component; a floor-1 resting village is browsable with tavern social hub.

---

## Phase 7 — Map & Travel Polish (GDD §5.5)

### 7a. Secret Cult fast-travel (§5.5)
- Discovery quest chain (hidden; triggered by NPC dialogue breadcrumb or player-following mechanic).
- Membership grants one-way or two-way city↔Tower passage. Decide: per-trip cost vs. membership dues (recommend small per-trip fee).
- Revocation: failed cult task or public betrayal.

Acceptance: player completes quest, gains `cult_member` status, uses cult passage from city to Tower in under 5 real minutes of game time.

---

## Phase 8 — Progression Milestones (GDD §11.3)

- Define milestone-level table (e.g., 5/12/20/35/50/70/90) with qualitative unlocks: extra grimoire slot, new dungeon tier access, Academy teaching eligibility, fast-travel unlock, passive mana-reservation efficiency.
- Place at uneven intervals per GDD intent.

Acceptance: reaching level 20 grants a displayed milestone unlock notification and the capability activates.

---

## Phase 9 — Charity Fund & Donation UX (GDD §12.5, §15.1)

Backend in place; surfaces missing.

- In-game charity donation UI on city Treasury/Academy views; confirmation, public donor board list, titles.
- Real-money donation page (external link) with cosmetic recognition hooks. No mechanical benefit.

Acceptance: donor of ≥ threshold X appears on public donor board with their title.

---

## Phase 10 — Audio System (GDD §16.5) — MISSING

Entirely unbuilt. Hybrid adaptive + curated-cue system.

- Client-side audio manager (assets/js): two buses — adaptive layer + cue layer. Cue overrides adaptive.
- Semantic trigger map: game-state → cue key. Families per GDD: `travel.safe`, `travel.danger`, `dungeon.explore.upper`, `dungeon.explore.deep`, `combat.duel.elite`, `combat.boss`, `tower.arrival`.
- Adaptive layer: lightweight generative loop (tonal pad + procedural rhythm) parameterized by game state; NOT a full Endel replacement, just non-fatiguing.
- Curated cue inventory: 8–12 seed cues licensed or original, keyed to semantic triggers. Public-domain-composition rule: in-house arrangements only; no random recordings.
- Broadcast: server emits `audio_cue` PubSub events on state transitions; client routes through the cue layer.

Acceptance: entering Tower triggers the `tower.arrival` cue, fades back to `dungeon.explore.upper` adaptive after the event ends.

---

## Cross-cutting work

- **Prompt version bumps**: every Phase 0/1 prompt rewrite bumps `prompt_versions` and mock fixtures.
- **Test coverage**: one integration test per phase acceptance clause above.
- **Telemetry**: AI failure fallbacks logged; orchestrator range violations flagged.
- **Localization**: `narrative_ru` and key exam / lecture copy must ship Russian-first per GDD.

---

## Sequencing

Critical path: **0 → 1 → 2 → 6a** (AI surface → combat → passives/utility → dungeon tick). These unblock each other.

Parallelizable against the critical path: Phase 3 (grimoires), Phase 4 (alchemy seeds), Phase 7 (cult), Phase 9 (donation UX), Phase 10 (audio).

Phase 5 (Academy) is the largest chunk and internally sequential: 5a → 5b/5c → 5d → 5e → 5f.

Phase 8 depends on Phase 5d being partly in (teaching eligibility unlock hooks into Professor state).

---

## Out of scope for this plan

- Third-person lore expansion beyond what existing NPC/dialogue scaffolding supports.
- New realms or custom-rule authoring tooling for federation operators (core federation is already DONE).
- PvE balance passes — will happen iteratively after Phase 1 lands.
