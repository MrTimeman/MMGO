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

    {:ok,
     %{
       "name" => name,
       "formula" => formula,
       "school" => school,
       "description" => "Mock-compiled spell for local development and tests.",
       "level_requirement" => max(div(caster_level, 2), 1),
       "fatigue_cost" => 6,
       "cooldown_turns" => 1,
       "targeting" => request["targeting"] || request[:targeting] || "enemy",
       "delivery_form" => request["delivery_form"] || request[:delivery_form] || "sphere",
       "tags" => [school, "compiled"],
       "narrative_tags" => [school, "arcane"],
       "environment_tags" => ["charged-#{school}"],
       "environment_mode" => "add",
       "effects" => default_effects(school),
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
     "Turn #{number} unfolds through #{length(events)} resolved events in the mock storyteller."}
  end

  defp default_effects("water") do
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

  defp default_effects(_school) do
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
