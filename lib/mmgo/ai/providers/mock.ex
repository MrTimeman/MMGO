defmodule MMGO.AI.Providers.Mock do
  @behaviour MMGO.AI.Provider

  def compile_spell(prompt_payload, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)
    request = decoded_payload["request"] || %{}
    character = decoded_payload["character"] || %{}
    school = request["school"] || request[:school] || "fire"
    formula = request["formula"] || request[:formula] || "Incantatio"
    name = request["name"] || request[:name] || humanize_formula(formula)
    caster_level = character["level"] || character[:level] || 1
    spell_type = request["spell_type"] || request[:spell_type] || "active"
    mana_reservation = if spell_type == "passive", do: 18, else: 0
    fatigue_cost = if spell_type == "passive", do: 0, else: 6
    targeting = request["targeting"] || request[:targeting] || default_targeting(spell_type)

    delivery_form =
      request["delivery_form"] || request[:delivery_form] || default_delivery(spell_type)

    {:ok,
     %{
       "name" => name,
       "name_ru" => "Ритуал #{name}",
       "formula" => formula,
       "school" => school,
       "spell_type" => spell_type,
       "mana_reservation" => mana_reservation,
       "description" => "Mock-compiled spell for local development and tests.",
       "level_requirement" => max(div(caster_level, 2), 1),
       "fatigue_cost" => fatigue_cost,
       "cooldown_turns" => 1,
       "targeting" => targeting,
       "delivery_form" => delivery_form,
       "tags" => [school, "compiled"],
       "narrative_tags" => [school, "arcane"],
       "environment_tags" => ["charged-#{school}"],
       "environment_mode" => "add",
       "effects" => default_effects(school, spell_type),
       "interaction_rules" => default_interactions(school),
       "failure_profile" => %{
         "difficulty" => max(div(caster_level, 2), 1),
         "base_success_rate" => 90,
         "partial_success_rate" => 7,
         "backlash_damage" => 2,
         "volatility" => 8
       }
     }}
  end

  def narrate_turn(prompt_payload, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)
    turn = decoded_payload["turn"] || %{}
    events = decoded_payload["events"] || []
    number = turn["number"] || turn[:number] || 1

    {:ok,
     "Ход #{number}: разрешено #{length(events)} событий, и сцена развивается без лишних выдумок."}
  end

  def orchestrate_combat(prompt_payload, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)
    resolutions = decoded_payload["resolutions"] || []

    picks =
      Enum.map(resolutions, fn resolution ->
        outcome_windows = resolution["outcome_windows"] || %{}
        success_max = outcome_windows["success_max"] || 0
        partial_max = outcome_windows["partial_max"] || success_max
        effect_ranges = get_in(resolution, ["outcomes", "success", "effect_ranges"]) || []
        default_outcome = default_outcome(success_max, partial_max)

        %{
          "resolution_id" => resolution["resolution_id"],
          "outcome" => default_outcome,
          "chosen_roll" => midpoint_roll(default_outcome, outcome_windows),
          "effect_picks" =>
            Enum.map(effect_ranges, fn effect_range ->
              %{
                "effect_index" => effect_range["effect_index"],
                "intensity" => midpoint(effect_range["min"], effect_range["max"])
              }
            end)
        }
      end)

    {:ok, %{"picks" => picks, "director_notes" => ["mock-provider deterministic midpoint"]}}
  end

  def tick_dungeon(prompt_payload, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)
    floors = decoded_payload["floors"] || []
    state = decoded_payload["state"] || %{}
    activity_window = decoded_payload["activity_window"] || %{}
    pressure_level = state["pressure_level"] || 0
    recent_moves = activity_window["recent_moves"] || 0

    directives =
      Enum.map(floors, fn floor ->
        %{
          "floor_id" => floor["id"],
          "threat_delta" => clamp(div(pressure_level + recent_moves, 20), -5, 5),
          "resource_delta" => clamp(-div(pressure_level, 25), -5, 5),
          "connection_shift" => if(pressure_level >= 50, do: "block", else: "stabilize"),
          "anomaly_tag" => if(pressure_level >= 60, do: "volatile", else: "none")
        }
      end)

    {:ok,
     %{
       "floor_directives" => directives,
       "summary" => "Mock dungeon director applied bounded maintenance pressure."
     }}
  end

  defp default_effects("water", "utility") do
    [
      %{
        "applies_to" => "environment",
        "state" => "revealed",
        "intensity" => 1,
        "variance" => 0,
        "duration" => 2
      }
    ]
  end

  defp default_effects(_school, "passive") do
    [
      %{
        "applies_to" => "caster",
        "state" => "shielded",
        "intensity" => 8,
        "variance" => 1,
        "duration" => 3
      }
    ]
  end

  defp default_effects("water", _spell_type) do
    [
      %{
        "applies_to" => "target",
        "state" => "impact",
        "intensity" => 10,
        "variance" => 2,
        "duration" => 0
      },
      %{
        "applies_to" => "target",
        "state" => "frozen",
        "intensity" => 4,
        "variance" => 0,
        "duration" => 1
      }
    ]
  end

  defp default_effects(_school, "utility") do
    [
      %{
        "applies_to" => "environment",
        "state" => "revealed",
        "intensity" => 1,
        "variance" => 0,
        "duration" => 2
      }
    ]
  end

  defp default_effects(_school, _spell_type) do
    [
      %{
        "applies_to" => "target",
        "state" => "impact",
        "intensity" => 12,
        "variance" => 2,
        "duration" => 0
      },
      %{
        "applies_to" => "target",
        "state" => "burning",
        "intensity" => 4,
        "variance" => 1,
        "duration" => 2
      }
    ]
  end

  defp default_interactions("water") do
    [
      %{
        "trigger_type" => "environment_tag",
        "trigger" => "burning",
        "outcome" => "negate",
        "modifier" => 0
      }
    ]
  end

  defp default_interactions(_school) do
    [
      %{
        "trigger_type" => "environment_tag",
        "trigger" => "wet",
        "outcome" => "negate",
        "modifier" => 0
      }
    ]
  end

  defp default_targeting("utility"), do: "zone"
  defp default_targeting("passive"), do: "self"
  defp default_targeting(_spell_type), do: "enemy"

  defp default_delivery("utility"), do: "zone"
  defp default_delivery("passive"), do: "self"
  defp default_delivery(_spell_type), do: "sphere"

  defp default_outcome(success_max, partial_max) do
    cond do
      success_max >= 50 -> "success"
      partial_max >= 50 -> "partial"
      true -> "failure"
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

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp humanize_formula(formula) do
    formula
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp decode_prompt_payload(%{user_prompt: user_prompt}) when is_binary(user_prompt) do
    case Jason.decode(user_prompt) do
      {:ok, decoded_payload} -> decoded_payload
      _error -> %{}
    end
  end

  defp decode_prompt_payload(prompt_payload) when is_map(prompt_payload), do: prompt_payload
end
