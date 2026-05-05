import Config

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

ai_config = Application.get_env(:mmgo, MMGO.AI, [])
gemini_config = Application.get_env(:mmgo, MMGO.AI.Providers.Gemini, [])
deepseek_config = Application.get_env(:mmgo, MMGO.AI.Providers.DeepSeek, [])
gemini_api_key = System.get_env("GEMINI_API_KEY") || gemini_config[:api_key]
gemini_env_api_key = System.get_env("GEMINI_API_KEY")
deepseek_api_key = System.get_env("DEEPSEEK_API_KEY") || deepseek_config[:api_key]
deepseek_env_api_key = System.get_env("DEEPSEEK_API_KEY")

selected_ai_provider =
  case String.downcase(System.get_env("MMGO_AI_PROVIDER") || "") do
    "deepseek" -> MMGO.AI.Providers.DeepSeek
    "gemini" -> MMGO.AI.Providers.Gemini
    "mock" -> MMGO.AI.Providers.Mock
    _ when deepseek_env_api_key not in [nil, ""] -> MMGO.AI.Providers.DeepSeek
    _ when gemini_env_api_key not in [nil, ""] -> MMGO.AI.Providers.Gemini
    _ -> ai_config[:default_provider]
  end

deepseek_default_model = System.get_env("DEEPSEEK_MODEL") || "deepseek-chat"
deepseek_models = deepseek_config[:models] || %{}

deepseek_max_tokens =
  case Integer.parse(System.get_env("DEEPSEEK_MAX_TOKENS") || "") do
    {tokens, ""} -> tokens
    _ -> deepseek_config[:max_tokens] || 4096
  end

ai_models =
  if selected_ai_provider == MMGO.AI.Providers.DeepSeek do
    %{
      spell_compile:
        System.get_env("DEEPSEEK_SPELL_MODEL") || deepseek_models[:spell_compile] ||
          deepseek_default_model,
      turn_narration:
        System.get_env("DEEPSEEK_NARRATION_MODEL") || deepseek_models[:turn_narration] ||
          deepseek_default_model,
      combat_orchestrator:
        System.get_env("DEEPSEEK_ORCHESTRATOR_MODEL") ||
          deepseek_models[:combat_orchestrator] || deepseek_default_model,
      dungeon_tick:
        System.get_env("DEEPSEEK_DUNGEON_TICK_MODEL") || deepseek_models[:dungeon_tick] ||
          deepseek_default_model
    }
  else
    %{
      spell_compile: System.get_env("GEMINI_SPELL_MODEL") || ai_config[:models][:spell_compile],
      turn_narration:
        System.get_env("GEMINI_NARRATION_MODEL") || ai_config[:models][:turn_narration],
      combat_orchestrator:
        System.get_env("GEMINI_ORCHESTRATOR_MODEL") || ai_config[:models][:combat_orchestrator],
      dungeon_tick:
        System.get_env("GEMINI_DUNGEON_TICK_MODEL") || ai_config[:models][:dungeon_tick]
    }
  end

config :mmgo, MMGO.AI,
  default_provider: selected_ai_provider,
  models: ai_models,
  prompt_versions: ai_config[:prompt_versions]

config :mmgo, MMGO.AI.Providers.Gemini,
  api_base_url:
    System.get_env("GEMINI_API_BASE_URL") || gemini_config[:api_base_url] ||
      "https://generativelanguage.googleapis.com/v1beta",
  api_key: gemini_api_key

config :mmgo, MMGO.AI.Providers.DeepSeek,
  api_base_url:
    System.get_env("DEEPSEEK_API_BASE_URL") || deepseek_config[:api_base_url] ||
      "https://api.deepseek.com",
  api_key: deepseek_api_key,
  max_tokens: deepseek_max_tokens,
  thinking: System.get_env("DEEPSEEK_THINKING") || deepseek_config[:thinking],
  reasoning_effort:
    System.get_env("DEEPSEEK_REASONING_EFFORT") || deepseek_config[:reasoning_effort]

telegram_config = Application.get_env(:mmgo, MMGO.Telegram, [])

config :mmgo, MMGO.Telegram,
  api_base_url: System.get_env("TELEGRAM_API_BASE_URL") || telegram_config[:api_base_url],
  bot_token: System.get_env("TELEGRAM_BOT_TOKEN") || telegram_config[:bot_token]

pvp_config = Application.get_env(:mmgo, MMGO.PVP, [])

config :mmgo, MMGO.PVP,
  duel_tax_rate_bps:
    String.to_integer(
      System.get_env("DUEL_TAX_RATE_BPS") || to_string(pvp_config[:duel_tax_rate_bps] || 500)
    )

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :mmgo, MMGO.Repo,
    # ssl: true,
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
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

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
