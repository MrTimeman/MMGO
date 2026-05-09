defmodule MMGO.Combat.Engine do
  alias MMGO.Combat.{Action, Combat, Orchestrator, Participant, RNG, Turn}
  alias MMGO.Inventory.{InventoryItem, ItemAction}
  alias MMGO.Spells.{Runtime, Spell, SpellEffect}

  def resolve_turn(%Combat{} = combat, %Turn{} = turn, participants, actions, opts \\ []) do
    participants_by_id =
      participants
      |> Enum.map(&normalize_participant_metadata/1)
      |> Map.new(&{&1.id, &1})

    active_participants = Enum.filter(Map.values(participants_by_id), &(&1.status == :ready))
    sides = normalize_sides(combat.sides)
    environment_tags = combat.environment_tags || []

    {participants_by_id, sides, environment_tags, starting_seq, events} =
      apply_start_of_turn(
        combat,
        active_participants,
        participants_by_id,
        sides,
        environment_tags,
        1,
        []
      )

    actions = fill_missing_actions(actions, active_participants)

    {participants_by_id, sides, environment_tags, inventory_updates, _final_seq, events} =
      actions
      |> Enum.sort_by(&RNG.order_key(combat.seed, [combat.turn_number, &1.participant_id]), :asc)
      |> Enum.reduce(
        {participants_by_id, sides, environment_tags, %{}, starting_seq, events},
        fn action, {participants_acc, sides_acc, tags_acc, inventory_acc, seq_acc, events_acc} ->
          resolve_action(
            combat,
            turn,
            action,
            participants_acc,
            sides_acc,
            tags_acc,
            inventory_acc,
            seq_acc,
            events_acc,
            opts
          )
        end
      )

    participants_by_id =
      participants_by_id
      |> expire_non_periodic_states(combat.turn_number)
      |> expire_passive_spells(combat.turn_number)

    winner_side = determine_winner(sides)
    participants_by_id = finalize_participants(participants_by_id, sides, winner_side)
    next_turn_number = if winner_side, do: combat.turn_number, else: combat.turn_number + 1

    %{
      combat_attrs: %{
        status: if(winner_side, do: :finished, else: :active_turn),
        turn_number: next_turn_number,
        environment_tags: environment_tags,
        sides: sides,
        winner_side: winner_side,
        finished_at: if(winner_side, do: DateTime.utc_now(), else: nil)
      },
      participant_updates:
        Map.new(participants_by_id, fn {participant_id, participant} ->
          {participant_id,
           %{
             status: participant.status,
             fatigue: participant.fatigue,
             cooldowns: participant.cooldowns,
             active_states: participant.active_states,
             metadata: participant.metadata
           }}
        end),
      turn_attrs: %{
        status: :resolved,
        narration: default_narration(turn.number, events, winner_side),
        resolution: %{
          "winner_side" => winner_side,
          "environment_tags" => environment_tags,
          "sides" => sides,
          "event_count" => length(events),
          "orchestrated" => Keyword.get(opts, :orchestrate, false)
        }
      },
      inventory_updates: inventory_updates,
      create_next_turn?: is_nil(winner_side),
      events: Enum.reverse(events)
    }
  end

  defp apply_start_of_turn(
         combat,
         active_participants,
         participants_by_id,
         sides,
         tags,
         seq,
         events
       ) do
    {sides, tags, seq, events} = apply_environment_ticks(combat, sides, tags, seq, events)

    Enum.reduce(
      active_participants,
      {participants_by_id, sides, tags, seq, events},
      fn participant, {participants_acc, sides_acc, tags_acc, seq_acc, events_acc} ->
        participant = decrement_cooldowns(participants_acc[participant.id])

        {participant, sides_acc, state_events, next_seq} =
          tick_states(combat, participant, sides_acc, seq_acc)

        {participant, tags_acc, aura_events, next_seq} =
          apply_passive_aura_tick(combat, participant, tags_acc, next_seq)

        {Map.put(participants_acc, participant.id, participant), sides_acc, tags_acc, next_seq,
         aura_events ++ state_events ++ events_acc}
      end
    )
  end

  defp apply_environment_ticks(combat, sides, tags, seq, events) do
    Enum.reduce(tags, {sides, tags, seq, events}, fn tag,
                                                     {sides_acc, tags_acc, seq_acc, events_acc} ->
      case tag do
        "burning" ->
          damage = 4

          updated_sides =
            sides_acc
            |> apply_side_delta("attackers", -damage)
            |> apply_side_delta("defenders", -damage)

          payload = %{
            "tag" => tag,
            "damage" => damage,
            "affected_sides" => ["attackers", "defenders"]
          }

          {updated_sides, tags_acc, seq_acc + 1,
           [event(seq_acc, combat.turn_number, "environment_tick", payload) | events_acc]}

        _other ->
          {sides_acc, tags_acc, seq_acc, events_acc}
      end
    end)
  end

  defp decrement_cooldowns(%Participant{} = participant) do
    cooldowns =
      participant.cooldowns
      |> Enum.reduce(%{}, fn {spell_id, remaining}, acc ->
        updated_remaining = max(remaining - 1, 0)

        if updated_remaining > 0 do
          Map.put(acc, spell_id, updated_remaining)
        else
          acc
        end
      end)

    %{participant | cooldowns: cooldowns}
  end

  defp tick_states(combat, %Participant{} = participant, sides, seq) do
    {active_states, sides, events, next_seq} =
      Enum.reduce(
        participant.active_states || [],
        {[], sides, [], seq},
        fn state, {states_acc, sides_acc, events_acc, seq_acc} ->
          if periodic_state?(Map.get(state, "state")) do
            remaining_turns = max(Map.get(state, "remaining_turns", 0) - 1, 0)

            {sides_acc, tick_event_payload} =
              case Map.get(state, "state") do
                "burning" ->
                  intensity = Map.get(state, "intensity", 0)

                  {apply_side_delta(sides_acc, participant.side, -intensity),
                   %{"damage" => intensity}}

                "regenerating" ->
                  intensity = Map.get(state, "intensity", 0)

                  {apply_side_delta(sides_acc, participant.side, intensity),
                   %{"healing" => intensity}}

                _other ->
                  {sides_acc, nil}
              end

            events_acc =
              if tick_event_payload do
                [
                  event(seq_acc, combat.turn_number, "state_tick", %{
                    "participant_id" => participant.id,
                    "state" => Map.get(state, "state"),
                    "side" => participant.side,
                    "details" => tick_event_payload
                  })
                  | events_acc
                ]
              else
                events_acc
              end

            states_acc =
              if remaining_turns > 0 do
                [Map.put(state, "remaining_turns", remaining_turns) | states_acc]
              else
                states_acc
              end

            {states_acc, sides_acc, events_acc,
             if(tick_event_payload, do: seq_acc + 1, else: seq_acc)}
          else
            {[state | states_acc], sides_acc, events_acc, seq_acc}
          end
        end
      )

    {%{participant | active_states: Enum.reverse(active_states)}, sides, Enum.reverse(events),
     next_seq}
  end

  defp fill_missing_actions(actions, active_participants) do
    submitted = MapSet.new(actions, & &1.participant_id)

    auto_waits =
      active_participants
      |> Enum.reject(&MapSet.member?(submitted, &1.id))
      |> Enum.map(fn participant ->
        %Action{
          participant_id: participant.id,
          action_type: :wait,
          payload: %{"auto" => true},
          submitted_at: DateTime.from_unix!(0)
        }
      end)

    actions ++ auto_waits
  end

  defp resolve_action(
         combat,
         _turn,
         %Action{action_type: :wait} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events,
         _opts
       ) do
    {participants, sides, tags, inventory_updates, seq + 1,
     [
       event(seq, combat.turn_number, "wait", %{"participant_id" => action.participant_id})
       | events
     ]}
  end

  defp resolve_action(
         combat,
         turn,
         %Action{action_type: :cast_spell} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events,
         opts
       ) do
    participant = Map.fetch!(participants, action.participant_id)

    cond do
      participant.status != :ready ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "skipped", %{"participant_id" => participant.id})
           | events
         ]}

      blocked = blocked_action(participant, :cast_spell) ->
        {updated_participant, blocked_state, consumed?} = blocked
        participants = Map.put(participants, participant.id, updated_participant)

        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "action_blocked", %{
             "participant_id" => participant.id,
             "state" => blocked_state,
             "consumed" => consumed?
           })
           | events
         ]}

      is_nil(action.spell) or action.spell.__struct__ == Ecto.Association.NotLoaded ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_action", %{"participant_id" => participant.id})
           | events
         ]}

      is_nil(participant.character_id) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_action", %{
             "participant_id" => participant.id,
             "reason" => "actor_cannot_cast_player_spell"
           })
           | events
         ]}

      is_nil(action.spell.creator_character_id) or
          action.spell.creator_character_id != participant.character_id ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "unauthorized_spell", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell_id
           })
           | events
         ]}

      not spell_available?(participant, action.spell.id) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "spell_not_prepared", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell.id,
             "grimoire_id" => participant.grimoire_id
           })
           | events
         ]}

      action.spell.spell_type == :utility ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_action", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell.id,
             "reason" => "utility_spells_are_out_of_combat_only"
           })
           | events
         ]}

      Map.get(participant.cooldowns || %{}, action.spell.id, 0) > 0 and
          action.spell.spell_type != :passive ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "spell_on_cooldown", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell.id
           })
           | events
         ]}

      true ->
        resolve_spell_cast(
          combat,
          turn,
          participant,
          action,
          participants,
          sides,
          tags,
          inventory_updates,
          seq,
          events,
          opts
        )
    end
  end

  defp resolve_action(
         combat,
         _turn,
         %Action{action_type: :use_item} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events,
         _opts
       ) do
    participant = Map.fetch!(participants, action.participant_id)

    cond do
      participant.status != :ready ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "skipped", %{"participant_id" => participant.id})
           | events
         ]}

      blocked = blocked_action(participant, :use_item) ->
        {updated_participant, blocked_state, consumed?} = blocked
        participants = Map.put(participants, participant.id, updated_participant)

        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "action_blocked", %{
             "participant_id" => participant.id,
             "state" => blocked_state,
             "consumed" => consumed?
           })
           | events
         ]}

      is_nil(action.inventory_item) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_action", %{"participant_id" => participant.id})
           | events
         ]}

      action.inventory_item.character_id != participant.character_id ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "unauthorized_item", %{
             "participant_id" => participant.id,
             "inventory_item_id" => action.inventory_item_id
           })
           | events
         ]}

      true ->
        resolve_item_use(
          combat,
          action,
          participant,
          participants,
          sides,
          tags,
          inventory_updates,
          seq,
          events
        )
    end
  end

  defp resolve_spell_cast(
         combat,
         turn,
         participant,
         action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events,
         opts
       ) do
    spell = action.spell

    if spell.spell_type == :passive do
      resolve_passive_spell_toggle(
        combat,
        participant,
        spell,
        participants,
        sides,
        tags,
        inventory_updates,
        seq,
        events
      )
    else
      environment_outcome = Runtime.environment_outcome(spell, tags)

      success_rate =
        Runtime.success_rate(spell, participant_level(participant), div(participant.fatigue, 5))

      participant =
        participant
        |> Map.update!(:fatigue, &(&1 + spell.fatigue_cost))
        |> Map.update!(:cooldowns, &Map.put(&1, spell.id, spell.cooldown_turns))

      participants = Map.put(participants, participant.id, participant)

      cond do
        environment_outcome.negated? ->
          {participants, sides, tags, inventory_updates, seq + 1,
           [
             event(seq, combat.turn_number, "spell_negated", %{
               "participant_id" => participant.id,
               "spell_id" => spell.id,
               "environment_tags" => tags
             })
             | events
           ]}

        true ->
          target_side = resolve_target_side(action, participant, spell, sides)
          target_participant_id = resolve_target_participant_id(action, participants, target_side)

          resolution =
            build_spell_resolution(
              combat,
              turn,
              participant,
              spell,
              target_side,
              target_participant_id,
              environment_outcome,
              success_rate,
              seq
            )

          finalized_resolution = Orchestrator.finalize_resolution(combat, turn, resolution, opts)

          apply_spell_effects(
            combat,
            participant,
            spell,
            participants,
            sides,
            tags,
            environment_outcome,
            inventory_updates,
            seq,
            events,
            resolution,
            finalized_resolution
          )
      end
    end
  end

  defp resolve_passive_spell_toggle(
         combat,
         participant,
         spell,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    participant = normalize_participant_metadata(participant)

    if passive_spell_active?(participant, spell.id) do
      updated_participant = deactivate_passive_spell(participant, spell.id)
      participants = Map.put(participants, participant.id, updated_participant)
      mana = mana_state(updated_participant)

      payload = %{
        "participant_id" => participant.id,
        "spell_id" => spell.id,
        "mode" => "off",
        "reserved_mana" => mana["reserved_mana"],
        "max_mana" => mana["max_mana"]
      }

      {participants, sides, tags, inventory_updates, seq + 1,
       [event(seq, combat.turn_number, "passive_toggled", payload) | events]}
    else
      mana = mana_state(participant)

      if spell.mana_reservation > mana["max_mana"] do
        payload = %{
          "participant_id" => participant.id,
          "spell_id" => spell.id,
          "required_reservation" => spell.mana_reservation,
          "available_mana" => mana["max_mana"]
        }

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, "passive_insufficient_mana", payload) | events]}
      else
        passive_target_side = participant.side

        passive_target_participant_id =
          if spell.targeting == :self, do: participant.id, else: nil

        {participants, sides, tags, payload} =
          spell.effects
          |> Enum.reduce(
            {participants, sides, tags, %{"effects" => []}},
            fn effect, {participants_acc, sides_acc, tags_acc, payload_acc} ->
              {participants_acc, sides_acc, tags_acc, effect_payload} =
                apply_finalized_effect(
                  participant,
                  passive_target_side,
                  passive_target_participant_id,
                  spell,
                  effect,
                  participants_acc,
                  sides_acc,
                  tags_acc,
                  combat.turn_number,
                  effect.intensity
                )

              {participants_acc, sides_acc, tags_acc,
               Map.update!(payload_acc, "effects", &[effect_payload | &1])}
            end
          )

        updated_participant =
          participants
          |> Map.fetch!(participant.id)
          |> register_active_passive(spell, combat.turn_number)

        participants = Map.put(participants, participant.id, updated_participant)
        mana = mana_state(updated_participant)

        payload =
          payload
          |> Map.put("participant_id", participant.id)
          |> Map.put("spell_id", spell.id)
          |> Map.put("mode", "on")
          |> Map.put("reserved_mana", mana["reserved_mana"])
          |> Map.put("max_mana", mana["max_mana"])
          |> Map.update!("effects", &Enum.reverse(&1))

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, "passive_toggled", payload) | events]}
      end
    end
  end

  defp apply_passive_aura_tick(combat, %Participant{} = participant, tags, seq) do
    participant = normalize_participant_metadata(participant)

    {tags, aura_events, seq} =
      participant
      |> active_passives()
      |> Enum.reduce({tags, [], seq}, fn {spell_id, passive}, {tags_acc, events_acc, seq_acc} ->
        aura_effects = passive["aura_effects"] || []

        if aura_effects == [] do
          {tags_acc, events_acc, seq_acc}
        else
          next_tags =
            Enum.reduce(aura_effects, tags_acc, fn effect, inner_tags ->
              Enum.uniq(inner_tags ++ [effect["state"]])
            end)

          payload = %{
            "participant_id" => participant.id,
            "spell_id" => spell_id,
            "effects" => aura_effects
          }

          {next_tags,
           [event(seq_acc, combat.turn_number, "passive_aura_tick", payload) | events_acc],
           seq_acc + 1}
        end
      end)

    {participant, tags, Enum.reverse(aura_events), seq}
  end

  defp resolve_item_use(
         combat,
         %Action{} = action,
         %Participant{} = participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    inventory_item = action.inventory_item
    item_template = inventory_item.item_template

    action_key =
      get_in(action.payload || %{}, ["tool_action"]) ||
        get_in(action.payload || %{}, [:tool_action])

    item_action = action_key && action_definition(item_template, action_key)

    cond do
      is_nil(item_action) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_item_action", %{
             "participant_id" => participant.id,
             "inventory_item_id" => inventory_item.id,
             "action_key" => action_key
           })
           | events
         ]}

      not usable_inventory_item?(inventory_item, item_action) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "item_unavailable", %{
             "participant_id" => participant.id,
             "inventory_item_id" => inventory_item.id,
             "action_key" => action_key
           })
           | events
         ]}

      true ->
        {participants, sides, tags, payload} =
          apply_item_effects(
            combat,
            action,
            participant,
            inventory_item,
            item_action,
            participants,
            sides,
            tags
          )

        inventory_updates =
          Map.put(inventory_updates, inventory_item.id, %{
            quantity: max(inventory_item.quantity - item_action.quantity_cost, 0),
            reserved_quantity: inventory_item.reserved_quantity,
            durability: max(inventory_item.durability - item_action.durability_cost, 0)
          })

        payload =
          payload
          |> Map.put("participant_id", participant.id)
          |> Map.put("inventory_item_id", inventory_item.id)
          |> Map.put("action_key", item_action.key)
          |> Map.put("item_code", item_template.code)

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, "tool_action", payload) | events]}
    end
  end

  defp apply_spell_effects(
         combat,
         participant,
         spell,
         participants,
         sides,
         tags,
         environment_outcome,
         inventory_updates,
         seq,
         events,
         resolution,
         finalized_resolution
       ) do
    outcome = finalized_resolution["outcome"]
    target_side = resolution["target_side"]
    target_participant_id = resolution["target_participant_id"]
    orchestration = orchestration_payload(resolution, finalized_resolution)

    case outcome do
      "failure" ->
        backlash_damage =
          get_in(resolution, ["outcomes", "failure", "backlash_damage"]) ||
            spell.failure_profile.backlash_damage

        sides = apply_side_delta(sides, participant.side, -backlash_damage)

        payload = %{
          "participant_id" => participant.id,
          "spell_id" => spell.id,
          "backlash_damage" => backlash_damage,
          "orchestration" => orchestration
        }

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, "spell_failed", payload) | events]}

      _success_like ->
        selected_outcome = get_in(resolution, ["outcomes", outcome]) || %{}
        effect_ranges = selected_outcome["effect_ranges"] || []

        effect_range_map =
          Map.new(effect_ranges, fn effect_range ->
            {effect_range["effect_index"], effect_range}
          end)

        effect_pick_map =
          Map.new(finalized_resolution["effect_picks"] || [], fn effect_pick ->
            {effect_pick["effect_index"], effect_pick}
          end)

        {participants, sides, tags, payload} =
          spell.effects
          |> Kernel.++(environment_outcome.bonus_states)
          |> Enum.with_index()
          |> Enum.reduce(
            {participants, sides, tags, %{"effects" => []}},
            fn {effect, effect_index}, {participants_acc, sides_acc, tags_acc, payload_acc} ->
              effect_range = Map.fetch!(effect_range_map, effect_index)
              effect_pick = Map.fetch!(effect_pick_map, effect_index)

              {participants_acc, sides_acc, tags_acc, effect_payload} =
                apply_finalized_effect(
                  participant,
                  target_side,
                  target_participant_id,
                  spell,
                  effect,
                  participants_acc,
                  sides_acc,
                  tags_acc,
                  combat.turn_number,
                  effect_pick["intensity"]
                )

              effect_payload =
                effect_payload
                |> Map.put("effect_index", effect_index)
                |> Map.put("range", %{
                  "min" => effect_range["min"],
                  "max" => effect_range["max"]
                })

              {participants_acc, sides_acc, tags_acc,
               Map.update!(payload_acc, "effects", &[effect_payload | &1])}
            end
          )

        tags = apply_environment_tag_updates(tags, spell, environment_outcome)

        payload =
          payload
          |> Map.put("participant_id", participant.id)
          |> Map.put("spell_id", spell.id)
          |> Map.put("target_side", target_side)
          |> Map.put("target_participant_id", target_participant_id)
          |> Map.put("orchestration", orchestration)
          |> Map.update!("effects", &Enum.reverse(&1))

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, selected_outcome["event_type"], payload) | events]}
    end
  end

  defp apply_environment_tag_updates(tags, %Spell{} = spell, environment_outcome) do
    spread_tags = environment_outcome.spread_tags || []
    base_tags = Enum.uniq(tags ++ spread_tags)

    case {spell.environment_mode, environment_outcome.replacement_tags} do
      {_mode, replacement_tags} when is_list(replacement_tags) and replacement_tags != [] ->
        Enum.uniq(replacement_tags)

      {:add, _nil} ->
        Enum.uniq(base_tags ++ spell.environment_tags)

      {:replace, _nil} ->
        spell.environment_tags

      _other ->
        base_tags
    end
  end

  defp build_spell_resolution(
         combat,
         turn,
         participant,
         spell,
         target_side,
         target_participant_id,
         environment_outcome,
         success_rate,
         seq
       ) do
    partial_max = min(success_rate + spell.failure_profile.partial_success_rate, 100)
    combined_effects = spell.effects ++ environment_outcome.bonus_states

    %{
      "resolution_id" => "#{turn.number}:#{seq}:#{participant.id}:#{spell.id}",
      "combat_id" => combat.id,
      "participant_id" => participant.id,
      "spell_id" => spell.id,
      "target_side" => target_side,
      "target_participant_id" => target_participant_id,
      "outcome_windows" => %{
        "success_max" => success_rate,
        "partial_max" => partial_max,
        "failure_max" => 100
      },
      "outcomes" => %{
        "success" => %{
          "event_type" => "spell_cast",
          "effect_ranges" =>
            build_effect_ranges(combined_effects, environment_outcome.intensity_bonus, 1.0)
        },
        "partial" => %{
          "event_type" => "partial_spell_cast",
          "effect_ranges" =>
            build_effect_ranges(combined_effects, environment_outcome.intensity_bonus, 0.5)
        },
        "failure" => %{
          "event_type" => "spell_failed",
          "backlash_damage" => spell.failure_profile.backlash_damage
        }
      }
    }
  end

  defp build_effect_ranges(effects, intensity_bonus, multiplier) do
    effects
    |> Enum.with_index()
    |> Enum.map(fn {effect, effect_index} ->
      base_intensity = max(effect.intensity + intensity_bonus, 0)
      min_intensity = floor(max(base_intensity - effect.variance, 0) * multiplier)
      max_intensity = floor(max(base_intensity + effect.variance, 0) * multiplier)

      %{
        "effect_index" => effect_index,
        "state" => effect.state,
        "applies_to" => Atom.to_string(effect.applies_to),
        "min" => min(min_intensity, max_intensity),
        "max" => max(min_intensity, max_intensity),
        "duration" => effect.duration
      }
    end)
  end

  defp orchestration_payload(resolution, finalized_resolution) do
    %{
      "resolution_id" => resolution["resolution_id"],
      "mode" => finalized_resolution["orchestration_mode"] || "fallback",
      "outcome" => finalized_resolution["outcome"],
      "chosen_roll" => finalized_resolution["chosen_roll"],
      "outcome_windows" => resolution["outcome_windows"],
      "fallback_reason" => finalized_resolution["fallback_reason"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp apply_finalized_effect(
         participant,
         target_side,
         target_participant_id,
         source,
         %SpellEffect{} = effect,
         participants,
         sides,
         tags,
         turn_number,
         intensity
       ) do
    case effect.applies_to do
      :target ->
        apply_effect_to_participant_or_side(
          target_side,
          target_participant_id,
          effect,
          intensity,
          source,
          turn_number,
          participants,
          sides,
          tags
        )

      :caster ->
        apply_effect_to_participant_or_side(
          participant.side,
          participant.id,
          effect,
          intensity,
          source,
          turn_number,
          participants,
          sides,
          tags
        )

      :environment ->
        payload = %{
          "state" => effect.state,
          "intensity" => intensity,
          "applies_to" => "environment"
        }

        {participants, sides, Enum.uniq(tags ++ [effect.state]), payload}
    end
  end

  defp apply_item_effects(
         combat,
         action,
         participant,
         inventory_item,
         item_action,
         participants,
         sides,
         tags
       ) do
    target_side = resolve_target_side(action, participant, item_action, sides)
    target_participant_id = resolve_target_participant_id(action, participants, target_side)

    {participants, sides, tags, payload} =
      Enum.reduce(item_action.effects, {participants, sides, tags, %{"effects" => []}}, fn effect,
                                                                                           {participants_acc,
                                                                                            sides_acc,
                                                                                            tags_acc,
                                                                                            payload_acc} ->
        {participants_acc, sides_acc, tags_acc, effect_payload} =
          apply_effect(
            combat,
            participant,
            target_side,
            target_participant_id,
            inventory_item,
            effect,
            participants_acc,
            sides_acc,
            tags_acc,
            0,
            1.0
          )

        {participants_acc, sides_acc, tags_acc,
         Map.update!(payload_acc, "effects", &[effect_payload | &1])}
      end)

    payload =
      payload
      |> Map.put("target_side", target_side)
      |> Map.put("target_participant_id", target_participant_id)
      |> Map.update!("effects", &Enum.reverse(&1))

    {participants, sides, tags, payload}
  end

  defp apply_effect(
         combat,
         participant,
         target_side,
         target_participant_id,
         source,
         %SpellEffect{} = effect,
         participants,
         sides,
         tags,
         intensity_bonus,
         multiplier
       ) do
    intensity =
      (effect.intensity + intensity_bonus +
         RNG.bounded_noise(
           combat.seed,
           [source_id(source), participant.id, effect.state],
           effect.variance
         ))
      |> Kernel.*(multiplier)
      |> floor()
      |> max(0)

    case effect.applies_to do
      :target ->
        apply_effect_to_participant_or_side(
          target_side,
          target_participant_id,
          effect,
          intensity,
          source,
          combat.turn_number,
          participants,
          sides,
          tags
        )

      :caster ->
        apply_effect_to_participant_or_side(
          participant.side,
          participant.id,
          effect,
          intensity,
          source,
          combat.turn_number,
          participants,
          sides,
          tags
        )

      :environment ->
        payload = %{
          "state" => effect.state,
          "intensity" => intensity,
          "applies_to" => "environment"
        }

        {participants, sides, Enum.uniq(tags ++ [effect.state]), payload}
    end
  end

  defp apply_effect_to_participant_or_side(
         side,
         participant_id,
         effect,
         intensity,
         source,
         turn_number,
         participants,
         sides,
         tags
       ) do
    case effect.state do
      "impact" ->
        {participants, sides, damage_payload} =
          apply_damage(side, participant_id, intensity, participants, sides)

        {participants, sides, tags, Map.merge(damage_payload, %{"state" => effect.state})}

      "regenerating" when effect.duration == 0 ->
        sides = apply_side_delta(sides, side, intensity)
        {participants, sides, tags, %{"state" => effect.state, "healing" => intensity}}

      _other ->
        participants =
          update_participant_state(participants, participant_id, %{
            "state" => effect.state,
            "intensity" => intensity,
            "remaining_turns" => max(effect.duration, 1),
            "applied_on_turn" => turn_number,
            "source_id" => source_id(source)
          })

        {participants, sides, tags,
         %{
           "state" => effect.state,
           "intensity" => intensity,
           "duration" => max(effect.duration, 1),
           "participant_id" => participant_id
         }}
    end
  end

  defp apply_damage(side, target_participant_id, damage, participants, sides) do
    {participants, damage, absorbed} = consume_shield(side, damage, participants)

    {participants, damage, exposed_bonus} =
      consume_exposed(target_participant_id, damage, participants)

    {participants, damage, warded_reduction} =
      apply_warded(target_participant_id, damage + exposed_bonus, participants)

    total_damage = max(damage, 0)
    sides = apply_side_delta(sides, side, -total_damage)

    {participants, sides,
     %{
       "damage" => total_damage,
       "shield_absorbed" => absorbed,
       "exposed_bonus" => exposed_bonus,
       "warded_reduction" => warded_reduction,
       "target_side" => side
     }}
  end

  defp consume_shield(_side, damage, participants) when damage <= 0, do: {participants, damage, 0}

  defp consume_shield(side, damage, participants) do
    shielded_participant_id =
      participants
      |> Enum.map(fn {participant_id, participant} -> {participant_id, participant} end)
      |> Enum.filter(fn {_id, participant} ->
        participant.side == side and
          Enum.any?(participant.active_states || [], &(&1["state"] == "shielded"))
      end)
      |> Enum.sort_by(fn {_id, participant} -> participant.position end, :asc)
      |> List.first()
      |> case do
        {participant_id, _participant} -> participant_id
        nil -> nil
      end

    case shielded_participant_id do
      nil ->
        {participants, damage, 0}

      participant_id ->
        participant = Map.fetch!(participants, participant_id)

        {shield_state, remaining_states} =
          pop_first_state(participant.active_states || [], "shielded")

        absorbed = min(damage, Map.get(shield_state, "intensity", 0))

        updated_participant = %{participant | active_states: remaining_states}
        {Map.put(participants, participant_id, updated_participant), damage - absorbed, absorbed}
    end
  end

  defp consume_exposed(nil, damage, participants), do: {participants, damage, 0}

  defp consume_exposed(_participant_id, damage, participants) when damage <= 0,
    do: {participants, damage, 0}

  defp consume_exposed(participant_id, damage, participants) do
    participant = Map.get(participants, participant_id)

    if participant do
      case pop_first_state(participant.active_states || [], "exposed") do
        {nil, _states} ->
          {participants, damage, 0}

        {state, remaining_states} ->
          updated_participant = %{participant | active_states: remaining_states}

          {Map.put(participants, participant_id, updated_participant), damage,
           Map.get(state, "intensity", 0)}
      end
    else
      {participants, damage, 0}
    end
  end

  defp apply_warded(nil, damage, participants), do: {participants, damage, 0}

  defp apply_warded(_participant_id, damage, participants) when damage <= 0,
    do: {participants, damage, 0}

  defp apply_warded(participant_id, damage, participants) do
    participant = Map.get(participants, participant_id)

    if participant do
      reduction_percent =
        participant.active_states
        |> Enum.filter(&(&1["state"] == "warded"))
        |> Enum.map(&Map.get(&1, "intensity", 0))
        |> Enum.max(fn -> 0 end)
        |> clamp(0, 90)

      reduced = floor(damage * reduction_percent / 100)
      {participants, max(damage - reduced, 0), reduced}
    else
      {participants, damage, 0}
    end
  end

  defp pop_first_state(states, state_name) do
    {matched, remaining} = Enum.split_with(states, &(&1["state"] == state_name))

    case matched do
      [first | rest] -> {first, rest ++ remaining}
      [] -> {nil, states}
    end
  end

  defp update_participant_state(participants, nil, _state), do: participants

  defp update_participant_state(participants, participant_id, state) do
    Map.update!(participants, participant_id, fn participant ->
      %{participant | active_states: [state | participant.active_states || []]}
    end)
  end

  defp expire_non_periodic_states(participants, turn_number) do
    Map.new(participants, fn {participant_id, participant} ->
      active_states =
        participant.active_states
        |> Enum.reduce([], fn state, acc ->
          if periodic_state?(Map.get(state, "state")) do
            [state | acc]
          else
            if Map.get(state, "applied_on_turn") == turn_number do
              [state | acc]
            else
              remaining_turns = max(Map.get(state, "remaining_turns", 0) - 1, 0)

              if remaining_turns > 0 do
                [Map.put(state, "remaining_turns", remaining_turns) | acc]
              else
                acc
              end
            end
          end
        end)
        |> Enum.reverse()

      {participant_id, %{participant | active_states: active_states}}
    end)
  end

  defp expire_passive_spells(participants, turn_number) do
    Map.new(participants, fn {participant_id, participant} ->
      {participant_id, expire_passive_spells_for_participant(participant, turn_number)}
    end)
  end

  defp expire_passive_spells_for_participant(%Participant{} = participant, turn_number) do
    participant = normalize_participant_metadata(participant)

    {active_passives, expired_spell_ids} =
      participant
      |> active_passives()
      |> Enum.reduce({%{}, []}, fn {spell_id, passive}, {retained, expired} ->
        if passive_expired?(passive, turn_number) do
          {retained, [spell_id | expired]}
        else
          {Map.put(retained, spell_id, passive), expired}
        end
      end)

    participant
    |> remove_states_by_sources(expired_spell_ids)
    |> put_active_passives(active_passives)
    |> refresh_mana_state()
  end

  defp normalize_participant_metadata(%Participant{} = participant) do
    metadata = deep_stringify_keys(participant.metadata || %{})
    active_passives = active_passives_from_metadata(metadata)
    mana = normalized_mana_state(participant, metadata, active_passives)

    %{
      participant
      | metadata: metadata |> Map.put("active_passives", active_passives) |> Map.put("mana", mana)
    }
  end

  defp register_active_passive(%Participant{} = participant, %Spell{} = spell, turn_number) do
    aura_effects =
      Enum.map(spell.effects, fn effect ->
        %{
          "applies_to" => Atom.to_string(effect.applies_to),
          "state" => effect.state,
          "intensity" => effect.intensity
        }
      end)

    passive = %{
      "spell_id" => spell.id,
      "spell_name" => spell.name,
      "mana_reservation" => spell.mana_reservation,
      "expires_after_turn" => turn_number + passive_duration(spell) - 1,
      "aura_effects" => Enum.filter(aura_effects, &(&1["applies_to"] == "environment"))
    }

    participant
    |> put_active_passives(Map.put(active_passives(participant), spell.id, passive))
    |> refresh_mana_state()
  end

  defp deactivate_passive_spell(%Participant{} = participant, spell_id) do
    active_passives = Map.delete(active_passives(participant), spell_id)

    participant
    |> remove_states_by_sources([spell_id])
    |> put_active_passives(active_passives)
    |> refresh_mana_state()
  end

  defp passive_spell_active?(%Participant{} = participant, spell_id) do
    Map.has_key?(active_passives(participant), spell_id)
  end

  defp active_passives(%Participant{} = participant) do
    participant.metadata
    |> active_passives_from_metadata()
  end

  defp active_passives_from_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.get("active_passives", %{})
    |> deep_stringify_keys()
  end

  defp put_active_passives(%Participant{} = participant, active_passives) do
    metadata =
      participant.metadata
      |> deep_stringify_keys()
      |> Map.put("active_passives", active_passives)

    %{participant | metadata: metadata}
  end

  defp refresh_mana_state(%Participant{} = participant) do
    metadata = participant.metadata |> deep_stringify_keys()
    mana = normalized_mana_state(participant, metadata, active_passives_from_metadata(metadata))
    %{participant | metadata: Map.put(metadata, "mana", mana)}
  end

  defp mana_state(%Participant{} = participant) do
    participant
    |> normalize_participant_metadata()
    |> then(&(&1.metadata["mana"] || %{}))
  end

  defp normalized_mana_state(%Participant{} = participant, metadata, active_passives) do
    mana = deep_stringify_keys(Map.get(metadata, "mana", %{}))
    base_max_mana = Map.get(mana, "base_max_mana") || derived_max_mana(participant)

    reserved_mana =
      active_passives
      |> Enum.reduce(0, fn {_spell_id, passive}, acc ->
        acc + integer_value(passive["mana_reservation"])
      end)

    %{
      "base_max_mana" => base_max_mana,
      "reserved_mana" => reserved_mana,
      "max_mana" => max(base_max_mana - reserved_mana, 0)
    }
  end

  defp passive_duration(%Spell{} = spell) do
    spell.effects
    |> Enum.map(&max(&1.duration, 1))
    |> Enum.max(fn -> 1 end)
  end

  defp passive_expired?(passive, turn_number) do
    integer_value(passive["expires_after_turn"]) <= turn_number
  end

  defp remove_states_by_sources(%Participant{} = participant, spell_ids) do
    spell_ids = MapSet.new(spell_ids)

    active_states =
      Enum.reject(participant.active_states || [], fn state ->
        MapSet.member?(spell_ids, to_string(Map.get(state, "source_id")))
      end)

    %{participant | active_states: active_states}
  end

  defp derived_max_mana(%Participant{} = participant) do
    max(participant_level(participant) * 10, 50)
  end

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0
    end
  end

  defp integer_value(_value), do: 0

  defp deep_stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), deep_stringify_keys(value)} end)
  end

  defp deep_stringify_keys(list) when is_list(list), do: Enum.map(list, &deep_stringify_keys/1)
  defp deep_stringify_keys(value), do: value

  defp blocked_action(%Participant{} = participant, action_type) do
    active_states = participant.active_states || []

    cond do
      has_state?(active_states, "trapped") ->
        {participant, "trapped", false}

      action_type == :cast_spell and has_state?(active_states, "silenced") ->
        {participant, "silenced", false}

      has_state?(active_states, "channeling") ->
        {participant, "channeling", false}

      has_state?(active_states, "staggered") ->
        {_state, remaining_states} = pop_first_state(active_states, "staggered")
        {%{participant | active_states: remaining_states}, "staggered", true}

      true ->
        false
    end
  end

  defp spell_available?(%Participant{grimoire: nil}, _spell_id), do: false

  defp spell_available?(%Participant{grimoire: grimoire}, spell_id) do
    entries = if Ecto.assoc_loaded?(grimoire.entries), do: grimoire.entries, else: []
    Enum.any?(entries, &(&1.spell_id == spell_id))
  end

  defp has_state?(states, state_name) do
    Enum.any?(states, &(&1["state"] == state_name))
  end

  defp periodic_state?(state), do: state in ["burning", "regenerating"]

  defp participant_level(%Participant{combat_level: combat_level}) when is_integer(combat_level),
    do: combat_level

  defp participant_level(%Participant{character: %{level: level}}) when is_integer(level),
    do: level

  defp participant_level(_participant), do: 1

  defp usable_inventory_item?(%InventoryItem{} = inventory_item, %ItemAction{} = item_action) do
    MMGO.Inventory.available_quantity(inventory_item) > 0 and
      MMGO.Inventory.available_quantity(inventory_item) >= item_action.quantity_cost and
      inventory_item.durability >= item_action.durability_cost
  end

  defp action_definition(item_template, action_key) do
    Enum.find(item_template.actions || [], &(&1.key == action_key))
  end

  defp source_id(%Spell{id: id}), do: id
  defp source_id(%InventoryItem{id: id}), do: id

  defp resolve_target_side(
         %Action{target_side: target_side},
         participant,
         %Spell{targeting: targeting},
         _sides
       )
       when is_binary(target_side) and target_side != "" do
    case targeting do
      :self -> participant.side
      _other -> target_side
    end
  end

  defp resolve_target_side(
         %Action{target_side: target_side},
         participant,
         %ItemAction{targeting: targeting},
         _sides
       )
       when is_binary(target_side) and target_side != "" do
    case targeting do
      :self -> participant.side
      :ally -> participant.side
      _other -> target_side
    end
  end

  defp resolve_target_side(_action, participant, %Spell{targeting: :self}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %Spell{targeting: :ally}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %Spell{targeting: _targeting}, sides) do
    sides
    |> Map.keys()
    |> Enum.find(fn side -> side != participant.side end)
  end

  defp resolve_target_side(_action, participant, %ItemAction{targeting: :self}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %ItemAction{targeting: :ally}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %ItemAction{targeting: _targeting}, sides) do
    sides
    |> Map.keys()
    |> Enum.find(fn side -> side != participant.side end)
  end

  defp resolve_target_participant_id(
         %Action{target_participant_id: target_id},
         participants,
         _side
       )
       when is_binary(target_id) do
    if Map.has_key?(participants, target_id), do: target_id, else: nil
  end

  defp resolve_target_participant_id(_action, participants, side) do
    participants
    |> Enum.filter(fn {_participant_id, participant} ->
      participant.side == side and participant.status == :ready
    end)
    |> Enum.sort_by(fn {_participant_id, participant} -> participant.position end, :asc)
    |> List.first()
    |> case do
      {participant_id, _participant} -> participant_id
      nil -> nil
    end
  end

  defp apply_side_delta(sides, side, delta) do
    Map.update!(sides, side, fn side_data ->
      max_shared_hp = Map.get(side_data, "max_shared_hp", 100)
      shared_hp = Map.get(side_data, "shared_hp", max_shared_hp)

      Map.put(side_data, "shared_hp", clamp(shared_hp + delta, 0, max_shared_hp))
    end)
  end

  defp finalize_participants(participants, sides, winner_side) do
    if is_nil(winner_side) do
      participants
    else
      loser_side = sides |> Map.keys() |> Enum.find(&(&1 != winner_side))

      Map.new(participants, fn {participant_id, participant} ->
        status = if participant.side == loser_side, do: :defeated, else: participant.status
        {participant_id, %{participant | status: status}}
      end)
    end
  end

  defp determine_winner(sides) do
    alive_sides = Enum.filter(sides, fn {_side, data} -> Map.get(data, "shared_hp", 0) > 0 end)

    case alive_sides do
      [{winner_side, _data}] -> winner_side
      _other -> nil
    end
  end

  defp default_narration(turn_number, events, winner_side) do
    cond do
      winner_side ->
        "Ход #{turn_number} завершён: произошло #{length(events)} событий. Побеждает сторона #{winner_side}."

      true ->
        "Ход #{turn_number} завершён: произошло #{length(events)} событий."
    end
  end

  defp normalize_sides(sides) do
    Map.new(sides, fn {side, data} ->
      {to_string(side),
       %{
         "label" =>
           Map.get(data, "label") || Map.get(data, :label) || String.capitalize(to_string(side)),
         "shared_hp" => Map.get(data, "shared_hp") || Map.get(data, :shared_hp) || 100,
         "max_shared_hp" => Map.get(data, "max_shared_hp") || Map.get(data, :max_shared_hp) || 100
       }}
    end)
  end

  defp event(sequence, turn_number, event_type, payload) do
    %{
      turn_number: turn_number,
      sequence: sequence,
      event_type: event_type,
      payload: payload
    }
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
