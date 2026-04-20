# Default: start dev server
default: dev

# Start the development server
dev:
    mix phx.server

# Start the local map demo and print the suggested route
demo:
    @echo "MMGO local map demo"
    @echo "Open http://localhost:4000/play"
    @echo "Suggested route: Capital City -> Ash Crossing -> The Tower"
    @echo "Use the in-app 'Reset demo to start' button to return to Capital City."
    mix phx.server

# Start dev server with interactive Elixir shell
iex:
    iex -S mix phx.server

# Full project setup (deps, DB, assets)
setup:
    mix setup

# Reset DB, reseed the map graph, and get ready for the local demo
demo-setup:
    mix ecto.reset
    @echo "Demo world reseeded. Start it with: just demo"

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
