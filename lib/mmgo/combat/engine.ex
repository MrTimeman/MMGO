defmodule MMGO.Combat.Engine do
  alias MMGO.Combat.{Action, ActionSnapshot, Combat, Participant, RNG, Turn}
  alias MMGO.Inventory.{InventoryItem, ItemAction}
  alias MMGO.Spells.{Runtime, Spell, SpellEffect}
  alias MMGO.Worlds

  @elemental_break_conditions %{fire: "fire_spell", water: "water_spell"}
  @physical_action_kinds [:strike, :sweep]
  @environment_hazards_key "environment_hazards"
  @environment_hazard_state "burning"
  @max_environment_hazards 16
  @max_environment_hazard_intensity 100
  @max_environment_hazard_duration 8

  def resolve_turn(%Combat{} = combat, %Turn{} = turn, participants, actions) do
    participants_by_id = Map.new(participants, &{&1.id, &1})
    active_participants = Enum.filter(participants, &(&1.status == :ready))
    sides = normalize_sides(combat.sides)
    environment = initial_environment(combat, sides)

    # Environmental hazards are intentionally resolved before individual state
    # ticks and actions. A hazard is only added later in this resolution, so
    # it can never damage a side on the turn that created it.
    {environment, sides, starting_seq, events} =
      tick_environment_hazards(combat, environment, sides, 1, [])

    {participants_by_id, sides, starting_seq, events} =
      apply_start_of_turn(
        combat,
        active_participants,
        participants_by_id,
        sides,
        starting_seq,
        events
      )

    actions = fill_missing_actions(actions, active_participants)

    {participants_by_id, sides, environment, inventory_updates, _final_seq, events} =
      actions
      |> Enum.sort_by(&RNG.order_key(combat.seed, [combat.turn_number, &1.participant_id]), :asc)
      |> Enum.reduce(
        {participants_by_id, sides, environment, %{}, starting_seq, events},
        fn action,
           {participants_acc, sides_acc, environment_acc, inventory_acc, seq_acc, events_acc} ->
          resolve_action(
            combat,
            action,
            participants_acc,
            sides_acc,
            environment_acc,
            inventory_acc,
            seq_acc,
            events_acc
          )
        end
      )

    participants_by_id = expire_non_periodic_states(participants_by_id, combat.turn_number)

    winner_side = determine_winner(sides)
    participants_by_id = finalize_participants(participants_by_id, sides, winner_side)
    next_turn_number = if winner_side, do: combat.turn_number, else: combat.turn_number + 1

    %{
      combat_attrs: %{
        status: if(winner_side, do: :finished, else: :active_turn),
        turn_number: next_turn_number,
        environment_tags: environment.legacy_tags,
        metadata: put_environment_hazards(combat.metadata, environment.hazards),
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
             active_states: participant.active_states
           }}
        end),
      turn_attrs: %{
        status: :resolved,
        narration: default_narration(turn.number, events, winner_side),
        resolution: %{
          "winner_side" => winner_side,
          "environment_tags" => interaction_tags(environment),
          "environment_hazards" => environment.hazards,
          "sides" => sides,
          "event_count" => length(events)
        }
      },
      inventory_updates: inventory_updates,
      create_next_turn?: is_nil(winner_side),
      events: Enum.reverse(events)
    }
  end

  defp apply_start_of_turn(combat, active_participants, participants_by_id, sides, seq, events) do
    Enum.reduce(active_participants, {participants_by_id, sides, seq, events}, fn participant,
                                                                                  {participants_acc,
                                                                                   sides_acc,
                                                                                   seq_acc,
                                                                                   events_acc} ->
      participant = decrement_cooldowns(participants_acc[participant.id])

      {participant, sides_acc, state_events, next_seq} =
        tick_states(combat, participant, sides_acc, seq_acc)

      {Map.put(participants_acc, participant.id, participant), sides_acc, next_seq,
       state_events ++ events_acc}
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
         %Action{action_type: :wait} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    participant = Map.fetch!(participants, action.participant_id)

    case {Map.get(action.payload || %{}, "auto"),
          pop_first_state(participant.active_states || [], "channeling")} do
      {true, _channeling} ->
        wait_event(combat, action, participants, sides, tags, inventory_updates, seq, events)

      {_auto?, {nil, _states}} ->
        wait_event(combat, action, participants, sides, tags, inventory_updates, seq, events)

      {_auto?, {_channeling, remaining_states}} ->
        participants =
          Map.put(participants, participant.id, %{participant | active_states: remaining_states})

        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "channeling_stopped", %{
             "participant_id" => participant.id,
             "reason" => "caster_choice"
           })
           | events
         ]}
    end
  end

  defp resolve_action(
         combat,
         %Action{action_type: :flee} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    participant = Map.fetch!(participants, action.participant_id)

    if participant.status == :ready do
      participants = Map.put(participants, participant.id, %{participant | status: :fled})
      sides = forfeit_side_if_empty(sides, participants, participant.side)

      {participants, sides, tags, inventory_updates, seq + 1,
       [
         event(seq, combat.turn_number, "fled", %{
           "participant_id" => participant.id,
           "side" => participant.side
         })
         | events
       ]}
    else
      {participants, sides, tags, inventory_updates, seq + 1,
       [event(seq, combat.turn_number, "skipped", %{"participant_id" => participant.id}) | events]}
    end
  end

  defp resolve_action(
         combat,
         %Action{action_type: :cast_spell} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
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

      true ->
        resolve_snapshot_spell_cast(
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

  defp resolve_action(
         combat,
         %Action{action_type: :use_item} = action,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
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

      true ->
        resolve_snapshot_item_use(
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

  defp resolve_snapshot_spell_cast(
         combat,
         action,
         participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    case ActionSnapshot.cast_for_resolution(action) do
      {:ok, resolved_action, spell} ->
        cond do
          not Worlds.magic_allowed_for_combat?(combat) ->
            {participants, sides, tags, inventory_updates, seq + 1,
             [
               event(seq, combat.turn_number, "magic_suppressed", %{
                 "participant_id" => participant.id,
                 "spell_id" => spell.id,
                 "location_kind" =>
                   combat.metadata["location_kind"] || combat.metadata[:location_kind]
               })
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

          Map.get(participant.cooldowns || %{}, spell.id, 0) > 0 ->
            {participants, sides, tags, inventory_updates, seq + 1,
             [
               event(seq, combat.turn_number, "spell_on_cooldown", %{
                 "participant_id" => participant.id,
                 "spell_id" => spell.id
               })
               | events
             ]}

          true ->
            resolve_spell_cast(
              combat,
              resolved_action,
              spell,
              participant,
              participants,
              sides,
              tags,
              inventory_updates,
              seq,
              events
            )
        end

      {:error, _reason} ->
        invalid_snapshot_event(
          combat,
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

  defp resolve_snapshot_item_use(
         combat,
         action,
         participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    case ActionSnapshot.item_for_resolution(action) do
      {:ok, resolved_action, item_action, item_code} ->
        cond do
          is_nil(resolved_action.inventory_item) ->
            invalid_snapshot_event(
              combat,
              participant,
              participants,
              sides,
              tags,
              inventory_updates,
              seq,
              events
            )

          resolved_action.inventory_item.character_id != participant.character_id ->
            {participants, sides, tags, inventory_updates, seq + 1,
             [
               event(seq, combat.turn_number, "unauthorized_item", %{
                 "participant_id" => participant.id,
                 "inventory_item_id" => resolved_action.inventory_item_id
               })
               | events
             ]}

          true ->
            resolve_item_use(
              combat,
              resolved_action,
              item_action,
              item_code,
              participant,
              participants,
              sides,
              tags,
              inventory_updates,
              seq,
              events
            )
        end

      {:error, _reason} ->
        invalid_snapshot_event(
          combat,
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

  defp invalid_snapshot_event(
         combat,
         participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    {participants, sides, tags, inventory_updates, seq + 1,
     [
       event(seq, combat.turn_number, "invalid_action", %{
         "participant_id" => participant.id,
         "reason" => "invalid_snapshot"
       })
       | events
     ]}
  end

  defp resolve_spell_cast(
         combat,
         action,
         spell,
         participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    interaction_tags = interaction_tags(tags)
    environment_outcome = Runtime.environment_outcome(spell, interaction_tags)

    base_success_rate =
      Runtime.success_rate(spell, participant_level(participant), div(participant.fatigue, 5))

    blindness_penalty = blindness_accuracy_penalty(participant)
    success_rate = max(base_success_rate - blindness_penalty, 0)

    partial_success_threshold =
      max(base_success_rate + spell.failure_profile.partial_success_rate - blindness_penalty, 0)

    success_roll =
      RNG.percent(combat.seed, [combat.turn_number, participant.id, spell.id, :success])

    participant =
      participant
      |> Map.update!(:fatigue, &(&1 + spell.fatigue_cost))
      |> Map.update!(:cooldowns, &Map.put(&1, spell.id, spell.cooldown_turns))

    {participant, empowerment} = consume_empowered(participant)

    participants = Map.put(participants, participant.id, participant)

    cond do
      environment_outcome.negated? ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(
             seq,
             combat.turn_number,
             "spell_negated",
             %{
               "participant_id" => participant.id,
               "spell_id" => spell.id,
               "environment_tags" => interaction_tags
             }
             |> Map.merge(empowerment_payload(empowerment))
             |> maybe_put_accuracy_penalty(blindness_penalty)
           )
           | events
         ]}

      success_roll <= success_rate ->
        apply_spell_effects(
          combat,
          action,
          participant,
          spell,
          participants,
          sides,
          tags,
          environment_outcome,
          inventory_updates,
          seq,
          events,
          empowerment.multiplier,
          "spell_cast",
          empowerment,
          blindness_penalty
        )

      success_roll <= partial_success_threshold ->
        apply_spell_effects(
          combat,
          action,
          participant,
          spell,
          participants,
          sides,
          tags,
          environment_outcome,
          inventory_updates,
          seq,
          events,
          0.5 * empowerment.multiplier,
          "partial_spell_cast",
          empowerment,
          blindness_penalty
        )

      true ->
        backlash_damage = spell.failure_profile.backlash_damage
        sides = apply_side_delta(sides, participant.side, -backlash_damage)

        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(
             seq,
             combat.turn_number,
             "spell_failed",
             %{
               "participant_id" => participant.id,
               "spell_id" => spell.id,
               "backlash_damage" => backlash_damage
             }
             |> Map.merge(empowerment_payload(empowerment))
             |> maybe_put_accuracy_penalty(blindness_penalty)
           )
           | events
         ]}
    end
  end

  defp resolve_item_use(
         combat,
         %Action{} = action,
         %ItemAction{} = item_action,
         item_code,
         %Participant{} = participant,
         participants,
         sides,
         tags,
         inventory_updates,
         seq,
         events
       ) do
    inventory_item = action.inventory_item

    cond do
      not usable_inventory_item?(inventory_item, item_action) ->
        {participants, sides, tags, inventory_updates, seq + 1,
         [
           event(seq, combat.turn_number, "item_unavailable", %{
             "participant_id" => participant.id,
             "inventory_item_id" => inventory_item.id,
             "action_key" => item_action.key
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
            reserved_quantity:
              max(inventory_item.reserved_quantity - item_action.quantity_cost, 0),
            durability: max(inventory_item.durability - item_action.durability_cost, 0)
          })

        payload =
          payload
          |> Map.put("participant_id", participant.id)
          |> Map.put("inventory_item_id", inventory_item.id)
          |> Map.put("action_key", item_action.key)
          |> Map.put("item_code", item_code)

        {participants, sides, tags, inventory_updates, seq + 1,
         [event(seq, combat.turn_number, "tool_action", payload) | events]}
    end
  end

  defp apply_spell_effects(
         combat,
         action,
         participant,
         spell,
         participants,
         sides,
         tags,
         environment_outcome,
         inventory_updates,
         seq,
         events,
         multiplier,
         event_type,
         empowerment,
         blindness_penalty
       ) do
    target_side = resolve_target_side(action, participant, spell, sides)
    target_participant_id = resolve_target_participant_id(action, participants, target_side)
    effects = spell.effects ++ environment_outcome.bonus_states

    {participants, state_breaks} =
      break_states_for_conditions(
        participants,
        spell_break_conditions(spell),
        effect_recipient_ids(effects, participant.id, target_participant_id)
      )

    {participants, sides, tags, payload} =
      Enum.reduce(
        effects,
        {participants, sides, tags, %{"effects" => []}},
        fn effect, {participants_acc, sides_acc, tags_acc, payload_acc} ->
          {participants_acc, sides_acc, tags_acc, effect_payload} =
            apply_effect(
              combat,
              participant,
              target_side,
              target_participant_id,
              spell,
              effect,
              participants_acc,
              sides_acc,
              tags_acc,
              environment_outcome.intensity_bonus,
              multiplier
            )

          {participants_acc, sides_acc, tags_acc,
           Map.update!(payload_acc, "effects", &[effect_payload | &1])}
        end
      )

    tags = update_legacy_environment_tags(tags, spell, environment_outcome)

    payload =
      payload
      |> Map.put("participant_id", participant.id)
      |> Map.put("spell_id", spell.id)
      |> Map.put("target_side", target_side)
      |> Map.put("target_participant_id", target_participant_id)
      |> Map.update!("effects", &Enum.reverse(&1))
      |> Map.merge(empowerment_payload(empowerment))
      |> maybe_put_state_breaks(state_breaks)
      |> maybe_put_accuracy_penalty(blindness_penalty)

    {participants, sides, tags, inventory_updates, seq + 1,
     [event(seq, combat.turn_number, event_type, payload) | events]}
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

    {participants, state_breaks} =
      break_states_for_conditions(
        participants,
        physical_break_conditions(item_action),
        physical_hit_recipient_ids(item_action, target_participant_id)
      )

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
      |> maybe_put_state_breaks(state_breaks)

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
        apply_environment_effect(
          combat,
          target_side,
          source,
          effect,
          intensity,
          participants,
          sides,
          tags
        )
    end
  end

  # Environment hazards deliberately live in combat metadata rather than the
  # legacy flat tag list. That gives them a bounded lifetime without changing
  # the meaning of an existing persistent environment tag.
  defp apply_environment_effect(
         combat,
         target_side,
         source,
         %SpellEffect{} = effect,
         intensity,
         participants,
         sides,
         environment
       ) do
    if burning_environment_hazard?(effect) do
      {environment, created?} =
        add_environment_hazard(
          environment,
          target_side,
          source,
          intensity,
          effect.duration,
          combat.turn_number
        )

      payload = %{
        "state" => effect.state,
        "intensity" => intensity,
        "duration" => effect.duration,
        "applies_to" => "environment",
        "side" => target_side,
        "hazard_created" => created?
      }

      {participants, sides, environment, payload}
    else
      payload = %{
        "state" => effect.state,
        "intensity" => intensity,
        "applies_to" => "environment"
      }

      {participants, sides, add_legacy_environment_tag(environment, effect.state), payload}
    end
  end

  defp burning_environment_hazard?(%SpellEffect{
         state: @environment_hazard_state,
         duration: duration
       })
       when is_integer(duration) and duration > 0,
       do: true

  defp burning_environment_hazard?(_effect), do: false

  defp add_environment_hazard(environment, side, _source, intensity, duration, turn_number)
       when is_binary(side) and is_integer(intensity) and is_integer(duration) and
              is_integer(turn_number) do
    cond do
      length(environment.hazards) >= @max_environment_hazards ->
        {environment, false}

      intensity not in 1..@max_environment_hazard_intensity ->
        {environment, false}

      duration not in 1..@max_environment_hazard_duration ->
        {environment, false}

      true ->
        hazard = %{
          "state" => @environment_hazard_state,
          "side" => side,
          "intensity" => intensity,
          "duration" => duration,
          "remaining_turns" => duration,
          "applied_on_turn" => turn_number
        }

        {%{environment | hazards: environment.hazards ++ [hazard]}, true}
    end
  end

  defp add_environment_hazard(environment, _side, _source, _intensity, _duration, _turn_number),
    do: {environment, false}

  defp add_legacy_environment_tag(environment, tag) when is_binary(tag) do
    %{environment | legacy_tags: Enum.uniq(environment.legacy_tags ++ [tag])}
  end

  defp add_legacy_environment_tag(environment, _tag), do: environment

  defp update_legacy_environment_tags(environment, spell, environment_outcome) do
    legacy_tags =
      case {spell.environment_mode, environment_outcome.replacement_tags} do
        {_mode, replacement_tags} when is_list(replacement_tags) -> replacement_tags
        {:add, _nil} -> Enum.uniq(environment.legacy_tags ++ spell.environment_tags)
        {:replace, _nil} -> spell.environment_tags
        _other -> environment.legacy_tags
      end

    %{environment | legacy_tags: legacy_tags}
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
            "source_id" => source_id(source),
            "break_conditions" => effect.break_conditions || []
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

    total_damage = max(damage + exposed_bonus, 0)

    {participants, channeling_broken?} =
      break_channeling(target_participant_id, total_damage, participants)

    sides = apply_side_delta(sides, side, -total_damage)

    {participants, sides,
     %{
       "damage" => total_damage,
       "shield_absorbed" => absorbed,
       "exposed_bonus" => exposed_bonus,
       "target_side" => side,
       "channeling_broken" => channeling_broken?
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

  defp break_channeling(_participant_id, damage, participants) when damage <= 0,
    do: {participants, false}

  defp break_channeling(nil, _damage, participants), do: {participants, false}

  defp break_channeling(participant_id, _damage, participants) do
    case Map.get(participants, participant_id) do
      nil ->
        {participants, false}

      participant ->
        case pop_first_state(participant.active_states || [], "channeling") do
          {nil, _states} ->
            {participants, false}

          {_state, remaining_states} ->
            updated_participant = %{participant | active_states: remaining_states}
            {Map.put(participants, participant_id, updated_participant), true}
        end
    end
  end

  # `empowered` is an explicit multiplier, not a damage bonus. It is consumed
  # as soon as a valid spell cast begins, including a cast later negated by the
  # environment or one that fails its success roll.
  defp consume_empowered(%Participant{} = participant) do
    case pop_first_state(participant.active_states || [], "empowered") do
      {nil, _states} ->
        {participant, %{consumed?: false, multiplier: 1}}

      {state, remaining_states} ->
        multiplier = state |> Map.get("intensity", 1) |> max(1)

        {%{participant | active_states: remaining_states},
         %{consumed?: true, multiplier: multiplier}}
    end
  end

  defp empowerment_payload(%{consumed?: false}), do: %{}

  defp empowerment_payload(%{consumed?: true, multiplier: multiplier}) do
    %{"empowerment" => %{"consumed" => true, "multiplier" => multiplier}}
  end

  defp blindness_accuracy_penalty(%Participant{} = participant) do
    participant.active_states
    |> List.wrap()
    |> Enum.reduce(0, fn state, penalty ->
      case state do
        %{"state" => "blinded", "intensity" => intensity} when is_integer(intensity) ->
          penalty + max(intensity, 0)

        _other ->
          penalty
      end
    end)
    |> min(100)
  end

  defp maybe_put_accuracy_penalty(payload, 0), do: payload

  defp maybe_put_accuracy_penalty(payload, penalty),
    do: Map.put(payload, "accuracy_penalty", penalty)

  # GDD §2.3 break conditions are an intentionally closed, data-backed
  # vocabulary. A successful fire or water spell can break states only on a
  # participant receiving one of its effects. `physical_hit` is emitted only
  # by direct `:strike`/`:sweep` tool actions that contain a target impact.
  # The break pass happens before that action's effects are applied, so an
  # effect cannot remove a state it created in the same action.
  defp spell_break_conditions(%Spell{school: school}) do
    case Map.fetch(@elemental_break_conditions, school) do
      {:ok, condition} -> [condition]
      :error -> []
    end
  end

  defp physical_break_conditions(%ItemAction{action_kind: action_kind, effects: effects})
       when action_kind in @physical_action_kinds do
    if Enum.any?(effects || [], &direct_impact_effect?/1), do: ["physical_hit"], else: []
  end

  defp physical_break_conditions(_item_action), do: []

  defp direct_impact_effect?(%SpellEffect{
         applies_to: :target,
         state: "impact",
         intensity: intensity
       })
       when is_integer(intensity) and intensity > 0,
       do: true

  defp direct_impact_effect?(_effect), do: false

  defp effect_recipient_ids(effects, caster_id, target_participant_id) do
    effects
    |> Enum.flat_map(fn
      %SpellEffect{applies_to: :target} -> [target_participant_id]
      %SpellEffect{applies_to: :caster} -> [caster_id]
      _effect -> []
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp physical_hit_recipient_ids(item_action, target_participant_id) do
    case physical_break_conditions(item_action) do
      [] -> []
      _conditions -> List.wrap(target_participant_id)
    end
  end

  defp break_states_for_conditions(participants, [], _recipient_ids), do: {participants, []}

  defp break_states_for_conditions(participants, conditions, recipient_ids) do
    recipient_ids
    |> Enum.uniq()
    |> Enum.reduce({participants, []}, fn participant_id, {participants_acc, breaks_acc} ->
      case Map.get(participants_acc, participant_id) do
        %Participant{} = participant ->
          {remaining_states, participant_breaks} =
            Enum.reduce(participant.active_states || [], {[], []}, fn state,
                                                                      {states_acc,
                                                                       breaks_for_participant} ->
              case matching_break_condition(state, conditions) do
                nil ->
                  {[state | states_acc], breaks_for_participant}

                condition ->
                  break = %{
                    "participant_id" => participant.id,
                    "state" => Map.get(state, "state"),
                    "condition" => condition
                  }

                  {states_acc, [break | breaks_for_participant]}
              end
            end)

          participant_breaks = Enum.reverse(participant_breaks)

          if participant_breaks == [] do
            {participants_acc, breaks_acc}
          else
            updated_participant = %{
              participant
              | active_states: Enum.reverse(remaining_states)
            }

            {Map.put(participants_acc, participant.id, updated_participant),
             breaks_acc ++ participant_breaks}
          end

        _other ->
          {participants_acc, breaks_acc}
      end
    end)
  end

  defp matching_break_condition(state, conditions) when is_map(state) do
    state_conditions = state |> Map.get("break_conditions", []) |> List.wrap()
    Enum.find(conditions, &(&1 in state_conditions))
  end

  defp matching_break_condition(_state, _conditions), do: nil

  defp maybe_put_state_breaks(payload, []), do: payload

  defp maybe_put_state_breaks(payload, state_breaks),
    do: Map.put(payload, "state_breaks", state_breaks)

  defp wait_event(combat, action, participants, sides, tags, inventory_updates, seq, events) do
    {participants, sides, tags, inventory_updates, seq + 1,
     [
       event(seq, combat.turn_number, "wait", %{"participant_id" => action.participant_id})
       | events
     ]}
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
    inventory_item.quantity > 0 and inventory_item.quantity >= item_action.quantity_cost and
      inventory_item.durability >= item_action.durability_cost
  end

  defp source_id(%Spell{id: id}), do: id
  defp source_id(%InventoryItem{id: id}), do: id

  defp resolve_target_side(
         %Action{target_side: target_side},
         participant,
         %Spell{targeting: targeting},
         sides
       ) do
    resolve_legal_target_side(targeting, target_side, participant, sides)
  end

  defp resolve_target_side(
         %Action{target_side: target_side},
         participant,
         %ItemAction{targeting: targeting},
         sides
       ) do
    resolve_legal_target_side(targeting, target_side, participant, sides)
  end

  # Action snapshots have already validated targets. This fallback still keeps
  # old persisted actions from injecting a non-existent side into Map.update!.
  defp resolve_legal_target_side(targeting, _target_side, participant, _sides)
       when targeting in [:self, :ally],
       do: participant.side

  defp resolve_legal_target_side(_targeting, target_side, participant, sides)
       when is_binary(target_side) do
    if Map.has_key?(sides, target_side) and target_side != participant.side do
      target_side
    else
      opposing_side(participant, sides)
    end
  end

  defp resolve_legal_target_side(_targeting, _target_side, participant, sides),
    do: opposing_side(participant, sides)

  defp opposing_side(participant, sides) do
    sides
    |> Map.keys()
    |> Enum.find(fn side -> side != participant.side end)
  end

  defp resolve_target_participant_id(
         %Action{target_participant_id: target_id},
         participants,
         side
       )
       when is_binary(target_id) do
    case Map.get(participants, target_id) do
      %{side: ^side, status: :ready} -> target_id
      _other -> first_ready_participant_on_side(participants, side)
    end
  end

  defp resolve_target_participant_id(_action, participants, side) do
    first_ready_participant_on_side(participants, side)
  end

  defp first_ready_participant_on_side(participants, side) do
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
        status =
          cond do
            participant.status == :fled -> :fled
            participant.side == loser_side -> :defeated
            true -> participant.status
          end

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

  defp forfeit_side_if_empty(sides, participants, side) do
    ready_member? =
      Enum.any?(participants, fn {_id, participant} ->
        participant.side == side and participant.status == :ready
      end)

    if ready_member? do
      sides
    else
      Map.update(sides, side, %{"shared_hp" => 0}, &Map.put(&1, "shared_hp", 0))
    end
  end

  defp default_narration(turn_number, events, winner_side) do
    cond do
      winner_side ->
        "Ход #{turn_number} завершён, событий: #{length(events)}. Победила сторона «#{narration_side_label(winner_side)}»."

      true ->
        "Ход #{turn_number} завершён, событий: #{length(events)}."
    end
  end

  defp narration_side_label(side) when side in ["attackers", :attackers], do: "нападающие"
  defp narration_side_label(side) when side in ["defenders", :defenders], do: "защитники"
  defp narration_side_label(side) when side in ["party", :party], do: "отряд"
  defp narration_side_label(side) when side in ["encounter", :encounter], do: "противник"
  defp narration_side_label(_side), do: "неизвестная сторона"

  defp initial_environment(%Combat{} = combat, sides) do
    %{
      legacy_tags: legacy_environment_tags(combat.environment_tags),
      hazards: load_environment_hazards(combat.metadata, sides, combat.turn_number)
    }
  end

  # Only the stored, canonical hazard shape can deal damage. Invalid metadata
  # is discarded rather than coerced, so a corrupted row cannot create an
  # unbounded or side-injected environmental effect.
  defp load_environment_hazards(metadata, sides, turn_number) when is_map(sides) do
    metadata
    |> metadata_environment_hazards()
    |> case do
      hazards when is_list(hazards) ->
        hazards
        |> Enum.take(@max_environment_hazards)
        |> Enum.reduce([], fn hazard, acc ->
          case normalize_environment_hazard(hazard, sides, turn_number) do
            {:ok, normalized} -> [normalized | acc]
            :error -> acc
          end
        end)
        |> Enum.reverse()

      _other ->
        []
    end
  end

  defp metadata_environment_hazards(metadata) when is_map(metadata),
    do: Map.get(metadata, @environment_hazards_key)

  defp metadata_environment_hazards(_metadata), do: nil

  defp normalize_environment_hazard(hazard, sides, turn_number) when is_map(hazard) do
    with @environment_hazard_state <- Map.get(hazard, "state"),
         side when is_binary(side) <- Map.get(hazard, "side"),
         true <- Map.has_key?(sides, side),
         intensity when is_integer(intensity) <- Map.get(hazard, "intensity"),
         true <- intensity in 1..@max_environment_hazard_intensity,
         duration when is_integer(duration) <- Map.get(hazard, "duration"),
         true <- duration in 1..@max_environment_hazard_duration,
         remaining_turns when is_integer(remaining_turns) <- Map.get(hazard, "remaining_turns"),
         true <- remaining_turns in 1..duration,
         applied_on_turn when is_integer(applied_on_turn) <- Map.get(hazard, "applied_on_turn"),
         true <- applied_on_turn >= 1 and applied_on_turn < turn_number do
      {:ok,
       %{
         "state" => @environment_hazard_state,
         "side" => side,
         "intensity" => intensity,
         "duration" => duration,
         "remaining_turns" => remaining_turns,
         "applied_on_turn" => applied_on_turn
       }}
    else
      _other -> :error
    end
  end

  defp normalize_environment_hazard(_hazard, _sides, _turn_number), do: :error

  defp tick_environment_hazards(combat, environment, sides, seq, events) do
    {remaining_hazards, sides, next_seq, events} =
      Enum.reduce(environment.hazards, {[], sides, seq, events}, fn hazard,
                                                                    {hazards_acc, sides_acc,
                                                                     seq_acc, events_acc} ->
        remaining_turns = hazard["remaining_turns"] - 1
        intensity = hazard["intensity"]
        side = hazard["side"]
        sides_acc = apply_side_delta(sides_acc, side, -intensity)

        updated_hazards =
          if remaining_turns > 0 do
            [Map.put(hazard, "remaining_turns", remaining_turns) | hazards_acc]
          else
            hazards_acc
          end

        event =
          event(seq_acc, combat.turn_number, "environment_hazard_tick", %{
            "state" => hazard["state"],
            "side" => side,
            "damage" => intensity,
            "remaining_turns" => remaining_turns,
            "expired" => remaining_turns == 0
          })

        {updated_hazards, sides_acc, seq_acc + 1, [event | events_acc]}
      end)

    {%{environment | hazards: Enum.reverse(remaining_hazards)}, sides, next_seq, events}
  end

  # The engine resolves interaction rules against this transient view. The
  # persisted `environment_tags` field remains the backwards-compatible flat
  # tag list, while active hazards add tags only for as long as they exist.
  defp interaction_tags(%{legacy_tags: legacy_tags, hazards: hazards}) do
    Enum.uniq(legacy_tags ++ Enum.map(hazards, &Map.fetch!(&1, "state")))
  end

  defp put_environment_hazards(metadata, []) when is_map(metadata),
    do: Map.delete(metadata, @environment_hazards_key)

  defp put_environment_hazards(metadata, hazards) when is_map(metadata),
    do: Map.put(metadata, @environment_hazards_key, hazards)

  defp put_environment_hazards(_metadata, []), do: %{}

  defp put_environment_hazards(_metadata, hazards),
    do: %{@environment_hazards_key => hazards}

  defp legacy_environment_tags(tags) when is_list(tags), do: tags
  defp legacy_environment_tags(_tags), do: []

  defp normalize_sides(sides) do
    Map.new(sides, fn {side, data} ->
      {to_string(side),
       %{
         "label" => Map.get(data, "label") || Map.get(data, :label) || side_label(side),
         "shared_hp" => Map.get(data, "shared_hp") || Map.get(data, :shared_hp) || 100,
         "max_shared_hp" => Map.get(data, "max_shared_hp") || Map.get(data, :max_shared_hp) || 100
       }}
    end)
  end

  defp side_label(side) when side in ["attackers", :attackers], do: "Нападающие"
  defp side_label(side) when side in ["defenders", :defenders], do: "Защитники"
  defp side_label(side) when side in ["party", :party], do: "Отряд"
  defp side_label(side) when side in ["encounter", :encounter], do: "Противник"
  defp side_label(_side), do: "Сторона"

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
