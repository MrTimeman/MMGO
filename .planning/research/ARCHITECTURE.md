# Architecture Research: GDD Completion Order

## Boundary model

```text
Telegram Mini App / browser session
  -> authenticated LiveView live_session + current_scope
  -> thin gameplay facade / page-specific read model
  -> domain context command/query API
  -> Ecto transaction + persisted state + Oban/PubSub side effect
  -> LiveView refresh or pushed semantic event
```

- Extend `MMGO.Play` into an account-neutral gameplay facade where it already fits, and introduce similarly narrow read/command facades only when a page family needs a different aggregate. Do not expose raw Repo calls to LiveViews.
- Store the active character in a current scope/session assign created by verified Mini App login. Every facade command derives actor identity from that scope rather than accepting arbitrary character IDs from the browser.
- Keep generic, reusable domain rules in contexts (`MMGO.Combat`, `MMGO.Parties`, `MMGO.Dungeons`, `MMGO.Organizations`); page facades compose their read models and translate tagged errors into UI states.

## Cross-cutting integration points

- Router: create public Mini App entry/auth endpoints plus an authenticated `live_session`; move game pages into it and pass `current_scope` to `Layouts.app`.
- Accounts/Telegram: validate `initData`, provision/refresh identity, and rotate/clear a signed game session safely.
- Map/activity: a location-state facade should return canonical clock, location, active journey, allowed actions, nearby actors/events, and available destinations.
- Realtime: contexts publish only after successful transactions; facades subscribe LiveViews to character, combat, party, and realm topics.
- Jobs: scheduled tasks hold durable identifiers/timestamps and are idempotent under transactions; UI reads persisted status, never an in-memory timer.

## Combat architecture

1. Persist turn deadline and action declarations.
2. Deterministically validate available spells/tools, ownership, location, targets, fatigue, cooldowns, and shared HP.
3. Build a bounded intermediate result for caster actions.
4. Invoke `MMGO.AI` through an orchestration service; validate/normalize the structured reply against engine constraints.
5. Persist effects, narration, next deadline, and settlement in one durable flow; publish after commit.

The local bot duel becomes a test fixture/quick path, not the architecture for multiplayer combat. Party, dungeon, and overworld combat should use the same engine with mode-specific stakes.

## Phase-safe build order

1. Secure identity and current scope, then migrate real pages from demo session lookup.
2. Build location/activity read models and replace map/hub demo data.
3. Wire real spellbook/grimoire, then add combat deadlines/AI/tool actions and explicit UI flows.
4. Wire inventory/economy/base/alchemy/crafting pages through their contexts.
5. Wire party/overworld interactions, then an end-to-end dungeon expedition.
6. Finish Academy/Academia and repair state-machine defects.
7. Surface notification/federation, then organisations in v1 -> v4 dependency order.
8. Add semantic audio, observability, accessibility, and final GDD audit after game loops exist.

## Verification architecture

- Domain tests protect command invariants and state transitions.
- LiveView tests mount through real scoped sessions, operate stable IDs/forms, and assert observable results.
- Oban worker tests call workers/explicit timestamps rather than sleeping.
- End-to-end focused suites exercise one player-owned vertical loop at a time, then `mix precommit` validates the whole tree.
