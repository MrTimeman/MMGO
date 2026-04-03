# Roadmap: MMGO

## Overview

MMGO already has a large backend simulation foundation. The roadmap is therefore focused on converting existing gameplay systems into a coherent Telegram Mini App product: first make player access and world travel usable, then expose progression and economy loops, then ship social and combat play, and finally harden live operations and federation edges for a real service.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Telegram Access and Player Shell** - Turn Telegram identity and session bootstrap into a usable player entry flow.
- [ ] **Phase 2: World Travel Loop** - Surface location, routes, journeys, and travel-driven event states in the Mini App.
- [ ] **Phase 3: Spellcraft and Study Surfaces** - Expose spell, Academy, and job-based progression loops to players.
- [ ] **Phase 4: Inventory, Trade, and Reputation** - Connect economy systems to clear player-facing inventory and market flows.
- [ ] **Phase 5: Parties, Notifications, and Social Structures** - Make shared play and async coordination work through the app and bot together.
- [ ] **Phase 6: Expeditions, Combat, and Duels** - Ship playable dungeon, combat, extraction, and duel flows.
- [ ] **Phase 7: Live Operations and Federation Readiness** - Harden operator recovery and federation edges for production use.

## Phase Details

### Phase 1: Telegram Access and Player Shell
**Goal**: Players can launch MMGO from Telegram into a persistent, recoverable Mini App session with clear account and character context.
**Depends on**: Nothing (first phase)
**Requirements**: [ACCESS-01, ACCESS-02, ACCESS-03, ACCESS-04]
**UI hint**: yes
**Canonical refs**:
- `README.md`
- `docs/MMGO_GDD.md`
- `docs/TECH_ARCHITECTURE.md`
- `lib/mmgo_web/router.ex`
- `lib/mmgo_web/controllers/page_html/home.html.heex`
- `lib/mmgo/telegram/update_handler.ex`
**Success Criteria** (what must be TRUE):
  1. Player can launch MMGO from Telegram into a linked session without manual setup.
  2. New and returning players see a usable shell with current character context and next actions.
  3. Failed bootstrap states explain what went wrong and how to recover.
  4. Telegram deep links restore the correct Mini App context.
**Plans**: 2 plans

Plans:
- [x] 01-01: Telegram identity, linking, and deep-link routing
- [ ] 01-02: Player shell, character snapshot, and recovery states

### Phase 2: World Travel Loop
**Goal**: Players can understand where they are, where they can go, and how travel evolves over time.
**Depends on**: Phase 1
**Requirements**: [WORLD-01, WORLD-02, WORLD-03, WORLD-04]
**UI hint**: yes
**Canonical refs**:
- `docs/MMGO_GDD.md`
- `docs/TECH_ARCHITECTURE.md`
- `lib/mmgo/travel.ex`
- `lib/mmgo/travel/clock.ex`
- `assets/js/hooks/travel-compass.js`
- `assets/js/hooks/event-scroll.js`
**Success Criteria** (what must be TRUE):
  1. Player can inspect current location, destinations, ETA, and route constraints in one world view.
  2. Player can start travel and later return to completed or ongoing journey state.
  3. Food, carry-capacity, and route blockers are visible before commitment.
  4. Overworld events and encounter prompts surface in the app from location or travel state.
**Plans**: 2 plans

Plans:
- [ ] 02-01: Location, route, and journey control surfaces
- [ ] 02-02: Travel blockers, timers, and event presentation

### Phase 3: Spellcraft and Study Surfaces
**Goal**: Players can use the signature magic and progression systems through the Mini App instead of command-only flows.
**Depends on**: Phase 2
**Requirements**: [MAGIC-01, MAGIC-02, MAGIC-03, CRAFT-01]
**UI hint**: yes
**Canonical refs**:
- `docs/MMGO_GDD.md`
- `docs/TECH_ARCHITECTURE.md`
- `lib/mmgo/ai.ex`
- `lib/mmgo/alchemy.ex`
- `lib/mmgo/academia.ex`
- `assets/js/hooks/spell-circle.js`
- `assets/js/hooks/study-desk.js`
- `assets/js/hooks/grimoire-shelf.js`
- `assets/js/hooks/base-interior.js`
**Success Criteria** (what must be TRUE):
  1. Player can inspect and manage spell library, grimoires, and loadouts.
  2. Player can submit spell compilation and receive clear status and result feedback.
  3. Player can manage Academy or Academia progress and see timed study outcomes.
  4. Player can start and inspect alchemy, crafting, and base jobs from the app.
**Plans**: 2 plans

Plans:
- [ ] 03-01: Spellbook, grimoire, and spell compilation flows
- [ ] 03-02: Study, crafting, alchemy, and base job screens

### Phase 4: Inventory, Trade, and Reputation
**Goal**: Players can understand their resources and participate in MMGO's economy without leaving the Mini App.
**Depends on**: Phase 3
**Requirements**: [ECON-01, ECON-02, ECON-03]
**UI hint**: yes
**Canonical refs**:
- `docs/MMGO_GDD.md`
- `lib/mmgo/market.ex`
- `lib/mmgo/black_market.ex`
- `lib/mmgo/reputation.ex`
- `lib/mmgo/notifications.ex`
- `assets/js/hooks/wanted-board.js`
- `assets/js/hooks/base-interior.js`
**Success Criteria** (what must be TRUE):
  1. Player can inspect inventory, storage, balances, and recent ledger movement from one coherent resource flow.
  2. Player can execute legal and black-market trades with tax, escrow, and risk clearly explained.
  3. Player can inspect reputation, crimes, fines, and sanction state and resolve eligible penalties.
**Plans**: 2 plans

Plans:
- [ ] 04-01: Inventory, storage, balance, and ledger surfaces
- [ ] 04-02: Market, black-market, reputation, and fine-resolution flows

### Phase 5: Parties, Notifications, and Social Structures
**Goal**: Players can coordinate with other players and receive meaningful asynchronous nudges back into the game.
**Depends on**: Phase 4
**Requirements**: [SOCIAL-01, SOCIAL-02]
**UI hint**: yes
**Canonical refs**:
- `docs/MMGO_GDD.md`
- `lib/mmgo/parties.ex`
- `lib/mmgo/organizations.ex`
- `lib/mmgo/clubs.ex`
- `lib/mmgo/notifications.ex`
- `lib/mmgo/telegram/commands.ex`
- `assets/js/hooks/guild-hall.js`
- `assets/js/hooks/expedition-log.js`
**Success Criteria** (what must be TRUE):
  1. Player can manage party membership and expedition rosters from the Mini App.
  2. Player can inspect organization roles and permissions relevant to travel or social gameplay.
  3. Async game events send Telegram notifications with working deep links back into the Mini App.
**Plans**: 2 plans

Plans:
- [ ] 05-01: Party, expedition roster, and organization management
- [ ] 05-02: Async notifications, invitations, and deep-link return flows

### Phase 6: Expeditions, Combat, and Duels
**Goal**: The main PvE and PvP loops are playable end-to-end from the player-facing interface.
**Depends on**: Phase 5
**Requirements**: [EXP-01, COMBAT-01]
**UI hint**: yes
**Canonical refs**:
- `docs/MMGO_GDD.md`
- `docs/TECH_ARCHITECTURE.md`
- `lib/mmgo/dungeons.ex`
- `lib/mmgo/pvp.ex`
- `lib/mmgo/parties.ex`
- `assets/js/hooks/duel-challenge.js`
- `assets/js/hooks/expedition-log.js`
**Success Criteria** (what must be TRUE):
  1. Player can launch expeditions or dungeon runs and review run state, supplies, and extraction outcome.
  2. Player can review combat or duel state, submitted actions, results, and wager settlement in the Mini App.
  3. PvE and PvP outcomes flow back into inventory, progression, and logs without manual repair.
**Plans**: 2 plans

Plans:
- [ ] 06-01: Expedition and dungeon run interface
- [ ] 06-02: Combat, duel, extraction, and outcome interface

### Phase 7: Live Operations and Federation Readiness
**Goal**: Operators can run MMGO safely in production and federation edges remain recoverable.
**Depends on**: Phase 6
**Requirements**: [OPS-01, FED-01]
**UI hint**: no
**Canonical refs**:
- `README.md`
- `docs/TECH_ARCHITECTURE.md`
- `lib/mmgo/operator.ex`
- `lib/mmgo/notifications/delivery_worker.ex`
- `lib/mmgo_web/controllers/federation_controller.ex`
- `lib/mmgo_web/controllers/health_controller.ex`
**Success Criteria** (what must be TRUE):
  1. Operators can inspect health and audit surfaces and recover stuck scheduled workflows safely.
  2. Federation manifest and migration paths remain operable with documented recovery steps.
  3. Live-service readiness is explicit for AI providers, jobs, and external integrations.
**Plans**: 2 plans

Plans:
- [ ] 07-01: Operator diagnostics and scheduled-workflow recovery
- [ ] 07-02: Federation and live-readiness hardening

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Telegram Access and Player Shell | 0/2 | Not started | - |
| 2. World Travel Loop | 0/2 | Not started | - |
| 3. Spellcraft and Study Surfaces | 0/2 | Not started | - |
| 4. Inventory, Trade, and Reputation | 0/2 | Not started | - |
| 5. Parties, Notifications, and Social Structures | 0/2 | Not started | - |
| 6. Expeditions, Combat, and Duels | 0/2 | Not started | - |
| 7. Live Operations and Federation Readiness | 0/2 | Not started | - |
