defmodule MMGO.Telegram.Client do
  def get_me do
    request(:get, "/getMe")
  end

  def set_webhook(url) when is_binary(url) do
    payload =
      case config()[:webhook_secret] do
        secret when secret in [nil, ""] -> %{url: url}
        secret -> %{url: url, secret_token: secret}
      end

    request(:post, "/setWebhook", json: payload)
  end

  def send_message(chat_id, text, opts \\ []) do
    payload =
      opts
      |> Enum.into(%{})
      |> Map.merge(%{chat_id: chat_id, text: text})

    request(:post, "/sendMessage", json: payload)
  end

  defp request(method, path, req_opts \\ []) do
    with {:ok, token} <- bot_token() do
      url = "#{config()[:api_base_url] || "https://api.telegram.org"}/bot#{token}#{path}"

      case Req.request(Keyword.merge([method: method, url: url], req_opts)) do
        {:ok, %Req.Response{status: status, body: body}} ->
          handle_response(status, body)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp handle_response(status, body) do
    case decode_body(body) do
      %{"ok" => true, "result" => result} when status in 200..299 -> {:ok, result}
      decoded_body -> {:error, {:telegram_api, status, decoded_body}}
    end
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _error -> body
    end
  end

  defp decode_body(body), do: body

  defp bot_token do
    case config()[:bot_token] do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :missing_bot_token}
    end
  end

  defp config do
    Application.get_env(:mmgo, MMGO.Telegram, [])
  end
end
