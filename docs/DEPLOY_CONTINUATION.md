# Alpha.9 deployment continuation

This is a secret-free handoff for another coding agent if the current session
ends. Read `AGENTS.md` and `docs/DEPLOYMENT.md` first. Do not print or copy
`/opt/mmgo/mmgo.env` to the laptop.

## Goal and authority

The user explicitly approved transferring the production secrets and beta
database from the old host, deploying, switching traffic, and checking through
the public IP. The laptop must remain Docker-free.

- Repository: `/Users/albert/Documents/coding/mmgo`
- Branch: `main`
- Pushed release HEAD: `b279457`
- New host: `root@138.249.117.21`
- Old host, reachable from the new host: `root@100.64.0.2`
- Public domain: `https://mmgo.mrtimeman.ru`
- Clean deploy worktree: `/private/tmp/mmgo-deploy-9e97a02`
- Release: `mmgo:0.1.0-alpha.9`

Never add the user's untracked `.gitea/ISSUE_TEMPLATE/` files to a commit.

## Completed

- Arena, manifestations, random events, ranks, custom NvN rooms, mode choice,
  persistent default MMO character, and beta-duel removal are committed/pushed.
- `mix precommit` passes: 802 tests, including one property test.
- New Debian 13 host has Docker/Compose and nginx; `/opt/mmgo` is bootstrapped.
- Protected env was copied directly host-to-host and remains mode 0600.
- Added `ERL_AFLAGS=+Q 65536` remotely because Erlang 29's default port table
  could not fit the 1 GB host.
- Old beta database was transferred as a checksum-verified custom dump and
  restored. It contained 12 accounts and 13 characters.
- Protected import dump: `/opt/mmgo/backups/mmgo-import-alpha8.dump`.
- All three alpha.9 migrations completed successfully.
- Image built successfully on the new host.
- Isolated smoke app passed `/healthz`, home/play markers, and resolved the
  DeepSeek provider/model. A first live DeepSeek call had a transient network
  error; credential-free host and container checks later both reached DeepSeek
  with HTTP 401, proving TLS/network recovery.
- Public nginx still points to the old healthy host. No production app cutover
  has happened yet.

## Current state and immediate recovery

The isolated `mmgo-deploy-smoke` container is still running healthy on
`127.0.0.1:4100`. A cleanup attempt used an unsupported long Docker option and
did nothing. Remove it with the Docker 26-compatible short option:

```bash
ssh -o BatchMode=yes root@138.249.117.21 \
  'docker stop -t 15 mmgo-deploy-smoke >/dev/null; ! docker inspect mmgo-deploy-smoke >/dev/null 2>&1'
```

Then rerun the committed, cached pipeline:

```bash
cd /private/tmp/mmgo-deploy-9e97a02
MMGO_DB_USER=albert MMGO_DB_PASSWORD='' \
MMGO_JUMP_HOST='' MMGO_APP_HOST='root@138.249.117.21' \
MMGO_PUBLIC_URL='https://mmgo.mrtimeman.ru' \
MMGO_RELEASE_NOTES='Добавили отдельную Арену: ранги, дружеские командные бои, события окружения и заклинания призыва.' \
just deploy
```

The build and migrations are cached/idempotent. Do not bypass the DeepSeek
probe. If it fails again, inspect the failure and retain the old live service.

## Cutover after private alpha.9 is healthy

The existing nginx file is
`/etc/nginx/sites-enabled/mmgo.mrtimeman.ru.conf`. It currently contains two
exact upstreams `http://100.64.0.2:4000`. Back it up, replace only those exact
upstreams with `http://127.0.0.1:4000`, run `nginx -t`, and reload. Do not dump
the whole production nginx configuration or alter other sites.

Create a dedicated HTTP IP vhost so the university-blocked domain is not
required. Use exact `server_name 138.249.117.21`, proxy to
`http://127.0.0.1:4000`, preserve WebSocket headers, test nginx, then reload.
Do not publish Phoenix port 4000 directly.

Verify:

```bash
ssh root@138.249.117.21 'docker inspect mmgo-app --format="image={{.Config.Image}} status={{.State.Status}} health={{.State.Health.Status}}"'
ssh root@138.249.117.21 'curl -fsS http://127.0.0.1:4000/livez; curl -fsS http://127.0.0.1:4000/healthz'
curl -fsS http://138.249.117.21/healthz
curl -fsS -H 'Host: mmgo.mrtimeman.ru' http://138.249.117.21/healthz
ssh root@138.249.117.21 'docker logs --tail 200 mmgo-app'
```

The health JSON must report version `0.1.0-alpha.9`. Also check the latest
three schema migrations and that account/character counts remain 12/13 or
increase only through legitimate new activity.

After success, remove the explicit old-host transfer temp file
`/tmp/mmgo-alpha9-transfer.dump` on `100.64.0.2`; retain the protected backup on
the new host. Remove the detached worktree with `git worktree remove` only when
deployment and verification are complete.
