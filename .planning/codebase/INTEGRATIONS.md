# Integrations

## Integration inventory

| Boundary | Direction | Implementation |
| --- | --- | --- |
| PostgreSQL | read/write | Ecto repo `lib/mmgo/repo.ex` and migrations in `priv/repo/migrations/` |
| Telegram Bot API | inbound webhook and outbound API calls | `lib/mmgo/telegram.ex`, `lib/mmgo/telegram/client.ex`, `lib/mmgo_web/controllers/telegram_webhook_controller.ex` |
| Google Gemini | outbound AI completion requests | `lib/mmgo/ai/providers/gemini.ex` |
| DeepSeek | outbound AI completion requests | `lib/mmgo/ai/providers/deepseek.ex` |
| Remote MMGO realms | manifest discovery and character migration | `lib/mmgo/federation.ex`, `lib/mmgo_web/controllers/federation_controller.ex` |
| Browser client | LiveView WebSocket/long-poll and JSON HTTP | `lib/mmgo_web/endpoint.ex`, `lib/mmgo_web/router.ex` |

## PostgreSQL and jobs

- `MMGO.Repo` uses `Ecto.Adapters.Postgres` in `lib/mmgo/repo.ex`; production requires `DATABASE_URL` in `config/runtime.exs`.
- Development and test use `MMGO_DB_HOST`, `MMGO_DB_PORT`, `MMGO_DB_USER`, `MMGO_DB_PASSWORD`, and database-name environment variables in `config/dev.exs` and `config/test.exs`.
- `compose.yaml` runs a PostgreSQL 16 service and persists its volume as `postgres_data`.
- Oban uses the same database for durable background jobs. Notification delivery runs on its separate `telegram` queue in `lib/mmgo/notifications/delivery_worker.ex`.
- AI request/response metadata is persisted by `MMGO.AI` in `lib/mmgo/ai.ex`, rather than being sent to a separate observability service.

## Telegram bot and webhook

- The outbound client calls the Telegram Bot API base URL (default `https://api.telegram.org`) using Req in `lib/mmgo/telegram/client.ex`.
- Supported outbound Bot API operations are `getMe`, `setWebhook`, and `sendMessage`; the bot token comes from `TELEGRAM_BOT_TOKEN` via `config/runtime.exs`.
- Telegram posts updates to `POST /api/telegram/webhook`, registered in `lib/mmgo_web/router.ex` and handled by `lib/mmgo_web/controllers/telegram_webhook_controller.ex`.
- The controller checks `x-telegram-bot-api-secret-token` with a constant-time comparison when `TELEGRAM_WEBHOOK_SECRET` is configured (`lib/mmgo/telegram.ex`). With no configured secret, the authorization helper intentionally accepts the update.
- `MMGO.Telegram.UpdateHandler` provisions or refreshes an Account, TelegramIdentity, and default Character from the update's `from` payload through `MMGO.Accounts.provision_from_telegram/1`.
- Telegram notifications are formatted and scheduled through `lib/mmgo/notifications.ex`; failures are retried by Oban up to five attempts in `lib/mmgo/notifications/delivery_worker.ex`.
- Test configuration redirects Telegram traffic to a local endpoint in `config/test.exs`, and tests use Bypass rather than the real API.

## Generative AI providers

- Gemini calls `https://generativelanguage.googleapis.com/v1beta/...:generateContent` through Req with an `x-goog-api-key` header in `lib/mmgo/ai/providers/gemini.ex`.
- `GEMINI_API_KEY`, optional `GEMINI_API_BASE_URL`, and model environment variables are mapped in `config/runtime.exs`; Gemini supports native JSON-schema response configuration for spell compilation.
- DeepSeek calls `https://api.deepseek.com/v1/chat/completions` through Req with a Bearer token in `lib/mmgo/ai/providers/deepseek.ex`.
- `DEEPSEEK_API_KEY` selects the DeepSeek provider ahead of Gemini outside test; otherwise the configured mock provider remains the default (`config/runtime.exs`).
- `MMGO.AI.Provider` in `lib/mmgo/ai/provider.ex` is the provider-neutral boundary for structured and free-form completions.
- The mock provider in `lib/mmgo/ai/providers/mock.ex` keeps development and test flows usable without an external LLM credential.

## Realm federation API

- The application exposes `GET /api/federation/realm-manifest`; it serializes public realm metadata through `MMGO.Federation.export_realm_manifest/1` in `lib/mmgo_web/controllers/federation_controller.ex`.
- It exposes `POST /api/federation/import-migration` for incoming character migrations. This endpoint requires `Authorization: Bearer ...` matching `FEDERATION_IMPORT_TOKEN`, using a constant-time comparison.
- `MMGO.Federation.fetch_remote_manifest/1` GETs a registered realm's manifest URL with Req and validates its JSON shape in `lib/mmgo/federation.ex`.
- Outgoing migration requests POST JSON to each remote realm's `/api/federation/import-migration` endpoint and send its stored access token as a Bearer token (`lib/mmgo/federation.ex`).
- Remote realm endpoint, manifest URL, ruleset, migration state, and exchange rates are persisted in federation schemas under `lib/mmgo/federation/`.
- `FEDERATION_PUBLIC_BASE_URL` controls the exported public endpoint fallback; freeze and retention rules are also runtime-configurable in `config/runtime.exs`.

## Browser, session, and access control

- The endpoint gives browsers a signed, SameSite=Lax cookie session and passes it to LiveView's WebSocket/long-poll connections (`lib/mmgo_web/endpoint.ex`).
- Current browser gameplay uses `demo_character_id` and `demo_opponent_id` session values set by `lib/mmgo_web/controllers/play_demo_controller.ex`, not a general login flow.
- JSON play endpoints under `/api/play` require that demo cookie session and retain browser CSRF protection via the `:browser_api` pipeline (`lib/mmgo_web/router.ex`).
- No OAuth/password authentication provider or authenticated LiveView route group is configured in `mix.exs` or `lib/mmgo_web/router.ex`; Telegram identity is the only persisted external identity path.
- Operator-only Telegram commands use a configured comma-separated `OPERATOR_HANDLES` allowlist through `MMGO.Operator` (`config/runtime.exs` and `lib/mmgo/operator.ex`).
- The plain `:api` pipeline is used for Telegram and federation routes; their endpoint-specific secret/token checks are their authorization boundary.

## Other external and local boundaries

- `assets/css/app.css` imports Google Fonts from `fonts.googleapis.com`, making typography a browser-time external asset dependency.
- `MMGO.Mailer` exists in `lib/mmgo/mailer.ex`, but the configured adapters are local in development and test in `config/config.exs`/`config/test.exs`; no production mail provider is enabled in source.
- The map editor writes terrain JSON and sprite files to configured static paths via `lib/mmgo/world_map.ex` and `lib/mmgo/world_map/editor.ex`; those files are then served by `Plug.Static`.
- `/healthz` is a public JSON liveness/version response from `lib/mmgo_web/controllers/health_controller.ex`.
