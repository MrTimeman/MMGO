defmodule MMGO.Combat.ActionSnapshot do
  @moduledoc """
  Converts an untrusted combat action selection into a small, durable record of
  facts already approved by the server.

  Browser payloads never supply effects, costs, ownership, or arbitrary target
  identities. The combat context supplies a locked combat and participant; this
  module looks up only records owned by that participant and returns attributes
  suitable for `MMGO.Combat.Action`.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Participant}
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemAction}
  alias MMGO.Repo
  alias MMGO.Spells.{FailureProfile, Incantation, InteractionRule, Spell, SpellEffect}
  alias MMGO.Survival

  @action_types %{
    "wait" => :wait,
    "cast_spell" => :cast_spell,
    "use_item" => :use_item,
    "flee" => :flee
  }

  @schools %{
    "fire" => :fire,
    "water" => :water,
    "earth" => :earth,
    "air" => :air,
    "life" => :life,
    "death" => :death,
    "chaos" => :chaos,
    "order" => :order
  }

  @targeting_modes %{"self" => :self, "ally" => :ally, "enemy" => :enemy, "zone" => :zone}

  @delivery_forms %{
    "single_target" => :single_target,
    "beam" => :beam,
    "cone" => :cone,
    "sphere" => :sphere,
    "wall" => :wall,
    "zone" => :zone,
    "self" => :self,
    "link" => :link,
    "delayed_trigger" => :delayed_trigger
  }

  @environment_modes %{"none" => :none, "add" => :add, "replace" => :replace}
  @applies_to %{"target" => :target, "caster" => :caster, "environment" => :environment}

  @action_kinds %{
    "strike" => :strike,
    "sweep" => :sweep,
    "raise_shield" => :raise_shield,
    "throw" => :throw,
    "deploy" => :deploy,
    "repair" => :repair
  }

  @interaction_trigger_types %{
    "environment_tag" => :environment_tag,
    "target_state" => :target_state,
    "spell_tag" => :spell_tag
  }

  @interaction_outcomes %{
    "negate" => :negate,
    "amplify" => :amplify,
    "replace_environment" => :replace_environment,
    "apply_bonus_state" => :apply_bonus_state
  }

  def normalize(%Combat{} = combat, %Participant{} = participant, attrs)
      when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, action_type} <- action_type(attrs["action_type"]),
         {:ok, snapshot} <- normalize_action(action_type, combat, participant, attrs) do
      {:ok, snapshot}
    end
  end

  def normalize(_combat, _participant, _attrs), do: {:error, :invalid_action}

  @doc """
  Rehydrates the immutable spell and target approved at submission time.

  Persisted actions without a valid server snapshot fail closed. The small
  in-memory exception preserves pure engine unit tests that deliberately build
  an action struct without database persistence.
  """
  def cast_for_resolution(
        %Action{action_type: :cast_spell, id: nil, spell: %Spell{} = spell} = action
      ) do
    {:ok, action, spell}
  end

  def cast_for_resolution(%Action{action_type: :cast_spell, payload: payload} = action) do
    with %{"snapshot" => snapshot} when is_map(snapshot) <- payload,
         "cast_spell" <- Map.get(snapshot, "kind"),
         {:ok, spell} <- spell_from_snapshot(Map.get(snapshot, "spell")),
         {:ok, target_side, target_participant_id} <- target_from_snapshot(snapshot) do
      {:ok, %{action | target_side: target_side, target_participant_id: target_participant_id},
       spell}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  def cast_for_resolution(_action), do: {:error, :invalid_snapshot}

  @doc """
  Rehydrates a frozen item-action definition and target from a server-created
  action snapshot. Current inventory records are still used only to consume the
  resource that was reserved when the turn was sealed.
  """
  def item_for_resolution(%Action{action_type: :use_item, id: nil} = action) do
    with %InventoryItem{item_template: item_template} <- action.inventory_item,
         action_key when is_binary(action_key) <- tool_action_from_payload(action.payload),
         %ItemAction{} = item_action <-
           Enum.find(item_template.actions || [], &(&1.key == action_key)) do
      {:ok, action, item_action, item_template.code}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  def item_for_resolution(%Action{action_type: :use_item, payload: payload} = action) do
    with %{"snapshot" => snapshot} when is_map(snapshot) <- payload,
         "use_item" <- Map.get(snapshot, "kind"),
         {:ok, item_action} <- item_action_from_snapshot(Map.get(snapshot, "item_action")),
         item_code when is_binary(item_code) <- Map.get(snapshot, "item_code"),
         {:ok, target_side, target_participant_id} <- target_from_snapshot(snapshot) do
      {:ok, %{action | target_side: target_side, target_participant_id: target_participant_id},
       item_action, item_code}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  def item_for_resolution(_action), do: {:error, :invalid_snapshot}

  defp normalize_action(:wait, _combat, _participant, _attrs) do
    {:ok,
     %{
       action_type: :wait,
       target_side: nil,
       target_participant_id: nil,
       payload: %{"snapshot" => %{"kind" => "wait"}}
     }}
  end

  defp normalize_action(:flee, _combat, %Participant{character: %Character{} = character}, _attrs) do
    with %{flee_available?: true} <- Survival.summary(character) do
      {:ok,
       %{
         action_type: :flee,
         target_side: nil,
         target_participant_id: nil,
         payload: %{"snapshot" => %{"kind" => "flee"}}
       }}
    else
      _other -> {:error, :flee_unavailable}
    end
  end

  defp normalize_action(:flee, _combat, _participant, _attrs), do: {:error, :flee_unavailable}

  defp normalize_action(:cast_spell, combat, participant, attrs) do
    with {:ok, spell} <- owned_prepared_spell(combat, participant, attrs["spell_id"]),
         {:ok, incantation} <- normalize_incantation(attrs, spell),
         {:ok, target_side, target_participant_id} <-
           normalize_target(combat, participant, spell.targeting, attrs) do
      {:ok,
       %{
         action_type: :cast_spell,
         spell_id: spell.id,
         target_side: target_side,
         target_participant_id: target_participant_id,
         payload: %{
           "snapshot" => %{
             "kind" => "cast_spell",
             "incantation" => incantation,
             "spell" => spell_snapshot(spell),
             "target_side" => target_side,
             "target_participant_id" => target_participant_id
           }
         }
       }}
    end
  end

  defp normalize_action(:use_item, combat, participant, attrs) do
    with {:ok, inventory_item} <- owned_inventory_item(participant, attrs["inventory_item_id"]),
         {:ok, item_action} <- item_action(inventory_item, tool_action(attrs)),
         :ok <- item_available?(inventory_item, item_action),
         {:ok, target_side, target_participant_id} <-
           normalize_target(combat, participant, item_action.targeting, attrs) do
      {:ok,
       %{
         action_type: :use_item,
         inventory_item_id: inventory_item.id,
         target_side: target_side,
         target_participant_id: target_participant_id,
         payload: %{
           "tool_action" => item_action.key,
           "snapshot" => %{
             "kind" => "use_item",
             "inventory_item_id" => inventory_item.id,
             "item_code" => inventory_item.item_template.code,
             "item_action" => item_action_snapshot(item_action),
             "target_side" => target_side,
             "target_participant_id" => target_participant_id
           }
         }
       }}
    end
  end

  defp action_type(action_type) when is_atom(action_type),
    do: action_type(Atom.to_string(action_type))

  defp action_type(action_type) when is_binary(action_type) do
    case Map.fetch(@action_types, action_type) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_action_type}
    end
  end

  defp action_type(_action_type), do: {:error, :invalid_action_type}

  defp owned_prepared_spell(%Combat{} = combat, %Participant{} = participant, spell_id)
       when is_binary(spell_id) do
    spell = Repo.get(Spell, spell_id)

    cond do
      is_nil(spell) ->
        {:error, :spell_not_found}

      is_nil(participant.character_id) or spell.creator_character_id != participant.character_id ->
        {:error, :spell_not_owned}

      spell.realm_id != combat.realm_id ->
        {:error, :spell_not_owned}

      not prepared_spell?(participant, spell.id) ->
        {:error, :spell_not_prepared}

      true ->
        {:ok, spell}
    end
  end

  defp owned_prepared_spell(_combat, _participant, _spell_id), do: {:error, :spell_not_found}

  defp prepared_spell?(%Participant{grimoire: %{entries: entries}}, spell_id)
       when is_list(entries) do
    Enum.any?(entries, &(&1.spell_id == spell_id))
  end

  defp prepared_spell?(_participant, _spell_id), do: false

  defp normalize_incantation(attrs, %Spell{} = spell) do
    payload = map_value(attrs, "payload")

    incantation =
      attrs["incantation"] || map_value(payload, "incantation") || spell.formula

    case Incantation.normalize(incantation) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, :empty_formula} -> {:error, :invalid_incantation}
      {:error, :too_many_words} -> {:error, :invalid_incantation}
      {:error, :invalid_word} -> {:error, :invalid_incantation}
    end
  end

  defp owned_inventory_item(%Participant{character_id: character_id}, inventory_item_id)
       when is_binary(character_id) and is_binary(inventory_item_id) do
    inventory_item =
      InventoryItem
      |> where([item], item.id == ^inventory_item_id)
      |> lock("FOR UPDATE")
      |> preload(:item_template)
      |> Repo.one()

    case inventory_item do
      %InventoryItem{character_id: ^character_id} = item -> {:ok, item}
      %InventoryItem{} -> {:error, :item_not_owned}
      nil -> {:error, :item_not_found}
    end
  end

  defp owned_inventory_item(_participant, _inventory_item_id), do: {:error, :item_not_found}

  defp item_action(%InventoryItem{item_template: item_template}, action_key)
       when is_binary(action_key) do
    case Enum.find(item_template.actions || [], &(&1.key == action_key)) do
      %ItemAction{} = item_action -> {:ok, item_action}
      nil -> {:error, :invalid_item_action}
    end
  end

  defp item_action(_inventory_item, _action_key), do: {:error, :invalid_item_action}

  defp item_available?(%InventoryItem{} = inventory_item, %ItemAction{} = item_action) do
    cond do
      Inventory.available_quantity(inventory_item) < item_action.quantity_cost ->
        {:error, :item_unavailable}

      inventory_item.durability < item_action.durability_cost ->
        {:error, :item_unavailable}

      true ->
        :ok
    end
  end

  defp normalize_target(combat, participant, targeting, attrs) do
    requested_target_id = attrs["target_participant_id"]
    requested_side = attrs["target_side"]

    case targeting do
      :self ->
        {:ok, participant.side, participant.id}

      :ally ->
        normalize_target_for_side(combat, participant, participant.side, requested_target_id)

      :enemy ->
        with {:ok, target_side} <- enemy_target_side(combat, participant, requested_side) do
          normalize_target_for_side(combat, participant, target_side, requested_target_id)
        end

      :zone ->
        with {:ok, target_side} <- enemy_target_side(combat, participant, requested_side) do
          normalize_target_for_side(combat, participant, target_side, requested_target_id,
            allow_empty?: true
          )
        end
    end
  end

  defp enemy_target_side(%Combat{} = combat, %Participant{} = participant, target_side)
       when is_binary(target_side) do
    if Map.has_key?(combat.sides, target_side) and target_side != participant.side do
      {:ok, target_side}
    else
      {:error, :invalid_target}
    end
  end

  defp enemy_target_side(%Combat{} = combat, %Participant{} = participant, nil) do
    combat.participants
    |> Enum.find(&(&1.side != participant.side and &1.status == :ready))
    |> case do
      nil -> {:error, :invalid_target}
      target -> {:ok, target.side}
    end
  end

  defp enemy_target_side(_combat, _participant, _target_side), do: {:error, :invalid_target}

  defp normalize_target_for_side(
         combat,
         participant,
         target_side,
         requested_target_id,
         opts \\ []
       ) do
    allow_empty? = Keyword.get(opts, :allow_empty?, false)

    candidates =
      combat.participants
      |> Enum.filter(&(&1.side == target_side and &1.status == :ready))
      |> Enum.sort_by(& &1.position)

    target =
      case requested_target_id do
        target_id when is_binary(target_id) ->
          Enum.find(candidates, &(&1.id == target_id))

        _other ->
          List.first(candidates)
      end

    cond do
      is_nil(target) and allow_empty? -> {:ok, target_side, nil}
      is_nil(target) -> {:error, :invalid_target}
      target.combat_id != combat.id -> {:error, :invalid_target}
      participant.combat_id != combat.id -> {:error, :invalid_target}
      true -> {:ok, target_side, target.id}
    end
  end

  defp tool_action(attrs) do
    payload = map_value(attrs, "payload")
    attrs["tool_action"] || map_value(payload, "tool_action")
  end

  defp spell_snapshot(spell) do
    %{
      "id" => spell.id,
      "name" => spell.name,
      "formula" => spell.formula,
      "school" => to_string(spell.school),
      "fatigue_cost" => spell.fatigue_cost,
      "cooldown_turns" => spell.cooldown_turns,
      "targeting" => to_string(spell.targeting),
      "delivery_form" => to_string(spell.delivery_form),
      "environment_tags" => spell.environment_tags,
      "environment_mode" => to_string(spell.environment_mode),
      "effects" => Enum.map(spell.effects, &effect_snapshot/1),
      "interaction_rules" => Enum.map(spell.interaction_rules, &interaction_rule_snapshot/1),
      "failure_profile" => failure_profile_snapshot(spell.failure_profile)
    }
  end

  defp item_action_snapshot(item_action) do
    %{
      "key" => item_action.key,
      "action_kind" => to_string(item_action.action_kind),
      "targeting" => to_string(item_action.targeting),
      "quantity_cost" => item_action.quantity_cost,
      "durability_cost" => item_action.durability_cost,
      "effects" => Enum.map(item_action.effects, &effect_snapshot/1)
    }
  end

  defp failure_profile_snapshot(failure_profile) do
    %{
      "difficulty" => failure_profile.difficulty,
      "base_success_rate" => failure_profile.base_success_rate,
      "partial_success_rate" => failure_profile.partial_success_rate,
      "backlash_damage" => failure_profile.backlash_damage,
      "volatility" => failure_profile.volatility
    }
  end

  defp interaction_rule_snapshot(rule) do
    %{
      "trigger_type" => to_string(rule.trigger_type),
      "trigger" => rule.trigger,
      "outcome" => to_string(rule.outcome),
      "modifier" => rule.modifier,
      "state" => rule.state,
      "replacement_tags" => rule.replacement_tags
    }
  end

  defp effect_snapshot(effect) do
    %{
      "applies_to" => to_string(effect.applies_to),
      "state" => effect.state,
      "intensity" => effect.intensity,
      "variance" => effect.variance,
      "duration" => effect.duration,
      "tags" => effect.tags,
      "break_conditions" => effect.break_conditions
    }
  end

  defp spell_from_snapshot(snapshot) when is_map(snapshot) do
    with id when is_binary(id) <- Map.get(snapshot, "id"),
         formula when is_binary(formula) and formula != "" <- Map.get(snapshot, "formula"),
         {:ok, school} <- enum_value(Map.get(snapshot, "school"), @schools),
         {:ok, targeting} <- enum_value(Map.get(snapshot, "targeting"), @targeting_modes),
         {:ok, delivery_form} <- enum_value(Map.get(snapshot, "delivery_form"), @delivery_forms),
         {:ok, environment_mode} <-
           enum_value(Map.get(snapshot, "environment_mode"), @environment_modes),
         fatigue_cost when is_integer(fatigue_cost) and fatigue_cost >= 0 <-
           Map.get(snapshot, "fatigue_cost"),
         cooldown_turns when is_integer(cooldown_turns) and cooldown_turns >= 0 <-
           Map.get(snapshot, "cooldown_turns"),
         {:ok, effects} <- effects_from_snapshot(Map.get(snapshot, "effects")),
         {:ok, interaction_rules} <-
           interaction_rules_from_snapshot(Map.get(snapshot, "interaction_rules")),
         {:ok, failure_profile} <-
           failure_profile_from_snapshot(Map.get(snapshot, "failure_profile")),
         true <- string_list?(Map.get(snapshot, "environment_tags", [])) do
      {:ok,
       %Spell{
         id: id,
         name: Map.get(snapshot, "name") || formula,
         formula: formula,
         school: school,
         fatigue_cost: fatigue_cost,
         cooldown_turns: cooldown_turns,
         targeting: targeting,
         delivery_form: delivery_form,
         environment_tags: Map.get(snapshot, "environment_tags", []),
         environment_mode: environment_mode,
         effects: effects,
         interaction_rules: interaction_rules,
         failure_profile: failure_profile
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp spell_from_snapshot(_snapshot), do: {:error, :invalid_snapshot}

  defp item_action_from_snapshot(snapshot) when is_map(snapshot) do
    with key when is_binary(key) and key != "" <- Map.get(snapshot, "key"),
         {:ok, action_kind} <- enum_value(Map.get(snapshot, "action_kind"), @action_kinds),
         {:ok, targeting} <- enum_value(Map.get(snapshot, "targeting"), @targeting_modes),
         quantity_cost when is_integer(quantity_cost) and quantity_cost >= 0 <-
           Map.get(snapshot, "quantity_cost"),
         durability_cost when is_integer(durability_cost) and durability_cost >= 0 <-
           Map.get(snapshot, "durability_cost"),
         {:ok, effects} <- effects_from_snapshot(Map.get(snapshot, "effects")) do
      {:ok,
       %ItemAction{
         key: key,
         action_kind: action_kind,
         targeting: targeting,
         quantity_cost: quantity_cost,
         durability_cost: durability_cost,
         effects: effects
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp item_action_from_snapshot(_snapshot), do: {:error, :invalid_snapshot}

  defp target_from_snapshot(snapshot) when is_map(snapshot) do
    target_side = Map.get(snapshot, "target_side")
    target_participant_id = Map.get(snapshot, "target_participant_id")

    if valid_optional_binary?(target_side) and valid_optional_binary?(target_participant_id) do
      {:ok, target_side, target_participant_id}
    else
      {:error, :invalid_snapshot}
    end
  end

  defp effects_from_snapshot(effects) when is_list(effects) do
    map_all(effects, &effect_from_snapshot/1)
  end

  defp effects_from_snapshot(_effects), do: {:error, :invalid_snapshot}

  defp effect_from_snapshot(effect) when is_map(effect) do
    with {:ok, applies_to} <- enum_value(Map.get(effect, "applies_to"), @applies_to),
         state when is_binary(state) <- Map.get(effect, "state"),
         true <- state in SpellEffect.supported_states(),
         intensity when is_integer(intensity) and intensity >= 0 <- Map.get(effect, "intensity"),
         variance when is_integer(variance) and variance >= 0 and variance <= intensity <-
           Map.get(effect, "variance"),
         duration when is_integer(duration) and duration >= 0 <- Map.get(effect, "duration"),
         true <- string_list?(Map.get(effect, "tags", [])),
         true <- valid_break_conditions?(Map.get(effect, "break_conditions", [])) do
      {:ok,
       %SpellEffect{
         applies_to: applies_to,
         state: state,
         intensity: intensity,
         variance: variance,
         duration: duration,
         tags: Map.get(effect, "tags", []),
         break_conditions: Map.get(effect, "break_conditions", [])
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp effect_from_snapshot(_effect), do: {:error, :invalid_snapshot}

  defp interaction_rules_from_snapshot(rules) when is_list(rules) do
    map_all(rules, &interaction_rule_from_snapshot/1)
  end

  defp interaction_rules_from_snapshot(_rules), do: {:error, :invalid_snapshot}

  defp interaction_rule_from_snapshot(rule) when is_map(rule) do
    with {:ok, trigger_type} <-
           enum_value(Map.get(rule, "trigger_type"), @interaction_trigger_types),
         trigger when is_binary(trigger) and trigger != "" <- Map.get(rule, "trigger"),
         {:ok, outcome} <- enum_value(Map.get(rule, "outcome"), @interaction_outcomes),
         modifier when is_integer(modifier) <- Map.get(rule, "modifier", 0),
         state when is_nil(state) or is_binary(state) <- Map.get(rule, "state"),
         true <- string_list?(Map.get(rule, "replacement_tags", [])) do
      {:ok,
       %InteractionRule{
         trigger_type: trigger_type,
         trigger: trigger,
         outcome: outcome,
         modifier: modifier,
         state: state,
         replacement_tags: Map.get(rule, "replacement_tags", [])
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp interaction_rule_from_snapshot(_rule), do: {:error, :invalid_snapshot}

  defp failure_profile_from_snapshot(profile) when is_map(profile) do
    with difficulty when is_integer(difficulty) and difficulty in 1..100 <-
           Map.get(profile, "difficulty"),
         base_success_rate when is_integer(base_success_rate) and base_success_rate in 1..100 <-
           Map.get(profile, "base_success_rate"),
         partial_success_rate
         when is_integer(partial_success_rate) and partial_success_rate in 0..100 <-
           Map.get(profile, "partial_success_rate"),
         backlash_damage when is_integer(backlash_damage) and backlash_damage >= 0 <-
           Map.get(profile, "backlash_damage"),
         volatility when is_integer(volatility) and volatility in 0..100 <-
           Map.get(profile, "volatility", 0) do
      {:ok,
       %FailureProfile{
         difficulty: difficulty,
         base_success_rate: base_success_rate,
         partial_success_rate: partial_success_rate,
         backlash_damage: backlash_damage,
         volatility: volatility
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp failure_profile_from_snapshot(_profile), do: {:error, :invalid_snapshot}

  defp tool_action_from_payload(payload) when is_map(payload) do
    Map.get(payload, "tool_action") || Map.get(payload, :tool_action)
  end

  defp tool_action_from_payload(_payload), do: nil

  defp enum_value(value, mapping) when is_binary(value) do
    case Map.fetch(mapping, value) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :invalid_snapshot}
    end
  end

  defp enum_value(value, mapping) when is_atom(value) do
    if value in Map.values(mapping), do: {:ok, value}, else: {:error, :invalid_snapshot}
  end

  defp enum_value(_value, _mapping), do: {:error, :invalid_snapshot}

  defp map_all(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} -> {:halt, {:error, :invalid_snapshot}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp string_list?(value) when is_list(value), do: Enum.all?(value, &is_binary/1)
  defp string_list?(_value), do: false

  defp valid_break_conditions?(conditions) do
    string_list?(conditions) and
      length(conditions) <= 3 and
      Enum.all?(conditions, &(&1 in SpellEffect.supported_break_conditions()))
  end

  defp valid_optional_binary?(nil), do: true
  defp valid_optional_binary?(value) when is_binary(value), do: true
  defp valid_optional_binary?(_value), do: false

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp map_value(map, "payload") when is_map(map),
    do: Map.get(map, "payload") || Map.get(map, :payload)

  defp map_value(map, "incantation") when is_map(map),
    do: Map.get(map, "incantation") || Map.get(map, :incantation)

  defp map_value(map, "tool_action") when is_map(map),
    do: Map.get(map, "tool_action") || Map.get(map, :tool_action)

  defp map_value(_map, _key), do: nil
end
