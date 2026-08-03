defmodule MMGO.Combat.Orchestrator do
  @moduledoc """
  Bounded runtime-AI orchestration for already sealed combat casts.

  Combat mechanics remain deterministic: the engine applies the immutable
  action snapshots first. This module records a second, provider-audited
  manifestation of those same permitted effects for narration. A provider is
  never allowed to add a state, target, cost, reward, or HP value; malformed
  output is replaced by a deterministic Russian fallback and retained only as
  a failed audit record.
  """

  import Ecto.Query, warn: false

  alias MMGO.AI
  alias MMGO.AI.Prompts.CombatTurnPrompt
  alias MMGO.Combat, as: CombatContext
  alias MMGO.Combat.{Action, ActionSnapshot, Turn}
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Repo
  alias MMGO.Spells.SpellEffect

  @orchestration_key "orchestration"

  @doc """
  Stores an immutable bounded orchestration record for a resolved turn.

  The provider call happens outside the database lock. A retry sees the stored
  artifact and returns it instead of issuing another request or changing any
  combat mechanics.
  """
  def orchestrate_turn(combat_id, turn_id, opts \\ [])

  def orchestrate_turn(combat_id, turn_id, opts)
      when is_binary(combat_id) and is_binary(turn_id) and is_list(opts) do
    with %Turn{combat_id: ^combat_id, status: :resolved} = turn <- Repo.get(Turn, turn_id) do
      case existing_orchestration(turn) do
        %{} ->
          {:ok, turn}

        nil ->
          combat = CombatContext.get_combat!(combat_id)
          actions = actions_for_turn(turn.id)
          envelope = build_envelope(combat, turn, actions)
          artifact = build_artifact(envelope, combat, turn, opts)
          persist_artifact(turn.id, artifact)
      end
    else
      nil -> {:error, :turn_not_found}
      %Turn{} -> {:error, :turn_not_resolved}
    end
  end

  def orchestrate_turn(_combat_id, _turn_id, _opts), do: {:error, :turn_not_found}

  @doc false
  def build_envelope(%CombatSchema{} = combat, %Turn{} = turn, actions) when is_list(actions) do
    participants_by_id = Map.new(combat.participants, &{&1.id, &1})

    casters =
      actions
      |> Enum.filter(&(&1.action_type == :cast_spell))
      |> Enum.sort_by(& &1.participant_id)
      |> bounded_casters(participants_by_id)

    %{
      "task" => "orchestrate_combat_turn",
      "combat" => %{
        "id" => combat.id,
        "kind" => to_string(combat.kind),
        "turn_number" => turn.number,
        "environment_tags" => combat.environment_tags || [],
        "sides" => combat.sides
      },
      "turn" => %{
        "id" => turn.id,
        "number" => turn.number,
        "resolution_token" => lifecycle_token(turn)
      },
      "state_primitives" => SpellEffect.supported_states(),
      "casters" => casters
    }
  end

  defp actions_for_turn(turn_id) do
    Repo.all(
      from action in Action,
        where: action.combat_turn_id == ^turn_id,
        order_by: [asc: action.participant_id]
    )
  end

  # This work is intentionally pure: async tasks only shape already-persisted
  # snapshots and never hold a database connection or a turn lock.
  defp bounded_casters(actions, participants_by_id) do
    actions
    |> Task.async_stream(
      fn action -> caster_envelope(action, participants_by_id) end,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce([], fn
      {:ok, {:ok, caster}}, acc -> [caster | acc]
      {:ok, {:error, _reason}}, acc -> acc
      {:exit, _reason}, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp caster_envelope(action, participants_by_id) do
    with {:ok, resolved_action, spell} <- ActionSnapshot.cast_for_resolution(action),
         %{combat_level: level, active_states: active_states} <-
           Map.get(participants_by_id, action.participant_id) do
      {:ok,
       %{
         "participant_id" => action.participant_id,
         "target_participant_id" => resolved_action.target_participant_id,
         "target_side" => resolved_action.target_side,
         "spell_id" => spell.id,
         "formula" => spell.formula,
         "incantation_slots" => spell.incantation_slots || %{},
         "school" => to_string(spell.school),
         "caster_level" => level,
         "active_states" => Enum.map(active_states || [], &Map.get(&1, "state")),
         "allowed_effects" =>
           Enum.map(spell.effects, fn effect ->
             %{
               "applies_to" => to_string(effect.applies_to),
               "state" => effect.state,
               "intensity" => effect.intensity,
               "duration" => effect.duration
             }
           end),
         "fatigue_cost" => spell.fatigue_cost,
         "cooldown_turns" => spell.cooldown_turns
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp build_artifact(%{"casters" => []} = envelope, _combat, _turn, _opts) do
    fallback_artifact(envelope, :no_spell_casts)
  end

  defp build_artifact(envelope, combat, turn, opts) do
    prompt = CombatTurnPrompt.build(envelope)

    ai_opts =
      opts
      |> Keyword.put(:metadata, %{combat_id: combat.id, combat_turn_id: turn.id})

    case AI.orchestrate_turn(prompt, ai_opts) do
      {:ok, %{orchestration: result, ai_request: ai_request}} ->
        case validate_result(result, envelope) do
          {:ok, validated} ->
            %{
              "source" => "provider",
              "envelope" => envelope,
              "result" => validated,
              "ai_request_id" => ai_request.id
            }

          {:error, reason} ->
            _ = AI.update_request(ai_request, %{status: :failed, error: inspect(reason)})
            fallback_artifact(envelope, reason)
        end

      {:error, reason} ->
        fallback_artifact(envelope, reason)
    end
  end

  defp validate_result(result, %{"casters" => casters})
       when is_map(result) and is_list(casters) do
    with casts when is_list(casts) <- Map.get(result, "casts"),
         narrative when is_binary(narrative) <- Map.get(result, "narrative_ru"),
         trimmed_narrative = String.trim(narrative),
         true <- byte_size(trimmed_narrative) in 1..1_200,
         {:ok, normalized_casts} <- validate_casts(casts, casters) do
      {:ok, %{"casts" => normalized_casts, "narrative_ru" => trimmed_narrative}}
    else
      _other -> {:error, :invalid_provider_result}
    end
  end

  defp validate_result(_result, _envelope), do: {:error, :invalid_provider_result}

  defp validate_casts(casts, allowed_casters) do
    allowed_by_participant = Map.new(allowed_casters, &{&1["participant_id"], &1})

    with true <- length(casts) == map_size(allowed_by_participant),
         {:ok, normalized_casts} <-
           map_all(casts, fn cast -> validate_cast(cast, allowed_by_participant) end),
         true <-
           normalized_casts
           |> Enum.map(& &1["participant_id"])
           |> MapSet.new()
           |> MapSet.equal?(MapSet.new(Map.keys(allowed_by_participant))) do
      {:ok, Enum.sort_by(normalized_casts, & &1["participant_id"])}
    else
      _other -> {:error, :invalid_provider_result}
    end
  end

  defp validate_cast(cast, allowed_by_participant) when is_map(cast) do
    with participant_id when is_binary(participant_id) <- Map.get(cast, "participant_id"),
         allowed when is_map(allowed) <- Map.get(allowed_by_participant, participant_id),
         true <- Map.get(cast, "target_participant_id") == allowed["target_participant_id"],
         effects when is_list(effects) <- Map.get(cast, "effects"),
         {:ok, normalized_effects} <- validate_effects(effects, allowed["allowed_effects"]) do
      {:ok,
       %{
         "participant_id" => participant_id,
         "target_participant_id" => allowed["target_participant_id"],
         "effects" => normalized_effects
       }}
    else
      _other -> {:error, :invalid_provider_result}
    end
  end

  defp validate_cast(_cast, _allowed), do: {:error, :invalid_provider_result}

  defp validate_effects(effects, allowed_effects) when is_list(allowed_effects) do
    map_all(effects, fn effect -> validate_effect(effect, allowed_effects) end)
  end

  defp validate_effects(_effects, _allowed_effects), do: {:error, :invalid_provider_result}

  defp validate_effect(effect, allowed_effects) when is_map(effect) do
    with applies_to when is_binary(applies_to) <- Map.get(effect, "applies_to"),
         state when is_binary(state) <- Map.get(effect, "state"),
         true <- state in SpellEffect.supported_states(),
         intensity when is_integer(intensity) and intensity >= 0 <- Map.get(effect, "intensity"),
         duration when is_integer(duration) and duration >= 0 <- Map.get(effect, "duration"),
         %{} = allowed_effect <-
           Enum.find(allowed_effects, fn candidate ->
             candidate["applies_to"] == applies_to and candidate["state"] == state and
               intensity <= candidate["intensity"] and duration <= candidate["duration"]
           end) do
      _ = allowed_effect

      {:ok,
       %{
         "applies_to" => applies_to,
         "state" => state,
         "intensity" => intensity,
         "duration" => duration
       }}
    else
      _other -> {:error, :invalid_provider_result}
    end
  end

  defp validate_effect(_effect, _allowed_effects), do: {:error, :invalid_provider_result}

  defp fallback_artifact(envelope, reason) do
    %{
      "source" => "fallback",
      "fallback_reason" => inspect(reason),
      "envelope" => envelope,
      "result" => %{
        "casts" =>
          Enum.map(envelope["casters"], fn caster ->
            %{
              "participant_id" => caster["participant_id"],
              "target_participant_id" => caster["target_participant_id"],
              "effects" => caster["allowed_effects"]
            }
          end),
        "narrative_ru" => fallback_narrative(envelope)
      }
    }
  end

  defp fallback_narrative(%{"turn" => %{"number" => turn_number}, "casters" => casters}) do
    "Ход #{turn_number}: движок применяет #{length(casters)} запечатанных магических проявления по сохранённым границам."
  end

  defp persist_artifact(turn_id, artifact) do
    Repo.transaction(fn ->
      turn =
        Turn
        |> where([turn], turn.id == ^turn_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      case existing_orchestration(turn) do
        %{} ->
          turn

        nil ->
          resolution = Map.put(turn.resolution || %{}, @orchestration_key, artifact)
          turn |> Turn.changeset(%{resolution: resolution}) |> Repo.update!()
      end
    end)
  end

  defp existing_orchestration(%Turn{resolution: resolution}) when is_map(resolution) do
    case Map.get(resolution, @orchestration_key) do
      %{} = artifact -> artifact
      _other -> nil
    end
  end

  defp existing_orchestration(_turn), do: nil

  defp lifecycle_token(%Turn{resolution: resolution}) when is_map(resolution) do
    resolution
    |> Map.get("lifecycle", %{})
    |> Map.get("resolution_token")
  end

  defp lifecycle_token(_turn), do: nil

  defp map_all(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} -> {:halt, {:error, :invalid_provider_result}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end
end
