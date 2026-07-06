defmodule MMGO.AI do
  import Ecto.Query, warn: false

  alias MMGO.AI.{PromptVersions, Request}
  alias MMGO.Repo

  def compile_spell(prompt_payload, opts \\ []) when is_map(prompt_payload) do
    {schema, prompt_payload} = Map.pop(prompt_payload, :schema)

    run(:spell_compile, prompt_payload, opts,
      result_key: :compiled_spell,
      stored_request_payload: Map.put(prompt_payload, :schema, schema),
      response_payload: & &1,
      request_attrs: fn metadata -> %{character_id: metadata["character_id"]} end,
      call: fn provider, payload, call_opts ->
        provider.structured_completion(payload, schema, call_opts)
      end
    )
  end

  def narrate_turn(prompt_payload, opts \\ []) when is_map(prompt_payload) do
    run(:turn_narration, prompt_payload, opts,
      result_key: :narration,
      stored_request_payload: prompt_payload,
      response_payload: &%{"text" => &1},
      request_attrs: fn metadata ->
        %{combat_id: metadata["combat_id"], combat_turn_id: metadata["combat_turn_id"]}
      end,
      call: fn provider, payload, call_opts -> provider.text_completion(payload, call_opts) end
    )
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

  # Generic plumbing shared by every AI use case: resolves the provider and
  # model, invokes the provider callback, and persists an MMGO.AI.Request
  # audit row for both the success and failure paths. Individual use cases
  # (compile_spell, narrate_turn, ...) supply only what differs: which
  # provider callback to call, how to shape the payloads for storage, and
  # which foreign keys to stamp onto the audit row.
  defp run(kind, prompt_payload, opts, config) do
    provider = provider(opts)
    model = model_for(kind, opts)
    prompt_version = Keyword.get(opts, :prompt_version, PromptVersions.for!(kind))
    metadata = normalize_map(Keyword.get(opts, :metadata, %{}))
    started_at = System.monotonic_time(:millisecond)

    result_key = Keyword.fetch!(config, :result_key)
    call = Keyword.fetch!(config, :call)

    base_attrs = %{
      kind: kind,
      provider: provider_name(provider),
      model: model,
      prompt_version: prompt_version,
      request_payload: Keyword.fetch!(config, :stored_request_payload),
      metadata: metadata
    }

    request_attrs =
      Map.merge(base_attrs, Keyword.fetch!(config, :request_attrs).(metadata))

    case call.(provider, prompt_payload, Keyword.put(opts, :model, model)) do
      {:ok, result} ->
        attrs =
          Map.merge(request_attrs, %{
            status: :succeeded,
            response_payload: Keyword.fetch!(config, :response_payload).(result),
            latency_ms: elapsed_ms(started_at)
          })

        with {:ok, ai_request} <- create_request(attrs) do
          {:ok, %{result_key => result, ai_request: ai_request}}
        end

      {:error, reason} ->
        attrs =
          Map.merge(request_attrs, %{
            status: :failed,
            response_payload: %{},
            latency_ms: elapsed_ms(started_at),
            error: inspect(reason)
          })

        with {:ok, _ai_request} <- create_request(attrs) do
          {:error, reason}
        end
    end
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
