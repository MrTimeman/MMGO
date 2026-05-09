# ── Dev ─────────────────────────────────────────────────────────────────────

default: dev

dev:
    mix phx.server

iex:
    iex -S mix phx.server

setup:
    mix setup

# ── Test ────────────────────────────────────────────────────────────────────

test *args:
    mix test {{args}}

test-watch:
    fswatch lib test | mix test --stale --listen-on-stdin

check:
    mix precommit

# ── Format & Clean ──────────────────────────────────────────────────────────

fmt:
    mix format

clean:
    mix clean

# ── DB ──────────────────────────────────────────────────────────────────────

db-setup:
    mix ecto.setup

db-reset:
    mix ecto.reset

db-migrate:
    mix ecto.migrate

db-rollback:
    mix ecto.rollback

db-prod-reset:
    ssh -J root@192.168.1.71 root@nova 'docker exec mmgo-postgres psql -U postgres mmgo_prod -c "TRUNCATE characters CASCADE"'

db-prod-shell:
    ssh -J root@192.168.1.71 root@nova 'docker exec -it mmgo-postgres psql -U postgres mmgo_prod'

# ── Docker (local) ──────────────────────────────────────────────────────────

up:
    docker compose up -d

down:
    docker compose down

# ── Assets ──────────────────────────────────────────────────────────────────

assets:
    mix assets.build

assets-deploy:
    mix assets.deploy

# ── Deploy (nova) ───────────────────────────────────────────────────────────

# Full deploy: compile → rsync → build → restart
deploy:
    mix compile
    rsync -az -e "ssh -J root@192.168.1.71" --exclude='.git' --exclude='_build' --exclude='deps' --exclude='.elixir_ls' --exclude='.env' . root@nova:/opt/mmgo/
    ssh -J root@192.168.1.71 root@nova 'cd /opt/mmgo && docker compose -f docker-compose.prod.yml build app && docker rm -f mmgo-app && docker compose -f docker-compose.prod.yml up -d --no-deps app'

# Deploy without compile (if already compiled)
deploy-fast:
    rsync -az -e "ssh -J root@192.168.1.71" --exclude='.git' --exclude='_build' --exclude='deps' --exclude='.elixir_ls' --exclude='.env' . root@nova:/opt/mmgo/
    ssh -J root@192.168.1.71 root@nova 'cd /opt/mmgo && docker compose -f docker-compose.prod.yml build app && docker rm -f mmgo-app && docker compose -f docker-compose.prod.yml up -d --no-deps app'

# Restart app container only (no rebuild)
deploy-restart:
    ssh -J root@192.168.1.71 root@nova 'docker rm -f mmgo-app && cd /opt/mmgo && docker compose -f docker-compose.prod.yml up -d --no-deps app'

# ── Logs ────────────────────────────────────────────────────────────────────

logs:
    ssh -J root@192.168.1.71 root@nova 'docker logs mmgo-app --tail 50'

logs-follow:
    ssh -J root@192.168.1.71 root@nova 'docker logs -f mmgo-app'

# ── SSH ─────────────────────────────────────────────────────────────────────

ssh-nova:
    ssh -J root@192.168.1.71 root@nova

ssh-app:
    ssh -J root@192.168.1.71 root@nova 'docker exec -it mmgo-app sh'

# ── Git ─────────────────────────────────────────────────────────────────────

push *args:
    git add -A
    git commit -m "{{args}}" -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
    git push origin $(git branch --show-current)

pull:
    git pull origin $(git branch --show-current)

main:
    git checkout main && git pull origin main
