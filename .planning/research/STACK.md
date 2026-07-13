# Stack Research: Full-GDD MMGO Delivery

## Baseline to preserve

- Keep the existing Phoenix 1.8 / LiveView / Ecto / PostgreSQL / Oban architecture documented in `.planning/codebase/STACK.md`.
- Reuse `MMGO.AI`, its provider behaviour, Req-based providers, prompt modules, and the mock provider rather than introducing a second LLM client.
- Reuse signed Phoenix cookie sessions, LiveView `on_mount`, Ecto transactions, Oban scheduling, Phoenix PubSub, bundled JS hooks, Tailwind v4, and the existing test stack.
- Do not add an SPA, a separate API gateway, client-side state store, polling framework, or a custom job runner. They would duplicate framework capabilities already in the repository.

## Telegram Mini App identity

- Add a small server-side Telegram Web App `initData` verifier using OTP `:crypto`, `URI.decode_query/1`, constant-time comparison, and an explicit max-age check. No third-party authentication dependency is required.
- The verifier belongs in an account/auth boundary (for example `MMGO.Telegram.WebAppAuth`), not in a controller or LiveView. It returns only normalized, validated Telegram user attributes.
- Reuse `MMGO.Accounts.provision_from_telegram/1` to create or refresh the account, identity, and character after verification.
- Set only server-derived `account_id` and `character_id` session values; mount game pages through an authenticated `live_session` that assigns a `current_scope` / current character.
- Preserve a clearly isolated demo-login route for development and existing deterministic tests; it must never be the production default or share state between real players.

## Runtime combat AI

- Add a provider-neutral combat orchestration boundary above the deterministic engine. It should create structured requests from the persisted combat state, call `MMGO.AI`, validate the response against allowed primitives/ranges, and persist an auditable result.
- Keep tool actions deterministic and allow the engine to reject AI output that exceeds its state vocabulary, actor permissions, costs, targets, or ranges.
- Extend the existing mock provider with fixed combat-resolution and narration fixtures so all tests run without external credentials.
- Do not call an LLM from a LiveView and do not make an LLM responsible for locks, win conditions, escrow, or database writes.

## Timers and real-time updates

- Add persisted turn deadlines and an Oban worker keyed by combat and turn. Schedule it when a turn opens; lock the combat transaction before resolving an expired turn so duplicate jobs are harmless.
- Use Phoenix PubSub to refresh participants, spectators, and map/party views after a committed command. LiveViews should subscribe to narrow character, party, combat, or realm topics after `connected?/1`.
- Avoid `Process.sleep/1`, in-memory timer state, and client authority. Tests should invoke the worker or use explicit timestamps.

## Semantic audio

- Model gameplay audio as semantic state/cue events (for example `travel.safe`, `dungeon.explore.upper`, `combat.boss`) emitted by the server facade and handled by one bundled JS hook.
- Keep cue selection data-driven and allow curated assets to override ambient state. The first implementation should accept local/empty asset maps gracefully, with no remote audio provider or copyrighted recordings committed.
- Do not use inline scripts or external layout script tags; register the hook in `assets/js/hooks/index.js` and push events from LiveViews.

## Configuration and security

- Make production Telegram webhook authorization fail closed when the webhook endpoint is enabled; retain an explicit test/development exception only if necessary.
- Keep bot tokens, AI keys, federation tokens, and audio asset URLs in runtime config. Never put them in fixtures, map docs, or client assigns.
- Test provider choice explicitly. `DEEPSEEK_API_KEY` currently changes runtime selection, so integration tests should use the mock provider or unset the variable deliberately.

## Recommended additions versus non-additions

| Need | Use | Avoid |
| --- | --- | --- |
| Mini App verification | OTP crypto + existing Accounts | OAuth/password stack |
| Combat deadline | Ecto migration + Oban | process timers / polling loops |
| AI gameplay | existing `MMGO.AI` behaviour | direct Req calls from UI |
| Live updates | Phoenix PubSub + LiveView | a new websocket service |
| Audio | semantic events + bundled hook | remote playback SDK dependency |
