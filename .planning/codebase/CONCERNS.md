# Current Concerns

## Alpha operations

- Production credentials, public Telegram webhook registration, a PostgreSQL service, and federation identity are external deployment inputs. Startup now fails closed when required values are absent.
- The release has readiness/liveness endpoints and a Docker health check, but public beta still requires load/soak testing, backup restoration practice, and a multi-node/federation exercise.
- Operators should alert on Oban retries, failed Telegram delivery records, failed AI audit rows, and economy reconciliation anomalies.

## Product and content

- The canonical seed provides a complete playable topology, not launch-scale content volume or final economic balance.
- Licensed recordings are intentionally absent. The semantic cue system is implemented; legally usable recordings remain an operations/content decision.
- Some history-oriented LiveViews retain manual refresh controls. Authoritative state remains durable and gameplay-critical workers are idempotent.

## Safety invariants to preserve

- All browser commands derive the actor from `current_scope`; never accept character or realm authority from client params.
- Money, inventory, escrow, ownership, and job transitions remain transactional and server-priced.
- AI providers may compose only within fixed schemas/primitives. Deterministic snapshots and fallbacks remain the mechanical authority.
- Realm migrations, Academy schedules, black-market deadlines, base builds, and production jobs must stay retry-safe under Oban.

## Verification

The release gate is `mix precommit`, followed by a production asset/release build. Deployment acceptance is documented in `docs/ALPHA_SCOPE.md` and `docs/DEPLOYMENT.md`.
