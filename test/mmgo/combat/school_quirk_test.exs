defmodule MMGO.Combat.SchoolQuirkTest do
  use ExUnit.Case, async: true

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, RNG, Turn}
  alias MMGO.Spells.{FailureProfile, Spell, SpellEffect}

  test "fire escalation grows burning after each deterministic tick" do
    spell = spell(:fire, :escalation, effect("burning", 5, 0, 2))
    first = resolve(spell)
    defender = updated_participant(first, "p2")

    assert [%{"state" => "burning", "intensity" => 5, "escalating" => true}] =
             Enum.map(defender.active_states, &Map.take(&1, ["state", "intensity", "escalating"]))

    second =
      Engine.resolve_turn(
        %{combat() | turn_number: 2, sides: first.combat_attrs.sides},
        %Turn{number: 2, status: :locked},
        [participant("p1", "attackers"), defender],
        []
      )

    assert [%{"state" => "burning", "intensity" => 7}] =
             Enum.map(updated_participant(second, "p2").active_states, fn state ->
               Map.take(state, ["state", "intensity"])
             end)
  end

  test "water replaces the environment and earth states persist without a timer" do
    water =
      %{
        spell(:water, :environment_shift, effect("frozen", 3, 0, 1))
        | environment_mode: :add,
          environment_tags: ["flooded"]
      }

    water_resolution = resolve(water, %{combat() | environment_tags: ["burning"]})
    assert water_resolution.combat_attrs.environment_tags == ["flooded"]

    earth = spell(:earth, :persistence, effect("shielded", 6, 0, 1, :caster))
    first = resolve(earth)
    attacker = updated_participant(first, "p1")

    second =
      Engine.resolve_turn(
        %{combat() | turn_number: 2, sides: first.combat_attrs.sides},
        %Turn{number: 2, status: :locked},
        [attacker, participant("p2", "defenders")],
        []
      )

    assert Enum.any?(updated_participant(second, "p1").active_states, fn state ->
             state["state"] == "shielded" and state["persistent"] == true and
               "physical_hit" in state["break_conditions"]
           end)
  end

  test "air resolves first while life strengthens regeneration" do
    ordinary = spell(:fire, nil, effect("impact", 4, 0, 0))
    air = %{spell(:air, :tempo, effect("impact", 4, 0, 0)) | id: "air-spell"}

    resolution =
      Engine.resolve_turn(combat(), %Turn{number: 1, status: :locked}, participants(), [
        action("p1", ordinary, "defenders"),
        action("p2", air, "attackers")
      ])

    [first_cast | _rest] = Enum.filter(resolution.events, &(&1.event_type == "spell_cast"))
    assert first_cast.payload["participant_id"] == "p2"
    assert first_cast.payload["school_quirk"]["id"] == "tempo"

    life = spell(:life, :vitality, effect("regenerating", 10, 0, 2, :caster))
    life_resolution = resolve(life)

    assert Enum.any?(updated_participant(life_resolution, "p1").active_states, fn state ->
             state["state"] == "regenerating" and state["intensity"] == 15 and
               state["remaining_turns"] == 3
           end)
  end

  test "death harvests an enemy state back into the caster's mana" do
    death = spell(:death, :harvest, effect("exposed", 2, 0, 1))
    attacker = %{participant("p1", "attackers") | mana: 40}

    defender = %{
      participant("p2", "defenders")
      | active_states: [%{"state" => "frozen", "intensity" => 4, "remaining_turns" => 2}]
    }

    resolution =
      Engine.resolve_turn(combat(), %Turn{number: 1, status: :locked}, [attacker, defender], [
        action("p1", death, "defenders")
      ])

    cast = Enum.find(resolution.events, &(&1.event_type == "spell_cast"))

    assert cast.payload["school_quirk"]["details"] == %{
             "consumed_state" => "frozen",
             "recovered_mana" => 4
           }

    # 40 in the pool, 10 back at the start of the turn, 4 harvested, 4 spent.
    assert updated_participant(resolution, "p1").mana == 50

    refute Enum.any?(
             updated_participant(resolution, "p2").active_states,
             &(&1["state"] == "frozen")
           )
  end

  test "chaos widens variance while order removes it" do
    chaos = spell(:chaos, :volatility, effect("impact", 10, 1, 0))
    chaos_resolution = resolve(chaos)
    chaos_cast = Enum.find(chaos_resolution.events, &(&1.event_type == "spell_cast"))

    expected =
      10 + RNG.bounded_noise(combat().seed, [chaos.id, "p1", "impact"], 10)

    assert [%{"damage" => ^expected}] =
             Enum.map(chaos_cast.payload["effects"], &Map.take(&1, ["damage"]))

    order = spell(:order, :precision, effect("impact", 10, 9, 0))
    order_resolution = resolve(order)
    order_cast = Enum.find(order_resolution.events, &(&1.event_type == "spell_cast"))

    assert [%{"damage" => 10}] =
             Enum.map(order_cast.payload["effects"], &Map.take(&1, ["damage"]))
  end

  defp resolve(spell, combat_value \\ combat()) do
    Engine.resolve_turn(
      combat_value,
      %Turn{number: combat_value.turn_number, status: :locked},
      participants(),
      [
        action("p1", spell, "defenders")
      ]
    )
  end

  defp combat do
    %Combat{
      id: "quirk-combat",
      turn_number: 1,
      seed: 12_345,
      environment_tags: [],
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participants, do: [participant("p1", "attackers"), participant("p2", "defenders")]

  defp participant(id, side) do
    %Participant{
      id: id,
      character_id: "character-#{id}",
      side: side,
      position: 0,
      status: :ready,
      combat_level: 10,
      max_mana: 100,
      mana: 100,
      locked_mana: 0,
      cooldowns: %{},
      active_states: [],
      character: %Character{id: "character-#{id}", level: 10}
    }
  end

  defp spell(school, quirk, effect) do
    %Spell{
      id: "#{school}-spell",
      school: school,
      school_quirk: quirk,
      targeting: if(effect.applies_to == :caster, do: :self, else: :enemy),
      delivery_form: :sphere,
      fatigue_cost: 4,
      cooldown_turns: 0,
      environment_tags: [],
      environment_mode: :none,
      effects: [effect],
      interaction_rules: [],
      failure_profile: %FailureProfile{
        difficulty: 1,
        base_success_rate: 100,
        partial_success_rate: 0,
        backlash_damage: 0
      }
    }
  end

  defp effect(state, intensity, variance, duration, applies_to \\ :target) do
    %SpellEffect{
      applies_to: applies_to,
      state: state,
      intensity: intensity,
      variance: variance,
      duration: duration,
      tags: [],
      break_conditions: []
    }
  end

  defp action(participant_id, spell, target_side) do
    %Action{
      participant_id: participant_id,
      action_type: :cast_spell,
      spell: spell,
      spell_id: spell.id,
      target_side: target_side
    }
  end

  defp updated_participant(resolution, participant_id) do
    attrs = Map.fetch!(resolution.participant_updates, participant_id)

    struct(
      participant(participant_id, if(participant_id == "p1", do: "attackers", else: "defenders")),
      attrs
    )
  end
end
