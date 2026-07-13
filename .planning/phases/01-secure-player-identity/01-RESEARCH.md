# Phase 1: Secure Player Identity — Research

## Summary

MMGO already persists a one-to-one `Account` ↔ `TelegramIdentity` and a default realm character through `MMGO.Accounts.provision_from_telegram/1`. The missing layer is not another account model: it is server-side Mini App `initData` validation, a scoped Phoenix browser session, and one LiveView authorization mount point. The phase should reuse OTP crypto, Phoenix sessions, and the existing account transaction.

## Existing architecture and reusable seams

- `lib/mmgo/accounts.ex` normalizes Telegram user fields and atomically provisions/refreshes an account, identity, and default-realm character.
- `lib/mmgo/accounts/telegram_identity.ex` has the unique Telegram user/account relationships needed to prevent duplicate ownership.
- `lib/mmgo_web/endpoint.ex` already gives HTTP and LiveView sockets the same signed cookie session.
- `lib/mmgo_web/router.ex` currently exposes all game LiveViews publicly and relies on `demo_character_id`; it needs a game `live_session` with an `on_mount` guard.
- `lib/mmgo_web/controllers/play_demo_controller.ex` and `play_api_controller.ex` demonstrate session writes but must be made explicitly demo/local rather than production identity.
- `config/test.exs` already provides `MMGO.Telegram` values `bot_token: "test-bot-token"` and `webhook_secret: "test-webhook-secret"`, allowing deterministic signature and webhook tests.

## Telegram Mini App validation contract

Telegram’s official Mini App guide requires sending `Telegram.WebApp.initData` as its raw query string to the backend. Build `data_check_string` from all received key/value pairs except `hash`, sorted alphabetically and joined with `"\n"`; calculate `secret_key = HMAC_SHA256(bot_token, "WebAppData")`, then compare the received `hash` to the hex HMAC of the data-check string using that secret. Validate `auth_date` freshness before trusting the JSON-encoded `user` field.

- Implement it in a dedicated `MMGO.Telegram.WebAppAuth` module using `URI.decode_query/1`, `Jason.decode/1`, `:crypto.mac/4`, and `Plug.Crypto.secure_compare/2`.
- Return tagged failures: `:missing_init_data`, `:missing_bot_token`, `:missing_hash`, `:invalid_hash`, `:missing_auth_date`, `:expired_auth_date`, `:missing_user`, and `:invalid_user`; never log raw init data.
- Read `max_auth_age_seconds` from `MMGO.Telegram` config with a conservative default such as 300 seconds. Tests pass an explicit fixed `now`/max age instead of sleeping.
- Accept only the known normalized user fields that `Accounts.provision_from_telegram/1` already handles; ignore unrelated query fields rather than atomizing them.

## Recommended web shape

1. Add a browser controller endpoint such as `POST /auth/telegram` that accepts a single `init_data` form parameter, invokes `WebAppAuth.authenticate/1`, calls Accounts provisioning, puts `:current_account_id` and `:current_character_id` in the signed session, and redirects to `/map`.
2. Add a small `MMGOWeb.GameAuth` module exposing `on_mount/4` plus `current_scope/1`. It loads the character through a new account-scoped query, checks account/character active state, assigns `%{account: ..., character: ...}` as `:current_scope`, or redirects unauthenticated guests to `/play`.
3. Create public `GameEntryLive` at `/play` with an external JS hook that sends `Telegram.WebApp.initData` via its ordinary CSRF-protected form/action or a colocated hook. Normal browsers get the contract’s safe explanation; local/test demo entry is exposed only when `config_env() in [:dev, :test]` or a dedicated explicit config flag is true.
4. Move map and all game routes into `live_session :game, on_mount: [{MMGOWeb.GameAuth, :require_character}]`; retain public entry/home and dev-only tools outside it.
5. Change core pages from direct `demo_character_id` reads to `current_scope.character`. Where a larger page cannot be fully migrated in Phase 1, it must still be inside the scope guard and must not execute a command through an unowned ID.
6. Tighten `MMGO.Telegram.authorized_webhook_secret?/1`: in production, missing config returns false; in test/dev only an explicit `allow_insecure_webhook?` configuration may permit a missing secret.

## Browser implementation choices

- Do not add a raw external Telegram script tag to a HEEx template because project rules prohibit external layout/template scripts. The official Mini App script can be loaded through the supported bundled asset path if the project chooses it; the initial phase can also read the globally injected `window.Telegram?.WebApp` object when Telegram supplies it.
- Register exactly one external `TelegramAuth` hook in `assets/js/hooks/` and `assets/js/hooks/index.js`; it reads `window.Telegram?.WebApp?.initData`, calls `ready()` if available, places the raw string into the hidden form field, and submits once. The server still treats it as untrusted until verified.
- Use a regular `<.form>`/`<.input type="hidden">` with `id="telegram-auth-form"`, a hook root id, and server-rendered fallback/error content. Do not expose bot token/client secret in JavaScript.
- Follow `AGENTS.md` rather than the older design-pass rule that prohibited `Layouts.app`: authenticated LiveViews must pass `current_scope` to `Layouts.app`.

## Test strategy

- Unit tests for WebAppAuth build real expected HMAC strings using the fixed test bot token; cover valid, reordered, tampered, missing, expired, malformed user, and missing token inputs.
- Accounts tests prove a valid Mini App identity reuses the same account/character and cannot create duplicates.
- Controller tests assert session contains only server-derived IDs and invalid init data never creates/changes records.
- LiveView tests assert `/map`, `/spellbook`, and other protected routes redirect without scope; a scoped connection mounts; swapping a session/query ID cannot select another character.
- Webhook tests assert production-style missing secret fails and explicit test/dev configuration remains controllable.

## Validation Architecture

Existing ExUnit, SQL Sandbox, ConnCase, and LiveViewTest infrastructure covers this phase. Add focused tests before or alongside each implementation task; use no watch mode or sleeps.

| Requirement | Automated evidence |
|-------------|--------------------|
| AUTH-01 | `test/mmgo/telegram/web_app_auth_test.exs` validates HMAC, auth date, and user parsing |
| AUTH-02 | controller + LiveView tests establish scope and reject cross-character access |
| AUTH-03 | controller tests retain explicit local demo behavior without granting production fallback |
| AUTH-04 | Telegram/Webhook controller tests cover missing-secret production behavior and test config |

## Risks and mitigations

- Query decoding can transform values incorrectly if the raw init-data string is reconstructed. Preserve values from `URI.decode_query/1` and create the canonical sorted string exactly once.
- `auth_date` uses Unix seconds. Pass `DateTime`/seconds explicitly to test freshness; do not rely on wall-clock sleeps.
- A shared `live_session` scope migration may reveal stale tests that still write `demo_character_id`. Add a fixture helper that writes `current_account_id`/`current_character_id` and migrate tests incrementally.
- No production token is available locally. Unit tests derive expected signatures from `test-bot-token`; runtime missing-token behavior must fail safely.

## Sources

- `docs/MMGO_GDD.md` §16.4
- `https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app` (validation algorithm and auth-date requirement)
- `lib/mmgo/accounts.ex`, `lib/mmgo/telegram.ex`, `lib/mmgo_web/router.ex`, `lib/mmgo_web/endpoint.ex`
