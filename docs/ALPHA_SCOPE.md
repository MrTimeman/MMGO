# MMGO Releasable Alpha Scope

Version `0.1.0-alpha.8` is the current operator-deployable alpha. The GDD remains the long-term product contract; this document defines the release boundary and the evidence required to call one build releasable.

## Included

- Verified Telegram Mini App identity and account-owned LiveView sessions.
- Canonical realm, map, compressed calendar, travel, events, scavenging, survival, inventory, and bases.
- Spell library and immutable grimoires, bounded spell compilation, timed simultaneous combat, duels, parties, and dungeon expeditions.
- Legal market/NPC economy, realm-configurable legal tax, black-market detection/fines/default deadlines, charity, tuition, and closed ledgers.
- Paid city bases plus coin/material/time-gated custom construction.
- Crafting and AI-interpreted alchemy constrained by immutable item primitives, with durable Oban jobs and deterministic fallbacks.
- Academy, Academia, clubs, careers, notifications, realm migration, organisations, treasuries, governance, diplomacy, and map overlays.
- Semantic audio cues, operator reports, database readiness/liveness endpoints, release scripts, and container packaging.

## Alpha acceptance gate

A release candidate must pass all of the following from a clean checkout:

```bash
mix precommit
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

The deployed release must then:

1. run `bin/migrate` successfully against a backed-up PostgreSQL database;
2. return HTTP 200 from `/livez` and `/healthz`;
3. accept a signed Telegram Mini App login;
4. start one real journey and one durable background job;
5. preserve audit rows for economy and AI operations.

## Deliberate alpha limits

- The repository ships no production credentials, external federation peer, or licensed soundtrack recordings.
- The canonical seed is starter content, not a promise of launch-scale content volume or balance.
- Provider outages use bounded deterministic fallback behavior; operators must monitor failed AI and Telegram requests.
- Some history-oriented screens retain a manual refresh control even though authoritative state is durable.
- Load, soak, disaster-recovery, and multi-node federation exercises are operator gates before a public beta.

Narrative choices still marked TBD in the GDD are content/balance decisions, not missing server authority. Any mechanic added after this alpha must retain the same ownership, transaction, AI-boundary, and test requirements.
