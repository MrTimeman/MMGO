defmodule MMGO.AI.Providers.Gemini do
  @behaviour MMGO.AI.Provider

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
      request_body(prompt_payload, %{
        responseMimeType: "application/json",
        responseSchema: prompt_payload.schema,
        temperature: temperature
      })

    with {:ok, response} <- request(model, body),
         {:ok, text} <- extract_text(response),
         {:ok, decoded} <- Jason.decode(text) do
      {:ok, decoded}
    else
      {:error, _reason} = error -> error
    end
  end

  defp request_text(model, prompt_payload, temperature) do
    body =
      request_body(prompt_payload, %{
        responseMimeType: "text/plain",
        temperature: temperature
      })

    with {:ok, response} <- request(model, body),
         {:ok, text} <- extract_text(response) do
      {:ok, String.trim(text)}
    end
  end

  defp request_body(prompt_payload, generation_config) do
    %{
      systemInstruction: %{
        role: "system",
        parts: [%{text: prompt_payload.system_prompt}]
      },
      contents: [
        %{
          role: "user",
          parts: [%{text: prompt_payload.user_prompt}]
        }
      ],
      generationConfig: generation_config
    }
  end

  defp request(model, body) do
    with {:ok, api_key} <- api_key() do
      url =
        "#{config()[:api_base_url] || "https://generativelanguage.googleapis.com/v1beta"}/models/#{model}:generateContent"

      case Req.post(url,
             json: body,
             headers: [{"x-goog-api-key", api_key}],
             receive_timeout: 60_000,
             connect_options: [timeout: 15_000]
           ) do
        {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
          {:ok, decode_body(response_body)}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          {:error, {:gemini_api, status, decode_body(response_body)}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp extract_text(%{"candidates" => [%{"content" => %{"parts" => parts}} | _rest]}) do
    text =
      parts
      |> Enum.map_join("", fn part -> Map.get(part, "text", "") end)
      |> String.trim()

    if text == "" do
      {:error, :empty_response}
    else
      {:ok, text}
    end
  end

  defp extract_text(_response), do: {:error, :invalid_response}

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
