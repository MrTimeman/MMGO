defmodule MMGO.Combat.ManaTest do
  @moduledoc """
  The mana economy: a bounded pool, refilled a share at a time, that a spell can
  genuinely fail to afford.
  """

  use ExUnit.Case, async: true

  alias MMGO.Arena.{Ladder, RoomRules}
  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, Turn}
  alias MMGO.Spells.Compiler
  alias MMGO.Spells.{FailureProfile, Spell, SpellEffect}

  test "a cast is paid for out of the pool" do
    spell = spell_fixture(30)
    [attacker, defender] = participants_fixture()

    resolution = resolve([attacker, defender], [cast(attacker, spell)])

    # Full pool, so the turn's regen is wasted and only the cost lands.
    assert resolution.participant_updates[attacker.id].mana == 70
  end

  test "an empty pool refuses the cast rather than running it for free" do
    spell = spell_fixture(30)
    [attacker, defender] = participants_fixture()
    attacker = %{attacker | mana: 4}

    resolution = resolve([attacker, defender], [cast(attacker, spell)])

    assert %{event_type: "insufficient_mana", payload: payload} =
             Enum.find(resolution.events, &(&1.event_type == "insufficient_mana"))

    assert payload["cost"] == 30
    refute Enum.any?(resolution.events, &(&1.event_type == "spell_cast"))

    # The turn's regen still arrives; nothing is spent.
    assert resolution.participant_updates[attacker.id].mana == 14
    assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 100
  end

  test "the pool returns a share of itself each turn and never overfills" do
    [attacker, defender] = participants_fixture()
    attacker = %{attacker | mana: 30}

    resolution = resolve([attacker, defender], [])
    assert resolution.participant_updates[attacker.id].mana == 40

    full = resolve([%{attacker | mana: 100}, defender], [])
    assert full.participant_updates[attacker.id].mana == 100
  end

  test "a room played under the unlimited rule never depletes" do
    spell = spell_fixture(30)
    [attacker, defender] = participants_fixture()
    attacker = %{attacker | mana: 1}

    combat = %{
      combat_fixture()
      | metadata: %{RoomRules.metadata_key() => %{"mana" => "unlimited"}}
    }

    resolution =
      Engine.resolve_turn(combat, %Turn{number: 1, status: :locked}, [attacker, defender], [
        cast(attacker, spell)
      ])

    assert Enum.any?(resolution.events, &(&1.event_type == "spell_cast"))
    assert resolution.participant_updates[attacker.id].mana == 100
  end

  # The two tables in the design — pools by division, cost by craft power — have
  # to meet: the strongest spell a rank may legally wield should cost a rising
  # share of that rank's pool, so the top of the ladder commits more to a cast
  # than the bottom does.
  test "the strongest spell a rank may wield costs it more of its pool as the ladder rises" do
    shares =
      for division <- Ladder.keys() do
        strongest = strongest_legal_power(division)
        cost = Compiler.power_budget(strongest).fatigue_cost

        cost / Ladder.max_mana_for(division)
      end

    assert shares == Enum.sort(shares)
    assert List.first(shares) < 0.2
    assert List.last(shares) > 0.3
  end

  # The last power that still reads as this division rather than the next one.
  defp strongest_legal_power(division) do
    1..60
    |> Enum.filter(&(Ladder.division_for_power(&1) == division))
    |> Enum.max()
  end

  defp resolve(participants, actions) do
    Engine.resolve_turn(
      combat_fixture(),
      %Turn{number: 1, status: :locked},
      participants,
      actions
    )
  end

  defp cast(participant, spell) do
    %Action{
      participant_id: participant.id,
      action_type: :cast_spell,
      spell: spell,
      spell_id: spell.id,
      target_side: "defenders"
    }
  end

  defp combat_fixture do
    %Combat{
      id: "mana-combat",
      turn_number: 1,
      seed: 4_242,
      environment_tags: [],
      metadata: %{},
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participants_fixture do
    [
      participant("p1", "attackers", "c1"),
      participant("p2", "defenders", "c2")
    ]
  end

  defp participant(id, side, character_id) do
    %Participant{
      id: id,
      character_id: character_id,
      side: side,
      position: 0,
      status: :ready,
      combat_level: 10,
      rank: :initiate,
      max_mana: 100,
      mana: 100,
      locked_mana: 0,
      cooldowns: %{},
      active_states: [],
      character: %Character{id: character_id, level: 10}
    }
  end

  defp spell_fixture(cost) do
    %Spell{
      id: "mana-spell",
      creator_character_id: "c1",
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      power: 10,
      fatigue_cost: cost,
      cooldown_turns: 0,
      environment_tags: [],
      environment_mode: :none,
      effects: [
        %SpellEffect{
          applies_to: :target,
          state: "impact",
          intensity: 10,
          variance: 0,
          duration: 0,
          tags: []
        }
      ],
      interaction_rules: [],
      failure_profile: %FailureProfile{
        difficulty: 1,
        base_success_rate: 100,
        partial_success_rate: 0,
        backlash_damage: 0,
        volatility: 0
      }
    }
  end
end
