defmodule MMGO.AI do
  import Ecto.Query, warn: false

  alias MMGO.AI.{PromptVersions, Request}
  alias MMGO.Repo

  def compile_spell(prompt_payload, opts \\ []) when is_map(prompt_payload) do
    provider = provider(opts)
    model = model_for(:spell_compile, opts)
    prompt_version = Keyword.get(opts, :prompt_version, PromptVersions.for!(:spell_compile))
    metadata = normalize_map(Keyword.get(opts, :metadata, %{}))
    started_at = System.monotonic_time(:millisecond)

    case provider.compile_spell(prompt_payload, Keyword.put(opts, :model, model)) do
      {:ok, compiled_spell} ->
        ai_request_attrs = %{
          kind: :spell_compile,
          status: :succeeded,
          provider: provider_name(provider),
          model: model,
          prompt_version: prompt_version,
          request_payload: prompt_payload,
          response_payload: compiled_spell,
          latency_ms: elapsed_ms(started_at),
          metadata: metadata,
          character_id: metadata["character_id"]
        }

        with {:ok, ai_request} <- create_request(ai_request_attrs) do
          {:ok, %{compiled_spell: compiled_spell, ai_request: ai_request}}
        end

      {:error, reason} ->
        ai_request_attrs = %{
          kind: :spell_compile,
          status: :failed,
          provider: provider_name(provider),
          model: model,
          prompt_version: prompt_version,
          request_payload: prompt_payload,
          response_payload: %{},
          latency_ms: elapsed_ms(started_at),
          error: inspect(reason),
          metadata: metadata,
          character_id: metadata["character_id"]
        }

        with {:ok, _ai_request} <- create_request(ai_request_attrs) do
          {:error, reason}
        end
    end
  end

  def narrate_turn(prompt_payload, opts \\ []) when is_map(prompt_payload) do
    provider = provider(opts)
    model = model_for(:turn_narration, opts)
    prompt_version = Keyword.get(opts, :prompt_version, PromptVersions.for!(:turn_narration))
    metadata = normalize_map(Keyword.get(opts, :metadata, %{}))
    started_at = System.monotonic_time(:millisecond)

    case provider.narrate_turn(prompt_payload, Keyword.put(opts, :model, model)) do
      {:ok, narration} ->
        ai_request_attrs = %{
          kind: :turn_narration,
          status: :succeeded,
          provider: provider_name(provider),
          model: model,
          prompt_version: prompt_version,
          request_payload: prompt_payload,
          response_payload: %{"text" => narration},
          latency_ms: elapsed_ms(started_at),
          metadata: metadata,
          combat_id: metadata["combat_id"],
          combat_turn_id: metadata["combat_turn_id"]
        }

        with {:ok, ai_request} <- create_request(ai_request_attrs) do
          {:ok, %{narration: narration, ai_request: ai_request}}
        end

      {:error, reason} ->
        ai_request_attrs = %{
          kind: :turn_narration,
          status: :failed,
          provider: provider_name(provider),
          model: model,
          prompt_version: prompt_version,
          request_payload: prompt_payload,
          response_payload: %{},
          latency_ms: elapsed_ms(started_at),
          error: inspect(reason),
          metadata: metadata,
          combat_id: metadata["combat_id"],
          combat_turn_id: metadata["combat_turn_id"]
        }

        with {:ok, _ai_request} <- create_request(ai_request_attrs) do
          {:error, reason}
        end
    end
  end

  def update_request(%Request{} = request, attrs) when is_map(attrs) do
    request
    |> Request.changeset(attrs)
    |> Repo.update()
  end

  def list_requests(kind \\ nil) do
    query =
      case kind do
        nil -> Request
        kind -> from request in Request, where: request.kind == ^kind
      end

    Repo.all(from request in query, order_by: [desc: request.inserted_at])
  end

  defp create_request(attrs) do
    %Request{}
    |> Request.changeset(attrs)
    |> Repo.insert()
  end

  defp provider(opts) do
    Keyword.get(opts, :provider, Application.fetch_env!(:mmgo, __MODULE__)[:default_provider])
  end

  defp model_for(kind, opts) do
    Keyword.get(opts, :model, Application.fetch_env!(:mmgo, __MODULE__)[:models][kind])
  end

  defp provider_name(provider), do: provider |> Module.split() |> Enum.join(".")

  defp elapsed_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
