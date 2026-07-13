# Requirements: MMGO Full GDD Completion

**Defined:** 2026-07-09
**Core Value:** A player can make meaningful, account-owned decisions in a persistent social magical world and see their consequences reflected immediately.

## v1 Requirements

### Identity and Access

- [x] **AUTH-01**: A Telegram Mini App request is verified server-side from `initData` before it can create or resume a player session.
- [x] **AUTH-02**: A signed browser/LiveView session identifies exactly one account-owned character and every game command derives its actor from that scope.
- [x] **AUTH-03**: Local development retains an isolated demo entry path that cannot impersonate or mutate a real player account.
- [x] **AUTH-04**: Telegram webhook authorization fails closed in production configuration and all credential-dependent paths remain testable with safe mocks.

### World and Travel

- [x] **WORLD-01**: The map and player screens display one canonical compressed 13-month game clock derived from server time.
- [x] **WORLD-02**: A player can see their real current location, journey progress, allowed location-gated activities, and server-authoritative destination choices.
- [x] **WORLD-03**: Map state reflects authorized nearby actors, interactions/events, notifications, realm information, and organisation overlays instead of fixed demo assigns.
- [x] **WORLD-04**: A player can use a real text-based activity hub at city, base, Tower, wilderness, and dungeon locations to navigate only valid actions.
- [x] **WORLD-05**: Overworld travel enforces magic-zone rules and supports player interaction choices (greet, trade, attack, avoid) through authoritative commands.

### Survival and Exploration

- [x] **SURV-01**: Travel and expeditions consume food over game time, apply progressive speed/HP penalties when food runs out, and recover correctly when supplies return.
- [x] **SURV-02**: A player can start and resolve location-appropriate scavenging with persisted time, loot, XP, and inventory-capacity consequences.
- [x] **SURV-03**: Carry weight, grimoire weight, food, loot, overload, and flee/movement penalties are visible and enforced in player flows.

### Magic and Spell Library

- [x] **MAGIC-01**: A caster can view their owned library and grimoires, choose a legal base spell, compose a 1–6 word incantation, and persist a compiled result.
- [x] **MAGIC-02**: Spell creation, ownership, grimoire capacity/write-once rules, active loadout, and recursive library progression are exposed through real UI commands.
- [x] **MAGIC-03**: Runtime spell orchestration accepts only schema-constrained effects within deterministic engine state primitives and provides a mockable fallback.

### Combat

- [x] **COMBAT-01**: All combat modes persist simultaneous-turn deadlines, action locks, timeout waits, and idempotent resolution under database concurrency.
- [x] **COMBAT-02**: Casters can submit a legal grimoire/incantation action and tool users can submit a legal equipped-item/action/target command from the browser.
- [x] **COMBAT-03**: Combat respects location magic restrictions, shared party HP, status/environment effects, fatigue/cooldowns, and mode-specific stakes.
- [x] **COMBAT-04**: A bounded AI orchestration/narration layer produces player-readable Russian turn results without bypassing deterministic limits.
- [x] **COMBAT-05**: Players can initiate, accept, spectate, flee, settle, and review real duel/club/dungeon/overworld combat outcomes according to their rules.

### Inventory, Economy, Bases, and Crafting

- [x] **ECON-01**: A player can inspect and move real owned inventory between carried storage and their base while capacity and permissions are enforced.
- [x] **ECON-02**: A player can use legal markets, NPC shops, charity/tuition, taxed transfers, and black-market trades through complete browser transactions.
- [x] **ECON-03**: A player can acquire, view, and use a base for protected storage, rest, spell composition, and permitted construction actions.
- [x] **ECON-04**: A player can start, monitor, collect, and recover from real alchemy brewing and crafting workshop jobs using owned recipes/materials/tools.
- [x] **ECON-05**: Economy screens expose relevant balance, treasury, tax, reputation, and transaction consequences without demo values.
- [x] **ECON-06**: No money, item, escrow, or ownership command accepts client-provided authority or leaves a partial transaction after failure.

### Parties and Dungeon Expeditions

- [x] **SOCIAL-01**: Players can create/invite/join/leave parties, choose visible expedition/loot settings, and see party supplies/readiness through real UI.
- [x] **SOCIAL-02**: Party events, club connections, overworld interactions, and player notifications create observable social consequences without static mock participants.
- [x] **SOCIAL-03**: A party receives live relevant updates for membership, journey, combat, and expedition state after committed changes.
- [x] **DUNGEON-01**: A qualified player/party can enter the Tower dungeon, navigate actual graph nodes/links, and see legal available actions.
- [x] **DUNGEON-02**: Dungeon runs support encounters, combat, scavenging, food/weight pressure, loot/resources, micro-village/rest choices, ascent, and return ritual flows.
- [x] **DUNGEON-03**: Dungeon defeat/extraction persists the GDD sacrifice/reward consequences, including inventory/grimoire loss, retained XP, and surface return.
- [x] **DUNGEON-04**: Dungeon activity uses the existing dynamic maintenance/content machinery through a playable browser loop rather than module-attribute demo data.

### Academy and Academia

- [x] **ACADEMY-01**: Students can complete a real ordered term loop: enrollment, bulletin/course selection, lectures, club window, midterm, final, and term break.
- [x] **ACADEMY-02**: Academy UI exposes real grades, GPA, cohort rank, graduation/failure tiers, scholarships, starter outcomes, and career progression.
- [x] **ACADEMY-03**: Club types and events produce their intended persisted rewards/relationships/ladder or expedition effects through player actions.
- [x] **ACADEMY-04**: Professor/advisor/course/publication/reputation workflows are player-facing and enforce real permissions and relationships.
- [x] **ACADEMY-05**: Thesis defenses support a valid three-professor panel, public scheduling/spectating, vote outcomes, rework/rejection consequences, and a regression-tested state machine.

### Realms, Notifications, and Federation

- [x] **REALM-01**: A player can see real in-app game notifications and delivery state alongside Telegram notification integration.
- [x] **REALM-02**: A player can browse available realms with rules/population/activity and start an authorized migration from the browser.
- [x] **REALM-03**: Realm migration, freeze, character identity, XP/currency conversion, inventory/base retention, and incompatible spell-library behavior are surfaced accurately to the player.

### Organisations and Realm Power

- [x] **ORG-01**: Players can found, browse, join, invite, manage, and use v1 organisations and org-linked fast travel through real account-owned web UI.
- [x] **ORG-02**: Organisations have transactional treasuries, assets/property/infrastructure ownership records, and share-aware profit/permission handling.
- [x] **ORG-03**: Organisations can compose governance blocks for leadership, membership, spending, succession, and voting, and the engine enforces them generically.
- [x] **ORG-04**: Players can execute and observe elections, referenda, share-weighted decisions, rivalries, alliances, and other governance/diplomacy outcomes.
- [x] **ORG-05**: Map filters display political, infrastructure, economic, and diplomacy overlays derived from real organisation control data.

### Atmosphere, Accessibility, and Quality

- [x] **ATMOS-01**: Gameplay state emits semantic ambient and major-event audio cues, with curated cues overriding ambience and graceful behavior when no asset is configured.
- [x] **ATMOS-02**: Core game screens provide clear loading, empty, permission, failure, and reconnect states with stable accessible controls and testable DOM IDs.
- [x] **QUALITY-01**: Every completed requirement has focused domain and/or LiveView coverage using owned sessions and server-authoritative outcomes.
- [x] **QUALITY-02**: The GDD/README AI-resolution contract is reconciled in product documentation and deterministic tests cover the safety boundary.
- [x] **QUALITY-03**: `mix precommit` passes with no stale demo-screen tests left behind by completed wiring work.
- [x] **QUALITY-04**: The product contains no pay-to-win mechanics, premium currency, loot boxes, or real-money gameplay advantage.

## GDD v0.9 Decision Deltas (added 2026-07-13)

Owner decisions on 2026-07-13 resolved four GDD TBDs (see `docs/MMGO_GDD.md` v0.9). Each creates new work against the updated contract:

- [ ] **DELTA-01**: Legal-transaction tax rate is realm-operator-configurable (canonical default 5%) instead of the hardcoded `@legal_market_tax_rate_bps` in `MMGO.Play`.
- [ ] **DELTA-02**: Untaxed black-market deals carry probabilistic NPC detection scaling with deal size; caught → fine (multiple of evaded tax, via `MMGO.Reputation.record_crime`) + reputation hit. (Only deal-default penalties exist today.)
- [ ] **DELTA-03**: Base acquisition has real costs: city purchase charges coins at a listed taxed price; building anywhere requires coins + gathered materials + game-days of construction. (Currently free.)
- [ ] **DELTA-04**: Alchemy is AI-interpreted brewing over fixed per-item alchemical primitives with inventory ingredient selection, schema-bounded like the spell compiler. (Current implementation is fixed-recipe brewing.)

## v2 Requirements

No deliberate deferrals: the user explicitly requested full GDD completion. Production secrets, external federation peers, and licensed soundtrack recordings remain deployment/content inputs rather than source requirements.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Copyrighted audio recordings | The semantic system is build scope; recording licensing is an external content decision. |
| Real-money gameplay benefits | Prohibited by the GDD's no-pay-to-win principle. |
| Committed production credentials | Unsafe and incompatible with environment-owned deployment configuration. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Complete |
| AUTH-02 | Phase 1 | Complete |
| AUTH-03 | Phase 1 | Complete |
| AUTH-04 | Phase 1 | Complete |
| WORLD-01 | Phase 2 | Complete |
| WORLD-02 | Phase 2 | Complete |
| WORLD-03 | Phase 2 | Complete |
| WORLD-04 | Phase 2 | Complete |
| WORLD-05 | Phase 2 | Complete |
| SURV-01 | Phase 2 | Complete |
| SURV-02 | Phase 2 | Complete |
| SURV-03 | Phase 2 | Complete |
| MAGIC-01 | Phase 3 | Complete |
| MAGIC-02 | Phase 3 | Complete |
| MAGIC-03 | Phase 4 | Complete |
| COMBAT-01 | Phase 4 | Complete |
| COMBAT-02 | Phase 4 | Complete |
| COMBAT-03 | Phase 4 | Complete |
| COMBAT-04 | Phase 4 | Complete |
| COMBAT-05 | Phase 4 | Complete |
| ECON-01 | Phase 5 | Complete |
| ECON-02 | Phase 5 | Complete |
| ECON-03 | Phase 5 | Complete |
| ECON-04 | Phase 5 | Complete |
| ECON-05 | Phase 5 | Complete |
| ECON-06 | Phase 5 | Complete |
| SOCIAL-01 | Phase 6 | Complete |
| SOCIAL-02 | Phase 6 | Complete |
| SOCIAL-03 | Phase 6 | Complete |
| DUNGEON-01 | Phase 7 | Complete |
| DUNGEON-02 | Phase 7 | Complete |
| DUNGEON-03 | Phase 7 | Complete |
| DUNGEON-04 | Phase 7 | Complete |
| ACADEMY-01 | Phase 8 | Complete |
| ACADEMY-02 | Phase 8 | Complete |
| ACADEMY-03 | Phase 8 | Complete |
| ACADEMY-04 | Phase 8 | Complete |
| ACADEMY-05 | Phase 8 | Complete |
| REALM-01 | Phase 9 | Complete |
| REALM-02 | Phase 9 | Complete |
| REALM-03 | Phase 9 | Complete |
| ORG-01 | Phase 10 | Complete |
| ORG-02 | Phase 10 | Complete |
| ORG-03 | Phase 11 | Complete |
| ORG-04 | Phase 11 | Complete |
| ORG-05 | Phase 11 | Complete |
| ATMOS-01 | Phase 12 | Complete |
| ATMOS-02 | Phase 12 | Complete |
| QUALITY-01 | Phase 12 | Complete |
| QUALITY-02 | Phase 4 | Complete |
| QUALITY-03 | Phase 12 | Complete |
| QUALITY-04 | Phase 12 | Complete |

**Coverage:**
- v1 requirements: 52 total
- Mapped to phases: 52
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-09*
*Last updated: 2026-07-13 — code audit found the tracker badly stale: all 52 v1 requirements verified against implementation + tests (618 tests green, `mix precommit` clean: compile --warnings-as-errors, format, test). Evidence: `MMGO.Play` facade covers every requirement family; every domain context and every LiveView has a focused test file. Added v0.9 decision deltas as new open items.*
