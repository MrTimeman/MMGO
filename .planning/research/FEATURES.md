# Feature Research: Full-GDD Player Product

## Delivery interpretation

The GDD is a connected-game contract, not a list of static screens. A requirement is complete only when a player with an owned character can reach its location, submit an authoritative action, observe persisted consequences, and recover from errors or time passage in the UI.

## Table-stakes player loops

### Identity and game entry

- Telegram Mini App identity validation provisions or reuses exactly one account-owned character and opens a scoped game session.
- A player can continue their own state after refresh; a forged session/request cannot operate another character.
- A development demo entry remains isolated for local tests and visual development.

### World, travel, and survival

- The map shows canonical compressed time, live journeys, nearby players/events where authorized, realm data, and semantic audio state.
- Players can travel routes with terrain/path costs, carry food, scavenge, encounter text events, suffer gradual starvation/overload consequences, and arrive through server time.
- Location gates expose only activities available at city, base, Tower, wilderness, or dungeon locations.

### Magic and combat

- Casters select a real owned base spell/grimoire and enter a 1–6 word incantation; compilation and library progression use persisted data.
- Tool users select owned/equipped deterministic items, actions, and targets.
- Simultaneous turns have persisted deadlines, lock actions, resolve absent actions as waits, respect magic zones, settle wagers/loot, and stream a readable narrative.
- Runtime AI enriches bounded spell effects and narration without bypassing engine validation; mock mode is deterministic.

### Inventory, economy, bases, and making

- Players see real carry capacity, equipment, grimoires, materials, currency, and storage; actions update the authoritative inventory.
- Players can transact through legal market/NPC/black-market flows, observe taxes/treasury effects, and use their own base for storage and timed crafting/alchemy jobs.
- Crafting, brewing, property/base construction, and resource outcomes have completion/recovery UI rather than only workers.

### Social expedition game

- Players can find/interact with others, invite/manage parties, choose loot rules, and see party readiness/supplies.
- A party can enter, navigate, act, scavenge, fight, extract, ascend, or suffer a dungeon defeat through a complete browser loop.
- Dungeon effects feed inventory, XP, reputation, survival, and return-to-world state.

### Academy and careers

- Academy terms follow an ordered schedule with enrollment, lectures, midterms, finals, club events, GPA/ranking, and graduation outcomes.
- Player-facing academy, clubs, research, advisor, professor, and thesis-defense screens use real contexts.
- Thesis panel votes and worker resolution form one valid state machine with regression coverage.

### Realms, organisations, ambience

- Players can view notifications, browse realms, initiate/migrate according to federation rules, and observe their own realm state.
- Organisation v1 has real web UI; v2 adds treasury/assets/shares; v3 enforces composable governance/votes; v4 exposes territory, filters, and diplomacy from real data.
- Semantic audio state is driven by gameplay context, with major event cues overriding ambience.

## Dependencies and order

1. Identity/session ownership gates every player command.
2. Shared location/read models make map, hubs, crafting, Academy, and social pages safe to wire.
3. Spellbook/combat needs inventory/grimoires and location gates; timer/AI needs persisted combat state.
4. Parties need identity and world state; dungeon needs parties, combat, survival, inventory, and rewards.
5. Organisation governance depends on accounts, economy, ownership, and map entities.

## GDD divergence to resolve

`README.md` currently frames spell AI as author-time compilation with deterministic combat, while GDD §2.3 and §3.4 require cast-time structured AI/orchestration/narration. The delivery model is hybrid: deterministic constraints and state mutation remain authoritative, while provider-backed AI selects only validated structured effects/narration inside those bounds.

## Explicit non-feature constraints

- Do not add pay-to-win, premium currency, or real-money advantages.
- Do not treat a static demo screen as completed functionality.
- Do not require live Telegram or AI credentials to run the test suite.
- Do not make licensed audio recordings part of source control; provide the cue system and asset contract.
