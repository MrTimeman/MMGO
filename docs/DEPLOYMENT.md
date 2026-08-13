# Alpha Deployment Runbook

MMGO ships as a Phoenix/OTP release. The supported alpha topology is one application release plus PostgreSQL 16; Oban runs inside the application node.

## Required production configuration

Use `deploy/production/mmgo.env.example` only as a checklist, and store the
completed file on the production host at `/opt/mmgo/mmgo.env`, never in source
control. Production startup fails closed unless these values are present:

- `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`
- `TELEGRAM_MINI_APP_URL` (normally `https://<PHX_HOST>/play`)
- `FEDERATION_PUBLIC_BASE_URL`, `FEDERATION_IMPORT_TOKEN`
- `DEEPSEEK_API_KEY`

DeepSeek is the authoritative production spell compiler. Empty or
whitespace-only keys and model overrides count as unset; when no nonblank
`AI_SPELL_MODEL` override is supplied, DeepSeek uses `deepseek-chat`.
`MMGO_ALLOW_MOCK_AI_IN_PROD=true` remains an explicit runtime escape hatch for
an isolated fallback-only test, but the standard `just deploy` production path
deliberately rejects Mock or Gemini.

Set `ECTO_SSL=false` only when the PostgreSQL connection is on a trusted local/private network that does not support TLS. Generate a release secret with `mix phx.gen.secret`; do not reuse development values.

## Fresh Debian 13 host

The supported bootstrap keeps the laptop Docker-free. It sends only the
checked-in non-secret bootstrap directory over SSH, installs Docker Engine and
Compose from Docker's official Debian repository on the server, and prepares
the runtime layout. Release source is later streamed from the committed Git
tree and the image is built entirely on the remote host.

For the directly reachable production host:

```bash
MMGO_JUMP_HOST='' \
MMGO_APP_HOST=root@138.249.117.21 \
just bootstrap-host
```

The bootstrap is pinned to Debian 13 and refuses to remove conflicting
container packages, overwrite `/opt/mmgo` configuration, or replace an
existing nginx virtual host. It installs these paths:

- `/opt/mmgo/docker-compose.prod.yml` — PostgreSQL 16 plus the release, with
  Phoenix bound only to `127.0.0.1:4000` on the host.
- `/opt/mmgo/mmgo.env.example` — non-secret configuration checklist.
- `/opt/mmgo/releases` and the mode-0700 `/opt/mmgo/backups` directory.
- `/etc/nginx/sites-available/mmgo.conf` only when nginx does not already
  manage the configured hostname. The existing nginx configuration is tested
  before a reload and otherwise left untouched.
- `/etc/nginx/sites-available/mmgo-preview.conf` — a loopback-only
  `127.0.0.1:4080` proxy used exclusively by `just prod-tunnel`; it is not a
  public listener.

Create the protected env file on the host and replace every placeholder. The
PostgreSQL password must be URL-encoded in `DATABASE_URL` when it contains URL
punctuation. Do not copy the completed file back to the laptop:

```bash
ssh root@138.249.117.21
install -m 0600 /opt/mmgo/mmgo.env.example /opt/mmgo/mmgo.env
editor /opt/mmgo/mmgo.env
exit

MMGO_JUMP_HOST='' MMGO_APP_HOST=root@138.249.117.21 just prod-init
```

On the host, `openssl rand -hex 32` makes a URL-safe PostgreSQL password and
`openssl rand -hex 64` makes suitable Phoenix, webhook, and federation
secrets. The Telegram bot token and DeepSeek API key must come from their
respective providers.

`prod-init` validates ownership, permissions, required nonblank values, and
example placeholders before it starts only PostgreSQL. It does not start or
replace the application. Do not use the root `compose.yaml` in production; it
contains deliberately simple local-development credentials and publishes the
database port.

If the hostname did not already have TLS in nginx, point DNS at the host and
provision the certificate before `just deploy`. For example, after reviewing
the generated independent site, use the Debian Certbot nginx integration:

```bash
apt-get install certbot python3-certbot-nginx
certbot --nginx -d mmgo.mrtimeman.ru
nginx -t
```

The application deploy verifies HTTPS from the server with a loopback
`--resolve`, so a university or corporate DNS filter on the laptop cannot turn
a healthy release into a false deployment failure.

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

Before switching Compose, the smoke container must report DeepSeek as the
resolved provider, a nonblank spell model, and a successful low-cost structured
JSON completion from the live DeepSeek endpoint. A missing key, wrong provider,
bad model, network failure, rejected API request, or malformed response aborts
the deployment before production is replaced; the probe output never prints
the API key or provider response body.

`MMGO_RELEASE_NOTES` becomes the player-facing Telegram announcement. Keep it
short, concrete, and free of internal commit details; the bot adds the closed
alpha heading and version automatically.

The target defaults match the current MMGO infrastructure (`klara` as the jump
host, `nova` as the application host, and `/opt/mmgo` as the runtime root).
Override them without editing the recipe through `MMGO_JUMP_HOST`,
`MMGO_APP_HOST`, `MMGO_REMOTE_ROOT`, `MMGO_PUBLIC_URL`, or
`MMGO_PRIVATE_HEALTH_URL`. Set `MMGO_JUMP_HOST` to an empty value when the
application host is directly reachable; `deploy`, `prod-status`, and
`prod-logs` then use SSH/SCP without a proxy jump:

```bash
MMGO_JUMP_HOST= MMGO_APP_HOST=root@138.249.117.21 just deploy-plan
MMGO_JUMP_HOST= MMGO_APP_HOST=root@138.249.117.21 just deploy
```

The recipe never reads production secrets locally and never packages ignored
or uncommitted files.

The deployment uses Docker's `default` builder unless
`MMGO_DOCKER_BUILDER` names another builder already configured on the
application host. Non-default builders are invoked with `--load`, so the
resulting image is available to the host's Compose runtime. This is useful for
isolating a release build from a damaged or heavily contended default BuildKit
cache.

No Docker client or daemon is used on the laptop. `just deploy` creates a
checksummed archive from the clean committed tree, uploads it over SSH, and
runs `docker build` on the application host.

For a standalone container deployment, the equivalent low-level commands are:

```bash
docker build -t mmgo:0.1.0-alpha.10 .
docker run --rm --env-file /secure/path/mmgo.env mmgo:0.1.0-alpha.10 bin/migrate
docker run --rm --env-file /secure/path/mmgo.env mmgo:0.1.0-alpha.10 bin/seed
docker run --name mmgo --env-file /secure/path/mmgo.env -p 4000:4000 mmgo:0.1.0-alpha.10
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

When the public hostname is blocked on the current network, verify the full UI
through an encrypted SSH tunnel instead of exposing Phoenix on a public port:

```bash
MMGO_JUMP_HOST='' MMGO_APP_HOST=root@138.249.117.21 just prod-tunnel 4400
# Keep that command running, then open http://127.0.0.1:4400
```

This reaches the server's loopback-only port through the host IP. For a simple
nginx/readiness check that does not require DNS and exposes no application
session, use the hostname only as the HTTP Host header:

```bash
curl -H 'Host: mmgo.mrtimeman.ru' http://138.249.117.21/healthz
```

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
