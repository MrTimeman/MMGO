defmodule MMGO.Telegram do
  alias MMGO.Telegram.{Client, UpdateHandler}

  def webhook_path do
    config()[:webhook_path] || "/api/telegram/webhook"
  end

  def authorized_webhook_secret?(provided_secret) do
    case config()[:webhook_secret] do
      secret when secret in [nil, ""] ->
        true

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

  defdelegate bot_info, to: Client, as: :get_me
  defdelegate send_message(chat_id, text, opts \\ []), to: Client

  defp config do
    Application.get_env(:mmgo, __MODULE__, [])
  end
end
