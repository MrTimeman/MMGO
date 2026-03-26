# MMGO Technical Architecture

Version 0.1

March 2026

## 1. Purpose

This document defines the technical direction for MMGO implementation.

It exists to lock in the major architectural decisions before development begins, so future work stays consistent with the game design document and with the agreed product priorities:

- AI-generated spells are the main product differentiator
- spell execution must still be fair, testable, and cheap to run
- the game server must remain authoritative over all persistent state
- the initial implementation should optimize for iteration speed, correctness, and operability rather than premature distribution

This is a living document. It should be updated when major technical assumptions change.

## 2. Core Technical Principles

### 2.1 Server-authoritative simulation

The backend is the source of truth for:

- player state
- inventory and storage
- currency and treasury
- travel and time progression
- party state
- combat state
- spell legality and resolution
- dungeon state

Clients submit intents. They do not decide outcomes.

Examples:

- "move to route X"
- "cast spell Y on target Z"
- "lock turn"
- "buy item N"

The server validates the action, resolves the simulation, persists the result, and then pushes updates to clients.

### 2.2 AI at authoring time, engine at runtime

MMGO does not use an LLM as the runtime authority for combat.

Instead, the magic system is split into two phases:

- `authoring`: AI interprets a newly created spell and compiles it into a structured deterministic spell spec
- `runtime`: the game engine resolves casts using the compiled spell spec plus current combat/environment state

This is the central technical decision of the project.

Consequences:

- spell creation can be expensive
- spell casting must be cheap
- PvP remains fair and replayable
- balance can be tested with deterministic simulations
- AI remains the system seller without being a runtime bottleneck

### 2.3 Deterministic execution with bounded variance

Compiled spells resolve deterministically from:

- compiled spell data
- combat state
- target state
- environment state
- a seeded RNG source for bounded variance

The same spell cast in materially identical conditions should produce materially identical outcomes, with only limited noise within predefined ranges.

### 2.4 Simulation-first architecture

The technical architecture should be optimized around domain simulation, not around generic CRUD application structure.

The most important systems are:

- combat state machines
- spell compilation and validation
- world time progression
- economic ledgering
- dungeon and travel state transitions

## 3. Technology Stack

## 3.1 Backend

Primary recommendation:

- `Elixir`
- `Phoenix`
- `Phoenix LiveView`

Reasons:

- excellent fit for concurrent game sessions, timers, and stateful workflows
- strong supervision and fault tolerance for AI jobs and user sessions
- fast iteration for complex domain logic
- low frontend complexity with LiveView
- good support for real-time updates and server-authoritative applications

### 3.2 Database and jobs

- `PostgreSQL` as the primary persistent datastore
- `Oban` for background jobs and scheduled work

Optional later additions:

- `Redis` only if a clear need appears for caching, distributed locks, or high-rate transient pub/sub beyond Phoenix defaults

### 3.3 Frontend

Primary recommendation:

- `Phoenix LiveView` for most of the Mini App UI
- minimal custom JavaScript for interactive pieces
- `canvas` or `PixiJS` only if the map requires richer rendering than plain DOM/SVG can reasonably provide

Reasons:

- reduced client complexity
- easier consistency with server state
- less frontend architecture burden for a backend-heavy project
- well suited for forms, inventories, travel views, combat logs, timers, and social interfaces

### 3.4 Telegram integration

Telegram integration should be handled inside the main Elixir system or as a closely related OTP application.

Responsibilities:

- authentication and account linking
- bot notifications
- turn reminders
- party invitations
- deep links into the Mini App
- out-of-band alerts for travel, crafting, and combat

### 3.5 AI providers

Initial target providers:

- `gemini-3-flash`
- `[g3f]-lite`

The codebase must not hardcode the game to a single provider API. Use an internal provider abstraction with versioned prompt contracts.

## 4. System Shape

MMGO should start as a modular monolith.

Do not start with microservices.

Reasons:

- the game is still discovering its domain model
- many systems are tightly coupled through simulation rules
- the operational overhead of services is not justified early
- Elixir already provides strong internal concurrency boundaries

Recommended top-level domains:

- `Accounts`
- `World`
- `Travel`
- `Combat`
- `Spells`
- `Inventory`
- `Economy`
- `Academy`
- `Dungeon`
- `Social`
- `Telegram`
- `AI`

Each domain should own:

- schemas and persistence logic
- command validation
- domain services
- pure rules modules where possible
- event emission hooks for logging and narration

## 5. Runtime Model

### 5.1 Time and long-running actions

Do not model the world as a constantly ticking global simulation.

Instead, use scheduled state transitions with timestamps.

Examples:

- travel starts at `t1`, ends at `t2`
- crafting starts at `t1`, completes at `t2`
- Academy enrollment starts at `t1`, graduates at `t2`
- migration freeze starts at `t1`, ends at `t2`

The system derives current state from persisted timestamps and runs jobs at important deadlines.

This is cheaper, simpler, and easier to audit than continuously ticking every actor.

### 5.2 Combat instances

Combat is modeled as an explicit state machine.

Suggested combat lifecycle:

- `forming`
- `active_turn`
- `locked`
- `resolving`
- `resolved`
- `finished`

Each combat stores:

- participants
- parties/sides
- shared HP pools
- actor-level statuses
- environment state
- turn timer configuration
- submitted actions
- event history
- RNG seed material
- final narrative output per turn

### 5.3 Deterministic RNG

Runtime variance must use seeded pseudorandomness.

This supports:

- reproducible debugging
- replayability
- fairness auditing
- stable tests

Suggested inputs for seed derivation:

- combat instance id
- turn number
- action order key
- spell id or action id

## 6. AI Architecture

## 6.1 AI roles

AI should be split into distinct responsibilities.

### 6.1.1 Spell compiler

Used when a player creates a new spell.

Input:

- school
- base spell
- incantation words
- caster progression data
- allowed engine schema
- allowed primitives, tags, and forms

Output:

- structured compiled spell spec
- narrative description of the created spell
- warnings, risks, or instability markers if applicable

### 6.1.2 Storyteller

Used after combat resolution or major world events.

Input:

- fully resolved engine events
- participants
- environment changes
- spell tags and names

Output:

- vivid player-facing narration

The storyteller is not authoritative. It does not decide mechanics.

### 6.1.3 Rare adjudicator (optional)

This is a fallback tool, not a normal runtime dependency.

It may be used later for unresolved edge cases or for offline content refinement, but the initial implementation should avoid requiring it during normal play.

## 6.2 Spell compilation pipeline

Recommended pipeline:

1. normalize player input
2. validate incantation format and basic constraints
3. collect authoring context
4. call the spell compiler model
5. parse schema-constrained JSON
6. validate against engine rules
7. clamp or reject invalid fields
8. assign budgets, tags, and deterministic runtime values
9. persist the compiled spell
10. add the spell to the player's library if accepted

### 6.3 Runtime casting pipeline

Recommended runtime pipeline:

1. player selects a compiled spell
2. engine checks cooldown, fatigue, legality, and targeting
3. engine resolves interactions against environment, target states, and other actions
4. engine applies deterministic effects and bounded variance
5. engine persists resolved turn events
6. storyteller receives the resolved turn and generates narration

No live LLM interpretation is required for normal spell execution.

## 6.4 Provider abstraction and observability

Every AI call must persist enough information for debugging and balancing.

Required stored metadata:

- provider name
- model name
- prompt template version
- normalized input payload
- raw model output
- parsed output
- validation result
- final accepted result
- latency
- token usage or cost if available

This is mandatory for spell compiler calls.

## 7. Spell Runtime Model

Compiled spells should be engine-native data, not loose AI text.

Each spell should contain structured fields similar to the following categories:

- `identity`
- `lineage`
- `requirements`
- `targeting`
- `delivery_form`
- `base_effects`
- `environment_effects`
- `interaction_rules`
- `failure_profile`
- `fatigue_cost`
- `cooldown`
- `narrative_tags`

The important rule is that spells are compiled against categories, tags, and primitives, not against an infinite set of future spell ids.

For example, a spell should define behavior in terms of:

- elemental tags like `fire`, `water`, `earth`, `air`
- form tags like `projectile`, `wall`, `zone`, `beam`, `link`
- interaction tags like `volatile`, `shielding`, `binding`, `healing`
- environment tags like `dry`, `wet`, `stone`, `wood`, `confined`
- target states like `burning`, `frozen`, `shielded`, `silenced`

This prevents combinatorial explosion and keeps runtime resolution tractable.

## 8. Primitives, Tags, and Forms

The engine should separate three layers of spell vocabulary.

### 8.1 State primitives

These are actual engine effects with deterministic meaning.

Examples:

- `impact`
- `burning`
- `frozen`
- `trapped`
- `blinded`
- `silenced`
- `staggered`
- `channeling`
- `shielded`
- `regenerating`
- `empowered`
- `exposed`

This set should expand carefully over time.

### 8.2 Tags

Tags are descriptive traits used for interaction logic and narration.

Examples:

- elemental tags: `fire`, `water`, `earth`, `air`, `life`, `death`, `chaos`, `order`
- behavior tags: `projectile`, `piercing`, `volatile`, `ritual`, `lingering`, `support`
- control tags: `binding`, `knockback`, `warding`, `concealing`

Tags are not direct effects by themselves.

### 8.3 Delivery forms

Delivery form describes how a spell enters the battlefield.

Examples:

- `single_target`
- `beam`
- `cone`
- `sphere`
- `wall`
- `zone`
- `self`
- `link`
- `delayed_trigger`

This keeps runtime resolution clearer than trying to encode everything inside state primitives.

## 9. Data and Persistence Principles

### 9.1 PostgreSQL as source of truth

PostgreSQL is the authoritative persistent store.

Use it for:

- player progression
- inventories and bases
- spell libraries and grimoires
- combat records
- world state references
- economy ledger
- Academy state
- party/social state

### 9.2 Append-only ledgers and logs

Two systems must be append-only from the start:

- currency ledger
- combat event log

Reasons:

- auditing
- dispute resolution
- exploit investigation
- balancing and analytics
- replayability
- AI debugging

### 9.3 Snapshots plus history

For expensive domains such as combat, use both:

- current-state snapshots for fast reads
- append-only events for history and replay

Do not require full event sourcing for the entire product.

## 10. Testing Strategy

Testing must be a major investment area.

If MMGO succeeds, it will be because the deterministic engine is trustworthy even while the AI layer remains creative.

### 10.1 Test language

Tests should primarily be written in `Elixir`, not in `C`.

Reasons:

- `ExUnit` is already fast and parallel
- engine logic is easier to test in the same language as implementation
- property tests are more important than raw micro-benchmark speed
- maintenance cost stays low

### 10.2 Test layers

Recommended test mix:

- unit tests for pure combat and spell runtime logic
- property tests for invariants
- integration tests for DB workflows and command handling
- fixture-based AI contract tests using frozen responses
- scenario tests for representative combat interactions
- simulation tests for large batches of generated fights

### 10.3 Priority invariants

Examples of invariants that should always hold:

- shared HP never becomes invalid
- statuses only transition through legal rules
- consumed defensive effects cannot trigger twice
- cooldown and fatigue costs are consistent with compiled spell data
- spells never emit unsupported primitives
- turn resolution order is stable
- same inputs and same seed produce same outputs
- variance stays within configured bounds
- ledger balances reconcile exactly

### 10.4 AI testing

Do not depend on live model calls in normal test suites.

Instead:

- freeze representative model outputs as fixtures
- validate parsing and schema checking against fixtures
- run optional manual or scheduled live-provider checks separately

## 11. Security and Abuse Resistance

### 11.1 Spell authoring input

Even with six Latin-word incantations, treat user input as hostile.

Required protections:

- normalization
- length limits
- character filtering
- profanity/abuse screening where needed
- prompt isolation so user text cannot alter system instructions

Optional future additions:

- Latin dictionary assistance
- typo correction suggestions
- language plausibility checks

Unknown words may still be allowed, but the compiler pipeline must handle them safely.

### 11.2 Runtime safety

The engine must reject any compiled output that:

- references unsupported primitives
- exceeds allowed numeric budgets
- creates impossible targeting
- violates school restrictions
- breaks known combat invariants

Never trust the LLM output directly.

## 12. Operations and Observability

Operational visibility is required early.

Minimum observability domains:

- AI call latency and failure rate
- spell compilation acceptance/rejection rates
- combat resolution time per turn
- narration generation time
- queue depth and job retries
- economy reconciliation checks
- player action rates and error rates

Structured logs should exist for:

- spell creation attempts
- spell compilation failures
- combat turn resolution
- ledger transfers
- migration events
- unusual runtime validation failures

## 13. Delivery Plan

The first implementation should focus on a narrow vertical slice.

Recommended first playable scope:

- one realm
- one city
- one Tower
- one shallow dungeon
- Telegram auth/linking
- player creation
- inventory and storage basics
- graph-based travel with compressed time
- party formation basics
- deterministic combat engine
- spell creation pipeline with compiled spells
- deterministic spell casting in combat
- storyteller narration layer
- loot, death-loss, and return flow

Explicitly defer:

- inter-realm federation
- advanced Academy authorship systems
- complex black market enforcement
- deep dynamic dungeon ecosystem behavior
- massive battle scaling

## 14. Open Questions

The following technical design questions remain open and should be resolved in future documents:

- final compiled spell schema
- exact primitive/tag/form taxonomy
- turn timer scaling rules
- map rendering approach inside the Mini App
- exact LiveView vs custom JS boundary
- economic ledger schema
- combat snapshot schema
- provider failover behavior for spell compilation and narration
- dictionary/normalization rules for incantation input

## 15. Current Decision Summary

The current agreed technical direction is:

- `Elixir` + `Phoenix`
- `Phoenix LiveView` as the default web UI approach
- `PostgreSQL` as source of truth
- `Oban` for background jobs
- modular monolith first
- AI used for spell compilation and narration, not normal runtime authority
- deterministic compiled spells with bounded variance
- append-only combat logs and money ledger
- heavy automated testing, especially pure engine, property, and simulation tests

This document should serve as the foundation for the next layer of technical documentation.
