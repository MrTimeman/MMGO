defmodule MMGO.Combat.Engine do
  alias MMGO.Combat.{Action, Combat, Participant, RNG, Turn}
  alias MMGO.Spells.{Runtime, Spell, SpellEffect}

  def resolve_turn(%Combat{} = combat, %Turn{} = turn, participants, actions) do
    participants_by_id = Map.new(participants, &{&1.id, &1})
    active_participants = Enum.filter(participants, &(&1.status == :ready))
    sides = normalize_sides(combat.sides)
    environment_tags = combat.environment_tags || []

    {participants_by_id, sides, starting_seq, events} =
      apply_start_of_turn(combat, active_participants, participants_by_id, sides, 1, [])

    actions = fill_missing_actions(actions, active_participants)

    {participants_by_id, sides, environment_tags, _final_seq, events} =
      actions
      |> Enum.sort_by(&RNG.order_key(combat.seed, [combat.turn_number, &1.participant_id]), :asc)
      |> Enum.reduce(
        {participants_by_id, sides, environment_tags, starting_seq, events},
        fn action, {participants_acc, sides_acc, tags_acc, seq_acc, events_acc} ->
          resolve_action(
            combat,
            action,
            participants_acc,
            sides_acc,
            tags_acc,
            seq_acc,
            events_acc
          )
        end
      )

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
             active_states: participant.active_states
           }}
        end),
      turn_attrs: %{
        status: :resolved,
        narration: default_narration(turn.number, events, winner_side),
        resolution: %{
          "winner_side" => winner_side,
          "environment_tags" => environment_tags,
          "sides" => sides,
          "event_count" => length(events)
        }
      },
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
      Enum.reduce(participant.active_states || [], {[], sides, [], seq}, fn state,
                                                                            {states_acc,
                                                                             sides_acc,
                                                                             events_acc, seq_acc} ->
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
      end)

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
         seq,
         events
       ) do
    {participants, sides, tags, seq + 1,
     [
       event(seq, combat.turn_number, "wait", %{"participant_id" => action.participant_id})
       | events
     ]}
  end

  defp resolve_action(
         combat,
         %Action{action_type: :cast_spell} = action,
         participants,
         sides,
         tags,
         seq,
         events
       ) do
    participant = Map.fetch!(participants, action.participant_id)

    cond do
      participant.status != :ready ->
        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "skipped", %{"participant_id" => participant.id})
           | events
         ]}

      is_nil(action.spell) ->
        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "invalid_action", %{"participant_id" => participant.id})
           | events
         ]}

      action.spell.creator_character_id != participant.character_id ->
        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "unauthorized_spell", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell_id
           })
           | events
         ]}

      Map.get(participant.cooldowns || %{}, action.spell.id, 0) > 0 ->
        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "spell_on_cooldown", %{
             "participant_id" => participant.id,
             "spell_id" => action.spell.id
           })
           | events
         ]}

      true ->
        resolve_spell_cast(combat, action, participant, participants, sides, tags, seq, events)
    end
  end

  defp resolve_spell_cast(combat, action, participant, participants, sides, tags, seq, events) do
    spell = action.spell
    environment_outcome = Runtime.environment_outcome(spell, tags)

    success_rate =
      Runtime.success_rate(spell, participant.character.level, div(participant.fatigue, 5))

    success_roll =
      RNG.percent(combat.seed, [combat.turn_number, participant.id, spell.id, :success])

    participant =
      participant
      |> Map.update!(:fatigue, &(&1 + spell.fatigue_cost))
      |> Map.update!(:cooldowns, &Map.put(&1, spell.id, spell.cooldown_turns))

    participants = Map.put(participants, participant.id, participant)

    cond do
      environment_outcome.negated? ->
        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "spell_negated", %{
             "participant_id" => participant.id,
             "spell_id" => spell.id,
             "environment_tags" => tags
           })
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
          seq,
          events,
          1.0,
          "spell_cast"
        )

      success_roll <= success_rate + spell.failure_profile.partial_success_rate ->
        apply_spell_effects(
          combat,
          action,
          participant,
          spell,
          participants,
          sides,
          tags,
          environment_outcome,
          seq,
          events,
          0.5,
          "partial_spell_cast"
        )

      true ->
        backlash_damage = spell.failure_profile.backlash_damage
        sides = apply_side_delta(sides, participant.side, -backlash_damage)

        {participants, sides, tags, seq + 1,
         [
           event(seq, combat.turn_number, "spell_failed", %{
             "participant_id" => participant.id,
             "spell_id" => spell.id,
             "backlash_damage" => backlash_damage
           })
           | events
         ]}
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
         seq,
         events,
         multiplier,
         event_type
       ) do
    target_side = resolve_target_side(action, participant, spell, sides)
    target_participant_id = resolve_target_participant_id(action, participants, target_side)

    {participants, sides, tags, payload} =
      Enum.reduce(
        spell.effects ++ environment_outcome.bonus_states,
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

    tags =
      case {spell.environment_mode, environment_outcome.replacement_tags} do
        {_mode, replacement_tags} when is_list(replacement_tags) -> replacement_tags
        {:add, _nil} -> Enum.uniq(tags ++ spell.environment_tags)
        {:replace, _nil} -> spell.environment_tags
        _other -> tags
      end

    payload =
      payload
      |> Map.put("participant_id", participant.id)
      |> Map.put("spell_id", spell.id)
      |> Map.put("target_side", target_side)
      |> Map.put("target_participant_id", target_participant_id)
      |> Map.update!("effects", &Enum.reverse(&1))

    {participants, sides, tags, seq + 1,
     [event(seq, combat.turn_number, event_type, payload) | events]}
  end

  defp apply_effect(
         combat,
         participant,
         target_side,
         target_participant_id,
         spell,
         %SpellEffect{} = effect,
         participants,
         sides,
         tags,
         intensity_bonus,
         multiplier
       ) do
    intensity =
      (effect.intensity + intensity_bonus +
         RNG.bounded_noise(combat.seed, [spell.id, participant.id, effect.state], effect.variance))
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
          spell,
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
          spell,
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
         spell,
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
            "source_spell_id" => spell.id
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
    sides = apply_side_delta(sides, side, -total_damage)

    {participants, sides,
     %{
       "damage" => total_damage,
       "shield_absorbed" => absorbed,
       "exposed_bonus" => exposed_bonus,
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

  defp resolve_target_side(_action, participant, %Spell{targeting: :self}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %Spell{targeting: :ally}, _sides),
    do: participant.side

  defp resolve_target_side(_action, participant, %Spell{targeting: _targeting}, sides) do
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
        "Turn #{turn_number} resolved with #{length(events)} events. #{winner_side} wins the combat."

      true ->
        "Turn #{turn_number} resolved with #{length(events)} events."
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
