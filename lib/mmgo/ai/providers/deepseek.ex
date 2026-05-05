defmodule MMGO.AI.Providers.DeepSeek do
  @behaviour MMGO.AI.Provider

  @default_base_url "https://api.deepseek.com"
  @default_max_tokens 4096

  def compile_spell(prompt_payload, opts) do
    model = Keyword.fetch!(opts, :model)
    request_json(model, prompt_payload, 0.3)
  end

  def narrate_turn(prompt_payload, opts) do
    model = Keyword.fetch!(opts, :model)
    request_text(model, prompt_payload, 0.7)
  end

  def orchestrate_combat(prompt_payload, opts) do
    model = Keyword.fetch!(opts, :model)
    request_json(model, prompt_payload, 0.4)
  end

  def tick_dungeon(prompt_payload, opts) do
    model = Keyword.fetch!(opts, :model)
    request_json(model, prompt_payload, 0.5)
  end

  defp request_json(model, prompt_payload, temperature) do
    body =
      request_body(model, prompt_payload, temperature,
        response_format: %{type: "json_object"},
        system_suffix: json_schema_suffix(prompt_payload),
        force_disable_thinking: true
      )

    with {:ok, response} <- request(body),
         {:ok, text} <- extract_content(response),
         {:ok, decoded} <- Jason.decode(text) do
      {:ok, decoded}
    else
      {:error, _reason} = error -> error
    end
  end

  defp request_text(model, prompt_payload, temperature) do
    body = request_body(model, prompt_payload, temperature)

    with {:ok, response} <- request(body),
         {:ok, text} <- extract_content(response) do
      {:ok, String.trim(text)}
    end
  end

  defp request_body(model, prompt_payload, temperature, opts \\ []) do
    base_body = %{
      model: model,
      messages: [
        %{role: "system", content: system_prompt(prompt_payload, opts[:system_suffix])},
        %{role: "user", content: prompt_payload.user_prompt}
      ],
      temperature: temperature,
      stream: false,
      max_tokens: config()[:max_tokens] || @default_max_tokens
    }

    base_body
    |> maybe_put(:response_format, opts[:response_format])
    |> maybe_put(:thinking, thinking_config(opts))
    |> maybe_put(:reasoning_effort, config()[:reasoning_effort])
  end

  defp request(body) do
    with {:ok, api_key} <- api_key() do
      url =
        "#{String.trim_trailing(config()[:api_base_url] || @default_base_url, "/")}/chat/completions"

      case Req.post(url,
             json: body,
             headers: [
               {"authorization", "Bearer #{api_key}"},
               {"content-type", "application/json"}
             ],
             receive_timeout: 120_000,
             connect_options: [timeout: 15_000]
           ) do
        {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
          {:ok, decode_body(response_body)}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          {:error, {:deepseek_api, status, decode_body(response_body)}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _rest]})
       when is_binary(content) do
    text = String.trim(content)

    if text == "" do
      {:error, :empty_response}
    else
      {:ok, text}
    end
  end

  defp extract_content(_response), do: {:error, :invalid_response}

  defp system_prompt(prompt_payload, nil), do: prompt_payload.system_prompt

  defp system_prompt(prompt_payload, suffix) do
    [prompt_payload.system_prompt, suffix]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp json_schema_suffix(%{schema: schema}) when is_map(schema) do
    """
    Return valid JSON only. Match this JSON Schema as closely as possible:
    #{Jason.encode!(schema)}
    """
    |> String.trim()
  end

  defp json_schema_suffix(_prompt_payload), do: "Return valid JSON only."

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp thinking_config(opts) do
    cond do
      opts[:force_disable_thinking] -> %{type: "disabled"}
      true ->
        case config()[:thinking] do
          value when value in ["enabled", "disabled"] -> %{type: value}
          _ -> nil
        end
    end
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _error -> body
    end
  end

  defp decode_body(body), do: body

  defp api_key do
    case config()[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp config do
    Application.get_env(:mmgo, __MODULE__, [])
  end
end
