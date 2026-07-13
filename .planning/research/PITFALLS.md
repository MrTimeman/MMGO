# Pitfalls Research: Full-GDD MMGO Delivery

## Security and ownership

- Never accept a character, account, opponent, party, or realm ID from a browser action as authority. Derive the actor from the verified session and validate relationships inside contexts.
- Telegram Web App `initData` must be verified server-side, checked for freshness, and compared in constant time. Parsing a user field without the data-check hash would allow account takeover.
- `MMGO.Telegram.authorized_webhook_secret?/1` currently accepts absent secrets. Make production behavior explicit/fail-closed before treating the bot endpoint as deployed.

## Persistence and concurrency

- Combat timeout jobs, journey completion, crafting, and defence workers may race with player actions. Persist deadline/status, lock the relevant row/aggregate, and make every worker idempotent.
- Do not use process-local timers, assigns, or `Process.sleep/1` for game truth. They fail on reconnect, restart, multi-node deployment, and test concurrency.
- Publish PubSub updates only after successful transactions so a LiveView never displays rolled-back state.

## AI safety and resilience

- AI output must never mint arbitrary state IDs, alter money/HP outside engine limits, select unauthorized targets, or decide database ownership. Validate the schema and fall back to bounded deterministic behavior on provider failure.
- Keep provider selection deterministic in tests. Runtime credentials such as `DEEPSEEK_API_KEY` can change behavior unexpectedly.
- The GDD/README conflict about cast-time AI must be resolved in docs and tests; otherwise future code may silently reintroduce two incompatible combat models.

## Web integration

- Replacing demo assigns screen-by-screen without a common scoped session will create inconsistent identity and authorization checks. Establish the auth/current scope boundary first.
- A visually polished LiveView is not evidence of a player loop. Every screen needs a context-backed command, an error path, a refresh path, and a LiveView integration test.
- Preserve existing `MMGO.Play` composition rather than directly calling half a dozen contexts from templates/callbacks.

## Domain-specific gaps

- Gradual starvation, world events, nearby players, party operations, dungeon browser flow, academy scheduling, and organisations v2–v4 are not just presentation tasks; identify missing persistence/state transitions before wiring UI.
- The thesis defence vote path needs a state-machine fix and test before exposing it as a real player action.
- Organisation ownership/governance needs generic enforcement, not ad hoc role checks in individual screens; shares and treasury permission rules should be transactional.

## Scope and operations

- A literal full GDD is too broad for one cosmetic pass. Use vertical phases with verifiable player outcomes and re-read the roadmap after each phase.
- Keep production deployment, real Telegram bot configuration, federation peers, and licensed audio assets as environment/content concerns; code must remain locally runnable with mocks.
- There is no checked-in CI pipeline. Keep focused test gates per phase and repair existing stale LiveView expectations as their real screens are wired.
