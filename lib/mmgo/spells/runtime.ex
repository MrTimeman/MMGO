defmodule MMGO.Spells.Runtime do
  alias MMGO.Spells.{InteractionRule, Spell, SpellEffect}

  def success_rate(%Spell{failure_profile: failure_profile}, caster_level, fatigue_penalty \\ 0) do
    (failure_profile.base_success_rate + (caster_level - failure_profile.difficulty) * 3 -
       fatigue_penalty)
    |> clamp(5, 99)
  end

  def environment_outcome(%Spell{} = spell, environment_tags) do
    spell.interaction_rules
    |> Enum.filter(&match_environment_rule?(&1, environment_tags))
    |> Enum.reduce(
      %{
        negated?: false,
        intensity_bonus: 0,
        replacement_tags: nil,
        spread_tags: [],
        bonus_states: []
      },
      fn rule, acc ->
        case rule.outcome do
          :negate -> %{acc | negated?: true}
          :amplify -> %{acc | intensity_bonus: acc.intensity_bonus + rule.modifier}
          :replace_environment -> %{acc | replacement_tags: rule.replacement_tags}
          :spread -> %{acc | spread_tags: Enum.uniq(acc.spread_tags ++ rule.replacement_tags)}
          :transform -> %{acc | replacement_tags: rule.replacement_tags}
          :apply_bonus_state -> %{acc | bonus_states: [bonus_state(rule) | acc.bonus_states]}
        end
      end
    )
  end

  def periodic_state?(state), do: state in ["burning", "regenerating"]

  def instant_state?(state), do: state == "impact"

  defp match_environment_rule?(
         %InteractionRule{trigger_type: :environment_tag, trigger: trigger},
         tags
       ) do
    trigger in tags
  end

  defp match_environment_rule?(_rule, _tags), do: false

  defp bonus_state(rule) do
    %SpellEffect{
      applies_to: :target,
      state: rule.state,
      intensity: max(rule.modifier, 0),
      variance: 0,
      duration: 1,
      tags: []
    }
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
