import Config

required_env! = fn name ->
  case System.get_env(name) do
    value when is_binary(value) and value != "" -> value
    _missing -> raise "environment variable #{name} is required in production"
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mmgo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mmgo, MMGOWeb.Endpoint, server: true
end

config :mmgo, MMGOWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

telegram_config = Application.get_env(:mmgo, MMGO.Telegram, [])

telegram_bot_token = System.get_env("TELEGRAM_BOT_TOKEN") || telegram_config[:bot_token]

telegram_webhook_secret =
  System.get_env("TELEGRAM_WEBHOOK_SECRET") || telegram_config[:webhook_secret]

if config_env() == :prod do
  if telegram_bot_token in [nil, ""] do
    raise "environment variable TELEGRAM_BOT_TOKEN is required in production"
  end

  if telegram_webhook_secret in [nil, ""] do
    raise "environment variable TELEGRAM_WEBHOOK_SECRET is required in production"
  end
end

allow_insecure_webhook? =
  config_env() != :prod and
    (System.get_env("TELEGRAM_ALLOW_INSECURE_WEBHOOK") == "true" or
       telegram_config[:allow_insecure_webhook?] == true)

web_app_auth_max_age_seconds =
  System.get_env("TELEGRAM_WEB_APP_AUTH_MAX_AGE_SECONDS") ||
    to_string(telegram_config[:web_app_auth_max_age_seconds] || 86_400)

telegram_mini_app_url =
  System.get_env("TELEGRAM_MINI_APP_URL") ||
    case System.get_env("PHX_HOST") do
      host when is_binary(host) and host != "" -> "https://#{host}/play"
      _missing -> telegram_config[:mini_app_url]
    end

telegram_release_admin_user_id =
  System.get_env("TELEGRAM_RELEASE_ADMIN_USER_ID") ||
    to_string(telegram_config[:release_admin_user_id] || 1_265_881_543)

config :mmgo, MMGO.Telegram,
  api_base_url:
    System.get_env("TELEGRAM_API_BASE_URL") || telegram_config[:api_base_url] ||
      "https://api.telegram.org",
  bot_token: telegram_bot_token,
  webhook_secret: telegram_webhook_secret,
  webhook_path: telegram_config[:webhook_path] || "/api/telegram/webhook",
  allow_insecure_webhook?: allow_insecure_webhook?,
  web_app_auth_max_age_seconds: String.to_integer(web_app_auth_max_age_seconds),
  mini_app_url: telegram_mini_app_url,
  release_admin_user_id: String.to_integer(telegram_release_admin_user_id)

# Keep the deterministic local demo useful while developing or running the
# browser-loop tests, but never expose it as a production authentication path.
# Developers may explicitly turn it off with MMGO_LOCAL_DEMO_ENABLED=false.
local_demo_enabled? =
  config_env() in [:dev, :test] and System.get_env("MMGO_LOCAL_DEMO_ENABLED") != "false"

config :mmgo, local_demo_enabled: local_demo_enabled?

ai_config = Application.get_env(:mmgo, MMGO.AI, [])
gemini_config = Application.get_env(:mmgo, MMGO.AI.Providers.Gemini, [])
gemini_api_key = System.get_env("GEMINI_API_KEY") || gemini_config[:api_key]
gemini_env_api_key = System.get_env("GEMINI_API_KEY")
deepseek_api_key = System.get_env("DEEPSEEK_API_KEY")

if config_env() == :prod and gemini_api_key in [nil, ""] and deepseek_api_key in [nil, ""] and
     System.get_env("MMGO_ALLOW_MOCK_AI_IN_PROD") != "true" do
  raise "GEMINI_API_KEY or DEEPSEEK_API_KEY is required in production (set MMGO_ALLOW_MOCK_AI_IN_PROD=true only for an explicit fallback-only deployment)"
end

default_provider =
  cond do
    config_env() == :test -> ai_config[:default_provider]
    deepseek_api_key -> MMGO.AI.Providers.DeepSeek
    gemini_env_api_key -> MMGO.AI.Providers.Gemini
    true -> ai_config[:default_provider]
  end

provider_model = fn generic_env, gemini_env, configured ->
  System.get_env(generic_env) || System.get_env(gemini_env) ||
    if(default_provider == MMGO.AI.Providers.DeepSeek, do: "deepseek-chat", else: configured)
end

config :mmgo, MMGO.AI,
  default_provider: default_provider,
  models: %{
    spell_compile:
      provider_model.("AI_SPELL_MODEL", "GEMINI_SPELL_MODEL", ai_config[:models][:spell_compile]),
    alchemy_brew:
      provider_model.(
        "AI_ALCHEMY_MODEL",
        "GEMINI_ALCHEMY_MODEL",
        ai_config[:models][:alchemy_brew]
      ),
    combat_orchestration:
      provider_model.(
        "AI_COMBAT_MODEL",
        "GEMINI_COMBAT_MODEL",
        ai_config[:models][:combat_orchestration]
      ),
    turn_narration:
      provider_model.(
        "AI_NARRATION_MODEL",
        "GEMINI_NARRATION_MODEL",
        ai_config[:models][:turn_narration]
      )
  },
  prompt_versions: ai_config[:prompt_versions]

config :mmgo, MMGO.AI.Providers.Gemini,
  api_base_url:
    System.get_env("GEMINI_API_BASE_URL") || gemini_config[:api_base_url] ||
      "https://generativelanguage.googleapis.com/v1beta",
  api_key: gemini_api_key

config :mmgo, MMGO.AI.Providers.DeepSeek, api_key: deepseek_api_key

operator_config = Application.get_env(:mmgo, MMGO.Operator, [])

operator_handles =
  case System.get_env("OPERATOR_HANDLES") do
    nil -> operator_config[:handles] || []
    raw_handles -> raw_handles |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

config :mmgo, MMGO.Operator, handles: operator_handles

pvp_config = Application.get_env(:mmgo, MMGO.PVP, [])

config :mmgo, MMGO.PVP,
  duel_tax_rate_bps:
    String.to_integer(
      System.get_env("DUEL_TAX_RATE_BPS") || to_string(pvp_config[:duel_tax_rate_bps] || 500)
    )

black_market_config = Application.get_env(:mmgo, MMGO.BlackMarket, [])

black_market_detection_enabled? =
  case System.get_env("BLACK_MARKET_DETECTION_ENABLED") do
    nil -> black_market_config[:detection_enabled] != false
    value -> value in ["true", "1"]
  end

config :mmgo, MMGO.BlackMarket,
  detection_enabled: black_market_detection_enabled?,
  delivery_game_days:
    String.to_integer(
      System.get_env("BLACK_MARKET_DELIVERY_GAME_DAYS") ||
        to_string(black_market_config[:delivery_game_days] || 7)
    ),
  detection_base_chance_bps:
    String.to_integer(
      System.get_env("BLACK_MARKET_BASE_CHANCE_BPS") ||
        to_string(black_market_config[:detection_base_chance_bps] || 300)
    ),
  detection_price_scale_bps:
    String.to_integer(
      System.get_env("BLACK_MARKET_PRICE_SCALE_BPS") ||
        to_string(black_market_config[:detection_price_scale_bps] || 2)
    ),
  detection_max_chance_bps:
    String.to_integer(
      System.get_env("BLACK_MARKET_MAX_CHANCE_BPS") ||
        to_string(black_market_config[:detection_max_chance_bps] || 5_000)
    ),
  detection_fine_multiplier:
    String.to_integer(
      System.get_env("BLACK_MARKET_FINE_MULTIPLIER") ||
        to_string(black_market_config[:detection_fine_multiplier] || 3)
    )

federation_config = Application.get_env(:mmgo, MMGO.Federation, [])

federation_public_base_url =
  System.get_env("FEDERATION_PUBLIC_BASE_URL") || federation_config[:public_base_url]

federation_import_token =
  System.get_env("FEDERATION_IMPORT_TOKEN") || federation_config[:import_token]

if config_env() == :prod do
  if federation_public_base_url in [nil, ""] do
    raise "environment variable FEDERATION_PUBLIC_BASE_URL is required in production"
  end

  if federation_import_token in [nil, ""] do
    raise "environment variable FEDERATION_IMPORT_TOKEN is required in production"
  end
end

config :mmgo, MMGO.Federation,
  freeze_game_days:
    String.to_integer(
      System.get_env("FEDERATION_FREEZE_GAME_DAYS") ||
        to_string(federation_config[:freeze_game_days] || 28)
    ),
  level_retention_bps:
    String.to_integer(
      System.get_env("FEDERATION_LEVEL_RETENTION_BPS") ||
        to_string(federation_config[:level_retention_bps] || 800)
    ),
  xp_retention_bps:
    String.to_integer(
      System.get_env("FEDERATION_XP_RETENTION_BPS") ||
        to_string(federation_config[:xp_retention_bps] || 700)
    ),
  public_base_url: federation_public_base_url,
  import_token: federation_import_token

if config_env() == :prod do
  database_url = required_env!.("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :mmgo, MMGO.Repo,
    ssl: System.get_env("ECTO_SSL", "true") in ["true", "1"],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = required_env!.("SECRET_KEY_BASE")

  host = required_env!.("PHX_HOST")

  config :mmgo, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :mmgo, MMGOWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :mmgo, MMGOWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :mmgo, MMGOWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :mmgo, MMGO.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
