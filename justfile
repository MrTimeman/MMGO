# Default: start dev server
default: dev

# Start the development server
dev:
    mix phx.server

# Start dev server with interactive Elixir shell
iex:
    iex -S mix phx.server

# Full project setup (deps, DB, assets)
setup:
    mix setup

# Run the test suite
test *args:
    mix test {{args}}

# Run precommit checks (compile, format, test)
check:
    mix precommit

# Format code
fmt:
    mix format

# ── Database ────────────────────────────────────────────────────────────────

db-setup:
    mix ecto.setup

db-reset:
    mix ecto.reset

db-migrate:
    mix ecto.migrate

db-rollback:
    mix ecto.rollback

# ── Docker ──────────────────────────────────────────────────────────────────

# Start Postgres in the background
up:
    docker compose up -d

# Stop all containers
down:
    docker compose down

# ── Assets ──────────────────────────────────────────────────────────────────

# Build JS + CSS for development
assets:
    mix assets.build

# Build and digest assets for production
assets-deploy:
    mix assets.deploy

# ── Misc ────────────────────────────────────────────────────────────────────

# Remove compiled artefacts
clean:
    mix clean
