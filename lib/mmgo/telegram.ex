defmodule MMGO.Telegram do
  alias MMGO.Telegram.{Client, UpdateHandler}

  def webhook_path do
    config()[:webhook_path] || "/api/telegram/webhook"
  end

  def mini_app_url, do: config()[:mini_app_url]

  def authorized_webhook_secret?(provided_secret) do
    case config()[:webhook_secret] do
      secret when secret in [nil, ""] ->
        config()[:allow_insecure_webhook?] == true

      secret
      when is_binary(secret) and is_binary(provided_secret) and
             byte_size(secret) == byte_size(provided_secret) ->
        Plug.Crypto.secure_compare(secret, provided_secret)

      _ ->
        false
    end
  end

  def handle_update(update) when is_map(update) do
    UpdateHandler.handle(update)
  end

  def set_webhook(base_url) when is_binary(base_url) do
    base_url
    |> URI.parse()
    |> URI.append_path(webhook_path())
    |> URI.to_string()
    |> Client.set_webhook()
  end

  def configure_bot(base_url) when is_binary(base_url) do
    with mini_app_url when is_binary(mini_app_url) <- mini_app_url(),
         {:ok, true} <- set_webhook(base_url),
         {:ok, true} <- Client.set_chat_menu_button(mini_app_url),
         {:ok, true} <- Client.set_commands(default_commands()) do
      {:ok, %{webhook: true, menu_button: true, commands: true}}
    else
      nil -> {:error, :missing_mini_app_url}
      error -> error
    end
  end

  defdelegate bot_info, to: Client, as: :get_me
  defdelegate send_message(chat_id, text, opts \\ []), to: Client

  defp default_commands do
    [
      %{command: "start", description: "Создать персонажа и открыть MMGO"},
      %{command: "play", description: "Открыть игру"},
      %{command: "help", description: "Что умеет бот"},
      %{command: "status", description: "Где я и что дальше"},
      %{command: "inventory", description: "Вещи и ресурсы"},
      %{command: "routes", description: "Соседние направления"},
      %{command: "journey", description: "Проверить переход"},
      %{command: "spells", description: "Подготовленные заклинания"}
    ]
  end

  defp config do
    Application.get_env(:mmgo, __MODULE__, [])
  end
end
