defmodule MMGO.AI.Providers.Mock do
  @behaviour MMGO.AI.Provider

  def structured_completion(prompt_payload, _schema, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)

    case decoded_payload["task"] do
      "orchestrate_combat_turn" -> {:ok, mock_orchestration(decoded_payload)}
      "interpret_alchemy" -> {:ok, mock_alchemy(decoded_payload)}
      _other -> {:ok, mock_compiled_spell(decoded_payload)}
    end
  end

  def text_completion(prompt_payload, _opts) do
    decoded_payload = decode_prompt_payload(prompt_payload)
    turn = decoded_payload["turn"] || %{}
    events = decoded_payload["events"] || []
    number = turn["number"] || turn[:number] || 1

    {:ok, "Ход #{number}: рассказчик описал разыгранных событий — #{length(events)}."}
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

  defp mock_orchestration(payload) do
    casts =
      payload
      |> Map.get("casters", [])
      |> Enum.map(fn caster ->
        %{
          "participant_id" => caster["participant_id"],
          "target_participant_id" => caster["target_participant_id"],
          "effects" => caster["allowed_effects"] || []
        }
      end)

    %{
      "casts" => casts,
      "narrative_ru" => "Запечатанные формулы находят дозволенные движком проявления."
    }
  end

  defp mock_alchemy(payload) do
    constraints = payload["engine_constraints"] || %{}
    allowed_states = constraints["allowed_states"] || ["impact"]
    max_intensity = constraints["max_intensity"] || 1
    state = List.first(allowed_states) || "impact"
    restorative? = state in ["regenerating", "empowered", "shielded"]

    %{
      "name" => "Пробный алхимический настой",
      "description" => "Смесь проявляет только свойства выбранных ингредиентов.",
      "targeting" => if(restorative?, do: "self", else: "enemy"),
      "brew_time_game_days" => 1,
      "difficulty" => 1,
      "effects" => [
        %{
          "applies_to" => if(restorative?, do: "caster", else: "target"),
          "state" => state,
          "intensity" => min(max_intensity, 4),
          "variance" => 0,
          "duration" => if(state == "impact", do: 0, else: 1),
          "tags" => ["alchemy", "mock"]
        }
      ]
    }
  end

  defp mock_compiled_spell(decoded_payload) do
    request = decoded_payload["request"] || %{}
    character = decoded_payload["character"] || %{}
    school = request["school"] || request[:school] || "fire"
    formula = request["formula"] || request[:formula] || "Incantatio"
    name = request["name"] || request[:name] || "Безымянное заклинание"
    caster_level = character["level"] || character[:level] || 1

    %{
      "outcome" => "created",
      "name" => name,
      "formula" => formula,
      "school" => school,
      "school_quirk" => mock_school_quirk(school),
      "description" => "Пробное заклинание для локальной разработки и испытаний.",
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
    }
  end

  defp mock_school_quirk("fire"), do: "escalation"
  defp mock_school_quirk("water"), do: "environment_shift"
  defp mock_school_quirk("earth"), do: "persistence"
  defp mock_school_quirk("air"), do: "tempo"
  defp mock_school_quirk("life"), do: "vitality"
  defp mock_school_quirk("death"), do: "harvest"
  defp mock_school_quirk("chaos"), do: "volatility"
  defp mock_school_quirk("order"), do: "precision"
  defp mock_school_quirk(_school), do: nil

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

  defp decode_prompt_payload(%{user_prompt: user_prompt}) when is_binary(user_prompt) do
    case Jason.decode(user_prompt) do
      {:ok, decoded_payload} -> decoded_payload
      _error -> %{}
    end
  end

  defp decode_prompt_payload(prompt_payload) when is_map(prompt_payload), do: prompt_payload
end
