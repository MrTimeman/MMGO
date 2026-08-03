# Alpha Deployment Runbook

MMGO ships as a Phoenix/OTP release. The supported alpha topology is one application release plus PostgreSQL 16; Oban runs inside the application node.

## Required production configuration

Copy `.env.example` into your secret manager, not into source control. Production startup fails closed unless these values are present:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`
- `TELEGRAM_MINI_APP_URL` (normally `https://<PHX_HOST>/play`)
- `FEDERATION_PUBLIC_BASE_URL`, `FEDERATION_IMPORT_TOKEN`
- `GEMINI_API_KEY` or `DEEPSEEK_API_KEY`

`MMGO_ALLOW_MOCK_AI_IN_PROD=true` is an explicit fallback-only exception for a closed test deployment. It is not the recommended closed-alpha configuration.

Set `ECTO_SSL=false` only when the PostgreSQL connection is on a trusted local/private network that does not support TLS. Generate a release secret with `mix phx.gen.secret`; do not reuse development values.

## Container build and first start

For the production topology documented below, use the checked-in `justfile`.
It deploys only a clean Git commit and performs the release gate, immutable
source archive, checksum verification, database backup, image build,
migrations, idempotent seed, isolated smoke container, Compose switch,
Telegram configuration, and private/public health checks:

```bash
just deploy-plan
MMGO_RELEASE_NOTES='Исправили путешествия и упростили навигацию по карте.' just deploy
just prod-status
```

`MMGO_RELEASE_NOTES` becomes the player-facing Telegram announcement. Keep it
short, concrete, and free of internal commit details; the bot adds the closed
alpha heading and version automatically.

The target defaults match the current MMGO infrastructure (`klara` as the jump
host, `nova` as the application host, and `/opt/mmgo` as the runtime root).
Override them without editing the recipe through `MMGO_JUMP_HOST`,
`MMGO_APP_HOST`, `MMGO_REMOTE_ROOT`, `MMGO_PUBLIC_URL`, or
`MMGO_PRIVATE_HEALTH_URL`. The recipe never reads production secrets locally
and never packages ignored or uncommitted files.

For a standalone container deployment, the equivalent low-level commands are:

```bash
docker build -t mmgo:0.1.0-alpha.6 .
docker run --rm --env-file /secure/path/mmgo.env mmgo:0.1.0-alpha.6 bin/migrate
docker run --rm --env-file /secure/path/mmgo.env mmgo:0.1.0-alpha.6 bin/seed
docker run --name mmgo --env-file /secure/path/mmgo.env -p 4000:4000 mmgo:0.1.0-alpha.6
```

`bin/seed` is idempotent and installs the canonical realm, treasury, routes, Academy content, construction resources, organisation anchors, and Tower dungeon topology. Run it on first deployment and after a release explicitly changes canonical seed content.

Without Docker, build with `MIX_ENV=prod mix assets.deploy` followed by `MIX_ENV=prod mix release`; the same `bin/migrate`, `bin/seed`, and `bin/server` commands are available under `_build/prod/rel/mmgo`.

## Proxy and Telegram

Terminate TLS at the reverse proxy and forward `x-forwarded-proto: https`. Configure the Telegram webhook to `https://<PHX_HOST>/api/telegram/webhook` and use the exact `TELEGRAM_WEBHOOK_SECRET` as Telegram's secret token. The local demo entry is disabled in production.

After the release is healthy, configure the webhook, default Mini App menu button,
and supported text-command menu from the running release:

```bash
bin/mmgo rpc 'MMGO.Telegram.configure_bot("https://<PHX_HOST>")'
```

`/start` and `/play` replies also include a signed Telegram `web_app` button. Mini
App login validates `Telegram.WebApp.initData` server-side and synchronizes the
signed Telegram display name, username, locale, and profile photo when available.

## Health and monitoring

- `/livez` proves the BEAM process and endpoint are alive.
- `/healthz` also executes `SELECT 1`; a database failure returns HTTP 503.
- The Docker health check probes `/livez` every 30 seconds.

Monitor HTTP error rate, PostgreSQL connections, Oban queue depth/retries, failed Telegram deliveries, failed AI request audit rows, and economy reconciliation reports. Alert on repeated readiness failures rather than restarting indefinitely.

## Deploy and rollback

1. Take a PostgreSQL backup and record the current image digest.
2. Run the new image's `bin/migrate` as a one-off task.
3. Start one instance, wait for both health endpoints, then switch traffic.
4. Exercise Telegram login, a database write, and one Oban job.
5. Retain the prior image and backup until the observation window closes.

Application rollback uses the previous immutable image. Database rollback must be reviewed migration-by-migration; do not run a blanket destructive rollback. Restore the pre-deploy backup when a data migration is not safely reversible.
