# Roadmap: MMGO Full GDD Completion

## Overview

This roadmap turns the existing domain-rich Phoenix prototype into the complete account-owned MMO described by `docs/MMGO_GDD.md`. It starts by securing identity and shared world state, then wires increasingly social gameplay loops through thin server-authoritative facades, adds the few missing state machines, and finishes with organisation power, semantic ambience, and full product verification.

## Phases

**Phase Numbering:**
- Integer phases are planned completion work.
- Decimal phases may be inserted for urgent blockers discovered during delivery.

- [x] **Phase 1: Secure Player Identity** - Turn existing Telegram identities into verified scoped browser sessions and remove shared-demo authority from gameplay. (completed 2026-07-10)
- [x] **Phase 2: Living World, Activities, and Survival** - Make map time, location hubs, overworld interactions, scavenging, and survival real player state. (completed 2026-07-10)
- [x] **Phase 3: Real Spellbook and Loadouts** - Replace spell/grimoire demo UI with location-gated, owned spell composition and loadout commands. (completed 2026-07-10)
- [x] **Phase 4: Timed, Bounded Combat** - Deliver durable simultaneous turns, caster/tool actions, runtime AI orchestration, and complete combat UI flows. (completed 2026-07-11)
- [x] **Phase 5: Economy, Bases, and Workshops** - Wire inventory, markets, base storage/building, crafting, alchemy, and financial consequences. (verified 2026-07-22)
- [x] **Phase 6: Social Parties and Live Coordination** - Deliver player interaction, parties, readiness, notifications, and realtime social state. (verified 2026-07-22)
- [x] **Phase 7: Playable Dungeon Expeditions** - Expose the existing dungeon engine as a full party expedition loop with survival, combat, extraction, and sacrifice. (verified 2026-07-22)
- [x] **Phase 8: Academy and Academia Careers** - Complete terms, clubs, ranking, research, professor ties, and thesis defense state flows. (verified 2026-07-22)
- [x] **Phase 9: Realm Discovery and Migration** - Surface notifications, realm browsing, and accurate federation migration to players. (verified 2026-07-22)
- [x] **Phase 10: Organisations, Assets, and Shares** - Turn organisation v1 into real web play and add treasury, ownership, and share-aware assets. (verified 2026-07-22)
- [x] **Phase 11: Governance, Territory, and Diplomacy** - Add enforceable governance blocks, collective decisions, territory data, and real map filters. (verified 2026-07-22)
- [x] **Phase 12: Atmosphere, Product Quality, and GDD Audit** - Add semantic audio/accessibility/reliability polish and prove the literal GDD completion target. (verified 2026-07-22)

## Phase Details

### Phase 1: Secure Player Identity
**Goal**: A Telegram Mini App player enters an account-owned scoped LiveView session, while local demo fixtures remain safe and isolated.
**Depends on**: Nothing (first phase)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04
**Success Criteria** (what must be TRUE):
  1. A valid Telegram `initData` request creates or resumes only its verified account-owned character and a forged/expired request is rejected.
  2. All game LiveViews run in an authenticated `live_session` with `current_scope`, and changing a client parameter cannot operate another character.
  3. Development/demo entry is explicitly isolated and tests can create independent scoped characters without shared global demo state.
  4. Production webhook configuration fails closed while test and local flows remain credential-free and covered.
**Plans**: 4 plans

Plans:
- [x] 01-01: Validate Telegram Mini App init data and harden webhook configuration.
- [x] 01-02: Create account-owned current scope and LiveView authorization guard.
- [x] 01-03: Build Mini App entry UI/controller and authenticated game routes.
- [x] 01-04: Migrate current browser flows and isolate local demo behavior.

### Phase 2: Living World, Activities, and Survival
**Goal**: The map and activity hubs reflect canonical time, owned location state, real interactions, and survival consequences.
**Depends on**: Phase 1
**Requirements**: WORLD-01, WORLD-02, WORLD-03, WORLD-04, WORLD-05, SURV-01, SURV-02, SURV-03
**Success Criteria** (what must be TRUE):
  1. A signed-in player sees canonical game time, their persisted location/journey, valid destinations, and only location-allowed actions.
  2. Map and hub state show real authorized events, nearby actors, notifications, realm data, and no hard-coded profile/calendar values.
  3. A player can scavenge and resolve the result through persisted server time, inventory, XP, and capacity rules.
  4. Food depletion progresses over time into the GDD speed/HP penalties and recovery, while overload rules are visible and enforced.
  5. Overworld interaction choices and magic restrictions are authoritative and covered by focused player-flow tests.
**Plans**: 4 plans

Plans:
- [x] 02-01: Add canonical calendar, scoped world read model, and truthful map overlays.
- [x] 02-02: Replace the demo location screen with scoped persistent text events.
- [x] 02-03: Wire nearby-player overworld interactions through authoritative commands.
- [x] 02-04: Add durable starvation consequences and browser scavenging/survival state.

### Phase 3: Real Spellbook and Loadouts
**Goal**: Casters manage their actual spell library and grimoires, then compose legal spells at permitted locations.
**Depends on**: Phase 2
**Requirements**: MAGIC-01, MAGIC-02
**Success Criteria** (what must be TRUE):
  1. A player sees only their own persisted library, grimoires, capacity, inscriptions, and active loadout.
  2. A caster can select a real base spell, enter a 1–6 word incantation, receive validation/result feedback, and persist the completed spell/library changes.
  3. Grimoire write-once, capacity, ownership, and location constraints reject invalid commands server-side.
  4. The LiveView has focused form/action tests against an owned scoped session rather than hard-coded demo assigns.
**Plans**: 3 plans

- [x] 03-01: Require an owned same-realm base and preserve compiler-owned lineage.
- [x] 03-02: Lock inscription and owner-wide activation for durable loadouts.
- [x] 03-03: Expose scoped Tower/base spellbook forms and explicit loadout actions.

### Phase 4: Timed, Bounded Combat
**Goal**: Every combat mode uses durable simultaneous turns, legal class-specific actions, bounded runtime AI enrichment, and readable outcomes.
**Depends on**: Phase 3
**Requirements**: MAGIC-03, COMBAT-01, COMBAT-02, COMBAT-03, COMBAT-04, COMBAT-05, QUALITY-02
**Success Criteria** (what must be TRUE):
  1. Combat persists a turn deadline, safely resolves timeouts/idempotent retries, and locks concurrent actions without process-local state.
  2. Casters submit owned grimoire/incantation actions and tool users submit owned item/action/target commands from real combat UI.
  3. Location magic rules, shared HP, status/environment effects, fatigue, cooldowns, wagers/loot, and flee/settlement behavior are enforced for the mode.
  4. Runtime AI output and Russian narration are schema-constrained by deterministic engine limits, mocked in tests, and documented consistently with the GDD.
  5. Duel, club, dungeon, and overworld participants/spectators can observe a clear resolved turn/outcome flow.
**Plans**: 4 plans

- [x] 04-01: Persist deadline lifecycle, exact-turn resolver ownership, and idempotent deadline workers.
- [x] 04-02: Normalize server-authoritative action snapshots and resolve only immutable legal state.
- [x] 04-03: Add bounded runtime orchestration, durable Russian narration, and deterministic fallback.
- [x] 04-04: Replace demo combat screens with scoped participant/spectator flows and mode finalizers.

### Phase 5: Economy, Bases, and Workshops
**Goal**: Real owned inventory connects markets, base life, financial state, crafting, and alchemy into completed browser transactions.
**Depends on**: Phase 2
**Requirements**: ECON-01, ECON-02, ECON-03, ECON-04, ECON-05, ECON-06
**Success Criteria** (what must be TRUE):
  1. A player can inspect and move real owned carried/base inventory with capacity and permission errors shown clearly.
  2. Legal market, NPC, charity/tuition, and black-market actions settle atomically with visible tax/treasury/reputation consequences.
  3. A player can acquire/use a base for storage, rest, composition, and permitted construction work.
  4. Crafting and alchemy jobs can be started, monitored, collected, and recovered from through the browser using real materials/recipes/tools.
  5. Financial and inventory commands cannot trust client authority or leave partial state after a failure.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 6: Social Parties and Live Coordination
**Goal**: Players can encounter each other, create/coordinate parties, and receive live authoritative social updates.
**Depends on**: Phases 2 and 4
**Requirements**: SOCIAL-01, SOCIAL-02, SOCIAL-03
**Success Criteria** (what must be TRUE):
  1. Players can find authorized nearby players, greet/trade/attack/avoid, and see the resulting persisted social/event state.
  2. Players can create, invite, join, leave, and configure real parties with readiness, supplies, and loot choices visible to members.
  3. Character, party, journey, combat, and notification updates reach affected LiveViews only after committed changes.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 7: Playable Dungeon Expeditions
**Goal**: A party can complete a real dungeon expedition through the browser using the existing graph, maintenance, combat, survival, loot, extraction, and sacrifice systems.
**Depends on**: Phases 4, 5, and 6
**Requirements**: DUNGEON-01, DUNGEON-02, DUNGEON-03, DUNGEON-04
**Success Criteria** (what must be TRUE):
  1. A qualified party enters the Tower dungeon and navigates persisted graph nodes/links with only legal actions displayed.
  2. Dungeon encounters, combat, scavenging, rest/micro-village choices, food/weight pressure, resources, and loot run through real state.
  3. Ascents, return ritual, extraction, defeat, sacrifice losses, retained XP, and return-to-surface consequences are visible and durable.
  4. Focused end-to-end tests prove a player-owned expedition rather than a static dungeon screen.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 8: Academy and Academia Careers
**Goal**: Students and academics complete real term, club, research, professor, and thesis-defense loops.
**Depends on**: Phases 3, 5, and 6
**Requirements**: ACADEMY-01, ACADEMY-02, ACADEMY-03, ACADEMY-04, ACADEMY-05
**Success Criteria** (what must be TRUE):
  1. A student can progress through ordered enrollment, courses, lectures, clubs, midterms, finals, and breaks with server-owned timing/state.
  2. Grades, GPA, ranks, graduation tiers, scholarship outcomes, starter rewards, and career options render from real data.
  3. Club events and professor/advisor/course/publication/reputation actions produce their promised persisted effects.
  4. Thesis defenses support scheduling, spectators, a valid three-professor panel, votes, rework/rejection, and worker resolution without an invalid state transition.
  5. All Academy/Academia screens use scoped session data and focused integration tests instead of demo assigns.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 9: Realm Discovery and Migration
**Goal**: Players can see notification history, discover real realms, and understand/perform federation migration correctly.
**Depends on**: Phases 1 and 5
**Requirements**: REALM-01, REALM-02, REALM-03
**Success Criteria** (what must be TRUE):
  1. A player can view their own in-app notifications and the relationship to Telegram delivery state.
  2. A player can browse registered realms with truthful rules/population/activity data and select a migration destination.
  3. The migration UI accurately represents/executes freeze, identity, XP/currency conversion, inventory/base retention, and spell-library incompatibility rules.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 10: Organisations, Assets, and Shares
**Goal**: Organisation v1 becomes real player web functionality and v2 adds transactional collective assets.
**Depends on**: Phases 5, 6, and 9
**Requirements**: ORG-01, ORG-02
**Success Criteria** (what must be TRUE):
  1. A scoped player can found, browse, invite, join, manage, and leave the four organisation kinds through real persistence/permission checks.
  2. Organisation-linked fast travel and member roles work from the browser without mock org data.
  3. Organisations have durable treasury, asset/property/infrastructure ownership, and share-aware profit/permission behavior.
  4. Asset and money transitions are transactional, auditable, and covered by ownership/permission tests.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 11: Governance, Territory, and Diplomacy
**Goal**: Organisations can govern collectively and visibly shape the realm map through generic, enforced data rules.
**Depends on**: Phase 10
**Requirements**: ORG-03, ORG-04, ORG-05
**Success Criteria** (what must be TRUE):
  1. Founders/members can compose governance blocks for leadership, membership, spending, succession, and decision rules, and commands enforce them generically.
  2. Players can create/participate in elections, referenda, share-weighted decisions, alliances, rivalries, and conflict outcomes according to their organisation rules.
  3. Political, infrastructure, economic, and diplomacy map overlays render real control/relationship data and respect player access.
  4. Organisation tests prove that changing a browser parameter cannot bypass governance or ownership rules.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

### Phase 12: Atmosphere, Product Quality, and GDD Audit
**Goal**: Complete semantic ambience, resilient/accessibile UX, automated quality evidence, and a literal final GDD compliance audit.
**Depends on**: Phases 1 through 11
**Requirements**: ATMOS-01, ATMOS-02, QUALITY-01, QUALITY-03, QUALITY-04
**Success Criteria** (what must be TRUE):
  1. Gameplay emits semantic ambient/event audio cues, curated priority overrides ambience, and missing assets fail gracefully.
  2. Core gameplay surfaces have stable accessible controls plus meaningful loading, empty, error, permission, and reconnect states.
  3. Every requirement has focused domain/LiveView coverage that exercises account-owned server-authoritative outcomes.
  4. `mix precommit` passes with stale demo tests/screens removed or migrated, and no prohibited monetisation mechanic exists.
  5. A final evidence-based audit maps every GDD section to implemented/verified behavior and finds no remaining demo-only player loop.
**Plans**: Implemented outside the original plan artifacts; verified by the alpha audit.

## Progress

**Execution Order:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Secure Player Identity | 4/4 | Complete   | 2026-07-10 |
| 2. Living World, Activities, and Survival | 4/4 | Complete | 2026-07-10 |
| 3. Real Spellbook and Loadouts | 3/3 | Complete | 2026-07-10 |
| 4. Timed, Bounded Combat | 4/4 | Complete | 2026-07-11 |
| 5. Economy, Bases, and Workshops | Implemented outside tracker | Complete | 2026-07-22 |
| 6. Social Parties and Live Coordination | Implemented outside tracker | Complete | 2026-07-22 |
| 7. Playable Dungeon Expeditions | Implemented outside tracker | Complete | 2026-07-22 |
| 8. Academy and Academia Careers | Implemented outside tracker | Complete | 2026-07-22 |
| 9. Realm Discovery and Migration | Implemented outside tracker | Complete | 2026-07-22 |
| 10. Organisations, Assets, and Shares | Implemented outside tracker | Complete | 2026-07-22 |
| 11. Governance, Territory, and Diplomacy | Implemented outside tracker | Complete | 2026-07-22 |
| 12. Atmosphere, Product Quality, and GDD Audit | Implemented outside tracker | Complete | 2026-07-22 |
