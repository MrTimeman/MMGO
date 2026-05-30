defmodule MMGO.AI.Providers.DeepSeek do
  @behaviour MMGO.AI.Provider

  @api_base "https://api.deepseek.com/v1"
  @spell_model "deepseek-chat"
  @narration_model "deepseek-chat"

  def compile_spell(prompt_payload, opts) do
    model = Keyword.get(opts, :model, @spell_model)

    schema_hint =
      case Map.get(prompt_payload, :schema) do
        nil -> ""
        schema -> "\n\nYou MUST return a JSON object matching this exact schema:\n#{Jason.encode!(schema, pretty: true)}"
      end

    body = %{
      model: model,
      messages: [
        %{role: "system", content: prompt_payload.system_prompt <> schema_hint},
        %{role: "user", content: prompt_payload.user_prompt}
      ],
      response_format: %{type: "json_object"},
      temperature: 0.3
    }

    with {:ok, text} <- chat(body),
         {:ok, decoded} <- Jason.decode(text) do
      {:ok, decoded}
    end
  end

  def narrate_turn(prompt_payload, opts) do
    model = Keyword.get(opts, :model, @narration_model)

    body = %{
      model: model,
      messages: [
        %{role: "system", content: prompt_payload.system_prompt},
        %{role: "user", content: prompt_payload.user_prompt}
      ],
      temperature: 0.7
    }

    with {:ok, text} <- chat(body) do
      {:ok, String.trim(text)}
    end
  end

  defp chat(body) do
    with {:ok, api_key} <- api_key() do
      url = "#{@api_base}/chat/completions"

      case Req.post(url,
             json: body,
             headers: [{"authorization", "Bearer #{api_key}"}]
           ) do
        {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
          extract_text(decode_body(response_body))

        {:ok, %Req.Response{status: status, body: response_body}} ->
          {:error, {:deepseek_api, status, decode_body(response_body)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_text(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_text(_), do: {:error, :invalid_response}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp decode_body(body), do: body

  defp api_key do
    case config()[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp config, do: Application.get_env(:mmgo, __MODULE__, [])
end
