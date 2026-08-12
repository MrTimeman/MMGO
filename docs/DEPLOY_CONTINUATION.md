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
- Pushed release HEAD: `78e7695`
- New host: `root@138.249.117.21`
- Old host, reachable from the new host: `root@100.64.0.2`
- Public domain: `https://mmgo.mrtimeman.ru`
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
  DeepSeek provider/model. The live DeepSeek structured-completion probe passed.
- `mmgo-app` is live, healthy, has zero restarts, and reports alpha.9 through
  the private listener, domain TLS vhost, and dedicated HTTP IP vhost.
- Public nginx now uses `http://127.0.0.1:4000`; its pre-cutover backup is
  `/opt/mmgo/backups/mmgo-nginx-pre-alpha9.conf`.
- Direct IP access is installed at `http://138.249.117.21`. Phoenix and
  PostgreSQL remain unexposed on raw public ports.

## Current state

Deployment is complete. Expected verification state:

```bash
ssh root@138.249.117.21 \
  'docker inspect mmgo-app --format="image={{.Config.Image}} status={{.State.Status}} health={{.State.Health.Status}} restarts={{.RestartCount}}"'
```

Expected: image `mmgo:0.1.0-alpha.9`, running, healthy, zero restarts. The
database retains 12 beta accounts and 13 characters; its latest migrations are
`20260812201850`, `20260812191140`, and `20260812190955`.

## Future deploys

Use a clean detached worktree because the main worktree contains user-owned
untracked `.gitea` files:

```bash
deploy_dir="$(mktemp -d /private/tmp/mmgo-deploy.XXXXXX)"
git worktree add --detach "$deploy_dir" HEAD
cd "$deploy_dir"
mix deps.get
MMGO_DB_USER=albert MMGO_DB_PASSWORD='' \
MMGO_JUMP_HOST='' MMGO_APP_HOST='root@138.249.117.21' \
MMGO_PUBLIC_URL='https://mmgo.mrtimeman.ru' \
MMGO_RELEASE_NOTES='Краткое описание выпуска.' \
just deploy
```

Do not bypass the DeepSeek probe. The first cold start on this 1 GB host can
take longer than one minute; inspect private health before treating a timeout
as a failed application. Keep `ERL_AFLAGS=+Q 65536` in the remote env.

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

Retain the protected alpha.8 import dump and pre-alpha.9 database backups on
the new host until the observation window closes.
