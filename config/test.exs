import Config

db_port = String.to_integer(System.get_env("MMGO_DB_PORT") || "5432")

test_db_name =
  System.get_env("MMGO_TEST_DB_NAME") || "mmgo_test#{System.get_env("MIX_TEST_PARTITION")}"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mmgo, MMGO.Repo,
  username: System.get_env("MMGO_DB_USER") || "postgres",
  password: System.get_env("MMGO_DB_PASSWORD") || "postgres",
  hostname: System.get_env("MMGO_DB_HOST") || "localhost",
  port: db_port,
  database: test_db_name,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :mmgo, Oban, testing: :manual

config :mmgo, MMGO.Telegram,
  api_base_url: "http://localhost:8081",
  bot_token: "test-bot-token",
  webhook_secret: "test-webhook-secret"

config :mmgo, MMGO.AI,
  default_provider: MMGO.AI.Providers.Mock,
  models: %{
    spell_compile: "gemini-3-flash-test",
    turn_narration: "g3f-lite-test",
    combat_orchestrator: "g3f-orchestrator-test",
    dungeon_tick: "g3f-dungeon-test"
  },
  prompt_versions: %{
    spell_compile: "test.spell-compile.v2",
    turn_narration: "test.turn-narration.v2",
    combat_orchestrator: "test.combat-orchestrator.v1",
    dungeon_tick: "test.dungeon-tick.v1"
  }

config :mmgo, MMGO.AI.Providers.Gemini,
  api_base_url: "http://localhost:8082",
  api_key: "test-gemini-key"

config :mmgo, MMGO.AI.Providers.DeepSeek,
  api_base_url: "http://localhost:8083",
  api_key: "test-deepseek-key",
  models: %{
    spell_compile: "deepseek-v4-pro-test",
    turn_narration: "deepseek-v4-pro-test",
    combat_orchestrator: "deepseek-v4-pro-test",
    dungeon_tick: "deepseek-v4-pro-test"
  },
  max_tokens: 4096,
  thinking: nil,
  reasoning_effort: nil

config :mmgo, MMGO.Federation,
  freeze_game_days: 28,
  level_retention_bps: 800,
  xp_retention_bps: 700,
  public_base_url: "http://localhost:4002",
  import_token: "test-federation-token"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mmgo, MMGOWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "shQW2atmuEEj+tjK9/ofbeaNadmG7hzOwGQg02K/UzHCQaZ5yjrCznsboi9VPXhn",
  server: false

# In test we don't send emails
config :mmgo, MMGO.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
