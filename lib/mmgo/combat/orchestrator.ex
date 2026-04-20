defmodule MMGO.Combat.Orchestrator do
  require Logger

  alias MMGO.AI
  alias MMGO.AI.Prompts.CombatOrchestratorPrompt
  alias MMGO.Combat.{Combat, Turn}

  def finalize_resolution(%Combat{} = combat, %Turn{} = turn, resolution, opts \\ [])
      when is_map(resolution) do
    if Keyword.get(opts, :orchestrate, false) do
      prompt_payload =
        CombatOrchestratorPrompt.build(%{
          combat: combat_payload(combat),
          turn: turn_payload(turn),
          resolutions: [resolution]
        })

      ai_opts =
        opts
        |> Keyword.put_new(:metadata, %{
          combat_id: combat.id,
          combat_turn_id: turn.id,
          turn_number: turn.number,
          resolution_id: resolution["resolution_id"]
        })

      case AI.orchestrate_combat(prompt_payload, ai_opts) do
        {:ok, %{directives: %{"picks" => [pick | _rest]}}} ->
          case validate_pick(resolution, pick) do
            {:ok, validated_pick} ->
              Map.put(validated_pick, "orchestration_mode", "ai")

            {:error, reason} ->
              emit_range_violation(combat, turn, resolution, reason)
              fallback_pick(combat, resolution, "range_violation")
          end

        {:ok, %{directives: directives}} ->
          emit_range_violation(combat, turn, resolution, {:missing_picks, directives})
          fallback_pick(combat, resolution, "range_violation")

        {:error, reason} ->
          emit_fallback(combat, turn, resolution, reason)
          fallback_pick(combat, resolution, "provider_failure")
      end
    else
      fallback_pick(combat, resolution, "deterministic_midpoint")
    end
  end

  defp validate_pick(resolution, pick) when is_map(pick) do
    outcome = pick["outcome"]
    chosen_roll = pick["chosen_roll"]
    effect_picks = pick["effect_picks"] || []

    with :ok <- validate_resolution_id(resolution, pick["resolution_id"]),
         :ok <- validate_outcome(outcome),
         :ok <- validate_roll(outcome, chosen_roll, resolution["outcome_windows"] || %{}),
         :ok <- validate_effect_picks(outcome, effect_picks, resolution) do
      {:ok,
       %{
         "resolution_id" => pick["resolution_id"],
         "outcome" => outcome,
         "chosen_roll" => chosen_roll,
         "effect_picks" => Enum.sort_by(effect_picks, & &1["effect_index"])
       }}
    end
  end

  defp validate_pick(_resolution, _pick), do: {:error, :invalid_pick_shape}

  defp validate_resolution_id(resolution, resolution_id) do
    if resolution_id == resolution["resolution_id"],
      do: :ok,
      else: {:error, :resolution_id_mismatch}
  end

  defp validate_outcome(outcome) when outcome in ["success", "partial", "failure"], do: :ok
  defp validate_outcome(_outcome), do: {:error, :invalid_outcome}

  defp validate_roll("success", chosen_roll, %{"success_max" => success_max})
       when is_integer(chosen_roll) and chosen_roll >= 1 and chosen_roll <= success_max,
       do: :ok

  defp validate_roll(
         "partial",
         chosen_roll,
         %{"success_max" => success_max, "partial_max" => partial_max}
       )
       when is_integer(chosen_roll) and chosen_roll > success_max and chosen_roll <= partial_max,
       do: :ok

  defp validate_roll(
         "failure",
         chosen_roll,
         %{"partial_max" => partial_max, "failure_max" => failure_max}
       )
       when is_integer(chosen_roll) and chosen_roll > partial_max and chosen_roll <= failure_max,
       do: :ok

  defp validate_roll(_outcome, _chosen_roll, _windows), do: {:error, :invalid_roll_window}

  defp validate_effect_picks("failure", effect_picks, _resolution) do
    if effect_picks == [], do: :ok, else: {:error, :failure_pick_must_not_have_effects}
  end

  defp validate_effect_picks(outcome, effect_picks, resolution) do
    effect_ranges = get_in(resolution, ["outcomes", outcome, "effect_ranges"]) || []

    cond do
      not Enum.all?(effect_picks, &valid_effect_pick?/1) ->
        {:error, :invalid_effect_pick_shape}

      true ->
        pick_indexes = MapSet.new(effect_picks, & &1["effect_index"])
        range_indexes = MapSet.new(effect_ranges, & &1["effect_index"])

        cond do
          pick_indexes != range_indexes ->
            {:error, :effect_pick_indexes_mismatch}

          Enum.any?(effect_picks, &effect_pick_out_of_range?(&1, effect_ranges)) ->
            {:error, :effect_pick_out_of_range}

          true ->
            :ok
        end
    end
  end

  defp valid_effect_pick?(%{"effect_index" => effect_index, "intensity" => intensity})
       when is_integer(effect_index) and is_integer(intensity),
       do: true

  defp valid_effect_pick?(_pick), do: false

  defp effect_pick_out_of_range?(pick, effect_ranges) do
    case Enum.find(effect_ranges, &(&1["effect_index"] == pick["effect_index"])) do
      %{"min" => min, "max" => max} ->
        pick["intensity"] < min or pick["intensity"] > max

      nil ->
        true
    end
  end

  defp fallback_pick(combat, resolution, reason) do
    outcome = midpoint_outcome(combat, resolution)
    effect_ranges = get_in(resolution, ["outcomes", outcome, "effect_ranges"]) || []

    %{
      "resolution_id" => resolution["resolution_id"],
      "outcome" => outcome,
      "chosen_roll" => midpoint_roll(outcome, resolution["outcome_windows"] || %{}),
      "effect_picks" =>
        Enum.map(effect_ranges, fn effect_range ->
          %{
            "effect_index" => effect_range["effect_index"],
            "intensity" => midpoint(effect_range["min"], effect_range["max"])
          }
        end),
      "orchestration_mode" => "fallback",
      "fallback_reason" => reason
    }
  end

  defp midpoint_outcome(%Combat{} = combat, resolution) do
    windows = resolution["outcome_windows"] || %{}
    success_max = windows["success_max"] || 0
    partial_max = windows["partial_max"] || 0
    target_side = resolution["target_side"]
    target_hp = get_in(combat.sides || %{}, [target_side, "shared_hp"]) || 100

    max_success_damage =
      resolution
      |> get_in(["outcomes", "success", "effect_ranges"])
      |> Kernel.||([])
      |> Enum.reduce(0, fn range, total -> total + (range["max"] || 0) end)

    cond do
      target_hp <= max_success_damage and success_max > 0 ->
        "success"

      combat.kind in [:dungeon_encounter, "dungeon_encounter"] and success_max >= 35 ->
        "success"

      combat.kind in [:dungeon_encounter, "dungeon_encounter"] and partial_max > 0 ->
        "partial"

      combat.kind in [:duel, "duel"] and success_max >= 45 ->
        "success"

      partial_max >= 50 ->
        "partial"

      success_max > 0 ->
        "success"

      true ->
        "failure"
    end
  end

  defp midpoint_roll("success", %{"success_max" => success_max}),
    do: midpoint(1, max(success_max, 1))

  defp midpoint_roll("partial", %{"success_max" => success_max, "partial_max" => partial_max}),
    do: midpoint(success_max + 1, max(partial_max, success_max + 1))

  defp midpoint_roll("failure", %{"partial_max" => partial_max, "failure_max" => failure_max}),
    do: midpoint(partial_max + 1, max(failure_max, partial_max + 1))

  defp midpoint_roll(_outcome, _windows), do: 50

  defp midpoint(min, max) when is_integer(min) and is_integer(max), do: div(min + max, 2)

  defp emit_range_violation(combat, turn, resolution, reason) do
    metadata = %{
      combat_id: combat.id,
      combat_turn_id: turn.id,
      turn_number: turn.number,
      resolution_id: resolution["resolution_id"],
      reason: inspect(reason)
    }

    :telemetry.execute([:mmgo, :combat, :orchestrator, :range_violation], %{count: 1}, metadata)

    Logger.warning(
      "combat orchestrator returned invalid picks for #{resolution["resolution_id"]}: #{inspect(reason)}"
    )
  end

  defp emit_fallback(combat, turn, resolution, reason) do
    metadata = %{
      combat_id: combat.id,
      combat_turn_id: turn.id,
      turn_number: turn.number,
      resolution_id: resolution["resolution_id"],
      reason: inspect(reason)
    }

    :telemetry.execute([:mmgo, :combat, :orchestrator, :fallback], %{count: 1}, metadata)

    Logger.warning(
      "combat orchestrator fell back to deterministic midpoint for #{resolution["resolution_id"]}: #{inspect(reason)}"
    )
  end

  defp combat_payload(%Combat{} = combat) do
    %{
      id: combat.id,
      kind: combat.kind,
      turn_number: combat.turn_number,
      environment_tags: combat.environment_tags,
      sides: combat.sides,
      metadata: combat.metadata || %{}
    }
  end

  defp turn_payload(%Turn{} = turn) do
    %{
      id: turn.id,
      number: turn.number,
      status: turn.status,
      resolution: turn.resolution || %{}
    }
  end
end
