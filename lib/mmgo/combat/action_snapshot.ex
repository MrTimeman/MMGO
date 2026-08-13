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
  alias MMGO.Arena.{Ladder, RoomRules}
  alias MMGO.Combat.{Action, Combat, Participant}
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemAction}
  alias MMGO.Repo

  alias MMGO.Spells.{
    FailureProfile,
    Incantation,
    InteractionRule,
    Manifestation,
    SchoolQuirk,
    Spell,
    SpellEffect
  }

  alias MMGO.Survival

  @action_types %{
    "wait" => :wait,
    "cast_spell" => :cast_spell,
    "manifestation_strike" => :manifestation_strike,
    "parry" => :parry,
    "block" => :block,
    "use_item" => :use_item,
    "flee" => :flee
  }

  # You may block with whatever you are holding, and what you hold decides how
  # much good it does. A shield is made for this; a blade turned flat is not;
  # bare arms and will are better than nothing and not much more.
  @guard_sources %{
    "summoned_shield" => %{block: 70, parry: 0},
    "summoned_creature" => %{block: 55, parry: 0},
    "summoned_weapon" => %{block: 40, parry: 70},
    "item" => %{block: 50, parry: 45},
    "bare" => %{block: 20, parry: 0}
  }

  @guard_manifestations ~w(summoned_shield summoned_creature summoned_weapon)
  @physical_guard_kinds [:raise_shield, :strike, :sweep, :deploy]

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

  @school_quirks Map.new(SchoolQuirk.values(), fn quirk -> {to_string(quirk), quirk} end)

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
  @incantation_slot_keys ~w(actio forma vis tempus mutatio pretium)
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
  Rehydrates a server-approved summoned weapon and target.

  The snapshot contains only bounded combat state copied from the participant;
  no weapon stats from the browser are accepted.
  """
  def manifestation_strike_for_resolution(
        %Action{action_type: :manifestation_strike, payload: payload} = action
      ) do
    with %{"snapshot" => snapshot} when is_map(snapshot) <- payload,
         "manifestation_strike" <- Map.get(snapshot, "kind"),
         {:ok, weapon} <- weapon_from_snapshot(Map.get(snapshot, "manifestation")),
         {:ok, target_side, target_participant_id} <- target_from_snapshot(snapshot) do
      {:ok, %{action | target_side: target_side, target_participant_id: target_participant_id},
       weapon}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  def manifestation_strike_for_resolution(_action), do: {:error, :invalid_snapshot}

  @doc """
  Rehydrates the defence the server approved at submission time.

  Only the source and its efficiency are carried, both of them server-chosen, so
  a browser cannot claim to be blocking with something it never held.
  """
  def guard_for_resolution(%Action{action_type: mode, payload: payload})
      when mode in [:parry, :block] do
    expected_kind = to_string(mode)

    with %{"snapshot" => snapshot} when is_map(snapshot) <- payload,
         ^expected_kind <- Map.get(snapshot, "kind"),
         source when is_binary(source) <- Map.get(snapshot, "guard_source"),
         efficiency when is_integer(efficiency) and efficiency > 0 <-
           guard_efficiency(mode, source) do
      {:ok, %{"mode" => to_string(mode), "source" => source, "efficiency" => efficiency}}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  def guard_for_resolution(_action), do: {:error, :invalid_snapshot}

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

  defp normalize_action(:flee, %Combat{kind: :arena_match}, _participant, _attrs) do
    {:ok,
     %{
       action_type: :flee,
       target_side: nil,
       target_participant_id: nil,
       payload: %{"snapshot" => %{"kind" => "flee"}}
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

  defp normalize_action(:manifestation_strike, combat, participant, attrs) do
    with {:ok, weapon} <- active_summoned_weapon(participant),
         {:ok, target_side, target_participant_id} <-
           normalize_target(combat, participant, :enemy, attrs) do
      {:ok,
       %{
         action_type: :manifestation_strike,
         target_side: target_side,
         target_participant_id: target_participant_id,
         payload: %{
           "snapshot" => %{
             "kind" => "manifestation_strike",
             "manifestation" => weapon,
             "target_side" => target_side,
             "target_participant_id" => target_participant_id
           }
         }
       }}
    end
  end

  defp normalize_action(mode, _combat, participant, attrs) when mode in [:parry, :block] do
    with {:ok, source} <- guard_source(mode, participant, attrs["guard_source"]) do
      {:ok,
       %{
         action_type: mode,
         target_side: nil,
         target_participant_id: nil,
         payload: %{
           "snapshot" => %{
             "kind" => to_string(mode),
             "guard_source" => source,
             "efficiency" => guard_efficiency(mode, source)
           }
         }
       }}
    end
  end

  defp normalize_action(:use_item, %Combat{kind: :arena_match}, _participant, _attrs),
    do: {:error, :items_disabled}

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

      not RoomRules.free_grimoire?(combat) and not prepared_spell?(participant, spell.id) ->
        {:error, :spell_not_prepared}

      not ranked_into_spell?(combat, participant, spell) ->
        {:error, :spell_rank_too_high}

      not affordable?(combat, participant, spell) ->
        {:error, :insufficient_mana}

      true ->
        {:ok, spell}
    end
  end

  defp owned_prepared_spell(_combat, _participant, _spell_id), do: {:error, :spell_not_found}

  @doc """
  Whether the caster can pay for this spell out of the pool they have now.

  The engine checks again when the turn resolves — the pool can drain in
  between — but refusing here is what lets the interface say so before the
  caster has spent their turn on it.
  """
  def affordable?(combat, %Participant{} = participant, %Spell{} = spell) do
    RoomRules.unlimited_mana?(combat) or participant.mana >= spell.fatigue_cost
  end

  @doc """
  Whether the caster's rank admits this spell.

  Craft decides how strong a spell is; rank decides who may wield it. Ranked
  play and the world hold a caster to the division the spell earned — and the
  spell becomes legal there the moment they rank into it. A custom room is where
  you play without restraint: anything the caster owns is legal in one, unless
  its host set a rank cap, which then binds everyone in the room equally.
  """
  def ranked_into_spell?(combat, participant, spell) do
    case rank_ceiling(combat, participant) do
      :any -> true
      ceiling -> Ladder.at_least?(ceiling, Spell.rank_requirement(spell))
    end
  end

  # The ceiling is the lower of what the caster has earned and what the room
  # allows. A room that frees rank drops the first half; a cap adds the second.
  defp rank_ceiling(combat, participant) do
    own = if RoomRules.free_rank?(combat), do: :any, else: caster_rank(participant)

    case {own, RoomRules.rank_cap(combat)} do
      {own, nil} -> own
      {:any, cap} -> cap
      {own, cap} -> if Ladder.at_least?(own, cap), do: cap, else: own
    end
  end

  # Participants without a rank of their own (actor templates) sit at the foot
  # of the ladder; they never cast player spells.
  defp caster_rank(%Participant{rank: rank}) when not is_nil(rank), do: rank
  defp caster_rank(_participant), do: hd(Ladder.keys())

  @doc """
  Everything the participant could raise against a blow right now, strongest
  first.

  Manifestations are read straight off the participant. A held item is not — the
  caller says whether there is one, because whoever is asking usually knows
  already and the alternative is a query on every render.
  """
  def guard_sources(mode, participant, opts \\ [])

  def guard_sources(mode, %Participant{} = participant, opts) when mode in [:parry, :block] do
    held =
      participant.active_states
      |> List.wrap()
      |> Enum.map(&Map.get(&1, "state"))
      |> Enum.filter(&(&1 in @guard_manifestations))
      |> Enum.uniq()

    held = if Keyword.get(opts, :holding_item?, false), do: ["item" | held], else: held

    ["bare" | held]
    |> Enum.filter(&(guard_efficiency(mode, &1) > 0))
    |> Enum.sort_by(&(-guard_efficiency(mode, &1)))
  end

  @doc "How much good this source does against a blow, as a percentage."
  def guard_efficiency(mode, source) when mode in [:parry, :block] do
    @guard_sources
    |> Map.get(source, %{block: 0, parry: 0})
    |> Map.fetch!(mode)
  end

  # Anything with a physical action on it can be interposed: a shield raised, a
  # tool held up, a blade turned. What it does not need is ammunition — nothing
  # is consumed by holding it in the way.
  defp holding_physical_item?(%Participant{character_id: character_id})
       when is_binary(character_id) do
    character_id
    |> Inventory.list_inventory_for_character()
    |> Enum.any?(fn item ->
      Enum.any?(item.item_template.actions || [], &(&1.action_kind in @physical_guard_kinds))
    end)
  end

  defp holding_physical_item?(_participant), do: false

  # A requested source must actually be in the participant's hands, and must be
  # good for the kind of defence they asked for: you cannot parry with a shield.
  # Only a claim to be holding an item is worth a query.
  defp guard_source(mode, participant, requested) do
    available =
      guard_sources(mode, participant,
        holding_item?: requested == "item" and holding_physical_item?(participant)
      )

    cond do
      is_binary(requested) and requested in available -> {:ok, requested}
      is_binary(requested) -> {:error, :guard_source_unavailable}
      available == [] -> {:error, :guard_source_unavailable}
      true -> {:ok, hd(available)}
    end
  end

  defp prepared_spell?(%Participant{grimoire: %{entries: entries}}, spell_id)
       when is_list(entries) do
    Enum.any?(entries, &(&1.spell_id == spell_id))
  end

  defp prepared_spell?(_participant, _spell_id), do: false

  defp active_summoned_weapon(%Participant{} = participant) do
    participant.active_states
    |> List.wrap()
    |> Enum.find(&(is_map(&1) and Map.get(&1, "state") == "summoned_weapon"))
    |> weapon_from_snapshot()
  end

  defp normalize_incantation(attrs, %Spell{} = spell) do
    payload = map_value(attrs, "payload")

    incantation =
      attrs["incantation"] || map_value(payload, "incantation") || spell.formula

    case Incantation.normalize(incantation) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, :invalid_incantation}
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
      "incantation_slots" => spell.incantation_slots || %{},
      "school" => to_string(spell.school),
      "school_quirk" => spell.school_quirk && to_string(spell.school_quirk),
      "fatigue_cost" => spell.fatigue_cost,
      "cooldown_turns" => spell.cooldown_turns,
      "targeting" => to_string(spell.targeting),
      "delivery_form" => to_string(spell.delivery_form),
      "environment_tags" => spell.environment_tags,
      "environment_mode" => to_string(spell.environment_mode),
      "effects" => Enum.map(spell.effects, &effect_snapshot/1),
      "manifestation" => manifestation_snapshot(spell.manifestation),
      "interaction_rules" => Enum.map(spell.interaction_rules, &interaction_rule_snapshot/1),
      "failure_profile" => failure_profile_snapshot(spell.failure_profile)
    }
  end

  defp manifestation_snapshot(nil), do: nil

  defp manifestation_snapshot(%Manifestation{} = manifestation) do
    %{
      "kind" => to_string(manifestation.kind),
      "display_name" => manifestation.display_name,
      "hp" => manifestation.hp,
      "power" => manifestation.power,
      "duration_turns" => manifestation.duration_turns
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
         incantation_slots when is_map(incantation_slots) <-
           Map.get(snapshot, "incantation_slots", %{}),
         true <- valid_incantation_slots?(incantation_slots, formula),
         {:ok, school} <- enum_value(Map.get(snapshot, "school"), @schools),
         {:ok, school_quirk} <-
           optional_enum_value(Map.get(snapshot, "school_quirk"), @school_quirks),
         true <- is_nil(school_quirk) or SchoolQuirk.compatible?(school, school_quirk),
         {:ok, targeting} <- enum_value(Map.get(snapshot, "targeting"), @targeting_modes),
         {:ok, delivery_form} <- enum_value(Map.get(snapshot, "delivery_form"), @delivery_forms),
         {:ok, environment_mode} <-
           enum_value(Map.get(snapshot, "environment_mode"), @environment_modes),
         fatigue_cost when is_integer(fatigue_cost) and fatigue_cost >= 0 <-
           Map.get(snapshot, "fatigue_cost"),
         cooldown_turns when is_integer(cooldown_turns) and cooldown_turns >= 0 <-
           Map.get(snapshot, "cooldown_turns"),
         {:ok, effects} <- effects_from_snapshot(Map.get(snapshot, "effects")),
         {:ok, manifestation} <-
           manifestation_from_snapshot(Map.get(snapshot, "manifestation")),
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
         incantation_slots: incantation_slots,
         school: school,
         school_quirk: school_quirk,
         fatigue_cost: fatigue_cost,
         cooldown_turns: cooldown_turns,
         targeting: targeting,
         delivery_form: delivery_form,
         environment_tags: Map.get(snapshot, "environment_tags", []),
         environment_mode: environment_mode,
         effects: effects,
         manifestation: manifestation,
         interaction_rules: interaction_rules,
         failure_profile: failure_profile
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp spell_from_snapshot(_snapshot), do: {:error, :invalid_snapshot}

  defp manifestation_from_snapshot(nil), do: {:ok, nil}

  defp manifestation_from_snapshot(snapshot) when is_map(snapshot) do
    %Manifestation{}
    |> Manifestation.changeset(snapshot)
    |> Ecto.Changeset.apply_action(:insert)
    |> case do
      {:ok, manifestation} -> {:ok, manifestation}
      {:error, _changeset} -> {:error, :invalid_snapshot}
    end
  end

  defp manifestation_from_snapshot(_snapshot), do: {:error, :invalid_snapshot}

  defp weapon_from_snapshot(snapshot) when is_map(snapshot) do
    with "summoned_weapon" <- Map.get(snapshot, "state"),
         source_spell_id when is_binary(source_spell_id) and source_spell_id != "" <-
           Map.get(snapshot, "source_spell_id"),
         display_name when is_binary(display_name) <- Map.get(snapshot, "display_name"),
         power when is_integer(power) <- Map.get(snapshot, "power"),
         remaining_turns when is_integer(remaining_turns) <- Map.get(snapshot, "remaining_turns"),
         applied_on_turn when is_integer(applied_on_turn) and applied_on_turn >= 0 <-
           Map.get(snapshot, "applied_on_turn"),
         {:ok, _manifestation} <-
           manifestation_from_snapshot(%{
             "kind" => "summoned_weapon",
             "display_name" => display_name,
             "power" => power,
             "duration_turns" => remaining_turns
           }) do
      {:ok,
       %{
         "state" => "summoned_weapon",
         "source_spell_id" => source_spell_id,
         "display_name" => display_name,
         "power" => power,
         "remaining_turns" => remaining_turns,
         "applied_on_turn" => applied_on_turn
       }}
    else
      _other -> {:error, :invalid_snapshot}
    end
  end

  defp weapon_from_snapshot(_snapshot), do: {:error, :manifestation_unavailable}

  defp optional_enum_value(nil, _values), do: {:ok, nil}
  defp optional_enum_value(value, values), do: enum_value(value, values)

  defp valid_incantation_slots?(slots, formula) do
    valid_seals? =
      Enum.all?(slots, fn
        {key, value} when key in @incantation_slot_keys and is_binary(value) ->
          match?({:ok, ^value}, Incantation.normalize(value)) and
            not String.contains?(value, " ")

        _invalid ->
          false
      end)

    valid_seals? and
      (map_size(slots) == 0 or incantation_formula(slots) == formula)
  end

  defp incantation_formula(slots) do
    @incantation_slot_keys
    |> Enum.flat_map(fn key ->
      case Map.get(slots, key) do
        nil -> []
        word -> [word]
      end
    end)
    |> Enum.join(" ")
  end

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
