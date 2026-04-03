# Requirements: MMGO

**Defined:** 2026-04-03
**Core Value:** Players can inhabit a persistent magical world where creative spell expression, meaningful trade-offs, and social interdependence feel deeper than a typical chat game while remaining fair, deterministic, and operable.

## v1 Requirements

### Access

- [ ] **ACCESS-01**: Player can open the MMGO Mini App from Telegram and land in a linked account session.
- [ ] **ACCESS-02**: New Telegram player can provision an account and starter character without manual database intervention.
- [ ] **ACCESS-03**: Returning player can restore current character state and pending timers after refresh or deep link entry.
- [ ] **ACCESS-04**: Player sees actionable recovery states when identity, session bootstrap, or account linking fails.

### World

- [ ] **WORLD-01**: Player can inspect current location, destinations, and route travel time in the Mini App.
- [ ] **WORLD-02**: Player can start a journey and later see the updated travel state without keeping the app open.
- [ ] **WORLD-03**: Player can inspect travel blockers such as food, carry capacity, or route availability before committing.
- [ ] **WORLD-04**: Player can review location-triggered text events or overworld encounter prompts in the Mini App.

### Spellcraft and Progression

- [ ] **MAGIC-01**: Player can inspect spell library, grimoires, and prepared loadouts in the Mini App.
- [ ] **MAGIC-02**: Player can submit spell compilation and receive clear AI status plus deterministic result feedback.
- [ ] **MAGIC-03**: Player can manage Academy or Academia study progress, tracks, and timed completions from the UI.
- [ ] **CRAFT-01**: Player can start and review alchemy, crafting, or base jobs with timer and outcome feedback.

### Economy

- [ ] **ECON-01**: Player can inspect inventory, storage, balances, and recent ledger activity from the Mini App.
- [ ] **ECON-02**: Player can create or fulfill legal and black-market trades with clear tax, escrow, and risk feedback.
- [ ] **ECON-03**: Player can inspect reputation, crimes, fines, and sanction state and resolve eligible penalties.

### Social and Async

- [ ] **SOCIAL-01**: Player can manage party membership, expedition roster, and organization role visibility relevant to gameplay permissions.
- [ ] **SOCIAL-02**: Player receives Telegram notifications and Mini App deep links for async completions, invitations, and urgent game events.

### Expeditions, Combat, and Operations

- [ ] **EXP-01**: Player can launch an expedition or dungeon run and review run state, supplies, and extraction outcome.
- [ ] **COMBAT-01**: Player can review combat or duel state, submitted actions, outcomes, and wager settlement in the Mini App.
- [ ] **OPS-01**: Operator can inspect health and audit surfaces and recover scheduled gameplay workflows without direct database edits.
- [ ] **FED-01**: Federation manifest and migration flows remain operable with a documented operator path.

## v2 Requirements

### Audio and Atmosphere

- **AUDIO-01**: Mini App resolves semantic music cues into adaptive or curated audio playback.
- **AUDIO-02**: Major world events can trigger iconic presentation cues without breaking gameplay flow.

### Expanded Social Layer

- **SOCIAL-03**: Players can discover clubs, professors, and organizations through richer in-app social discovery flows.
- **FED-02**: Players can browse inter-realm discovery and exchange state directly from the Mini App.

### Admin and Analytics

- **OPS-02**: Operators have a dedicated authenticated dashboard for recovery tools and service diagnostics.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Native iOS and Android apps | Telegram Mini App is the intended launch surface |
| Microservice split of gameplay domains | Modular monolith is a better fit while the simulation model is still moving |
| Runtime LLM combat authority | Deterministic runtime resolution is required for fairness and cost control |
| Pay-to-win monetization | Violates documented game pillars and donation-only model |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ACCESS-01 | Phase 1 | Pending |
| ACCESS-02 | Phase 1 | Pending |
| ACCESS-03 | Phase 1 | Pending |
| ACCESS-04 | Phase 1 | Pending |
| WORLD-01 | Phase 2 | Pending |
| WORLD-02 | Phase 2 | Pending |
| WORLD-03 | Phase 2 | Pending |
| WORLD-04 | Phase 2 | Pending |
| MAGIC-01 | Phase 3 | Pending |
| MAGIC-02 | Phase 3 | Pending |
| MAGIC-03 | Phase 3 | Pending |
| CRAFT-01 | Phase 3 | Pending |
| ECON-01 | Phase 4 | Pending |
| ECON-02 | Phase 4 | Pending |
| ECON-03 | Phase 4 | Pending |
| SOCIAL-01 | Phase 5 | Pending |
| SOCIAL-02 | Phase 5 | Pending |
| EXP-01 | Phase 6 | Pending |
| COMBAT-01 | Phase 6 | Pending |
| OPS-01 | Phase 7 | Pending |
| FED-01 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after initial definition*
