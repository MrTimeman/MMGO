# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mmgo,
  namespace: MMGO,
  ecto_repos: [MMGO.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :mmgo, Oban,
  repo: MMGO.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24}
  ],
  queues: [default: 10]

config :mmgo, MMGO.AI,
  default_provider: MMGO.AI.Providers.Mock,
  models: %{
    spell_compile: "gemini-2.5-flash",
    turn_narration: "gemini-2.5-flash-lite",
    combat_orchestrator: "gemini-2.5-flash",
    dungeon_tick: "gemini-2.5-flash"
  },
  prompt_versions: %{
    spell_compile: "2026-04-19.spell-compile.v2",
    turn_narration: "2026-04-19.turn-narration.v2",
    combat_orchestrator: "2026-04-19.combat-orchestrator.v1",
    dungeon_tick: "2026-04-19.dungeon-tick.v1"
  }

config :mmgo, MMGO.AI.Providers.Gemini,
  api_base_url: "https://generativelanguage.googleapis.com/v1beta",
  api_key: nil

config :mmgo, MMGO.AI.Providers.DeepSeek,
  api_base_url: "https://api.deepseek.com",
  api_key: nil,
  models: %{},
  max_tokens: 4096,
  thinking: nil,
  reasoning_effort: nil

config :mmgo, MMGO.Telegram,
  api_base_url: "https://api.telegram.org",
  bot_token: nil

config :mmgo, MMGO.PVP, duel_tax_rate_bps: 500

# Configure the endpoint
config :mmgo, MMGOWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MMGOWeb.ErrorHTML, json: MMGOWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MMGO.PubSub,
  live_view: [signing_salt: "TliYA0VF"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mmgo, MMGO.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mmgo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  mmgo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
