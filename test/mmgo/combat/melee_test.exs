defmodule MMGO.Combat.MeleeTest do
  @moduledoc """
  Melee inside the economy: a summoned weapon costs mana, rolls for accuracy,
  and cares about the ground it is swung on.
  """

  use ExUnit.Case, async: true

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, Turn}

  @weapon %{
    "state" => "summoned_weapon",
    "source_spell_id" => "spell-1",
    "display_name" => "Призванный клинок",
    "power" => 12,
    "remaining_turns" => 3,
    "applied_on_turn" => 1
  }

  describe "accuracy" do
    test "clear ground favours a blade and broken ground does not" do
      participant = participant("p1", "attackers")

      assert Engine.melee_accuracy(participant, ["clear"]) >
               Engine.melee_accuracy(participant, [])

      assert Engine.melee_accuracy(participant, ["ice"]) <
               Engine.melee_accuracy(participant, [])

      assert Engine.melee_accuracy(participant, ["rubble", "flooded"]) <
               Engine.melee_accuracy(participant, ["rubble"])
    end

    test "the caster's own state is taxed the same way a spell is" do
      blinded = %{
        participant("p1", "attackers")
        | active_states: [%{"state" => "blinded", "intensity" => 20}]
      }

      drained = %{participant("p1", "attackers") | mana: 20}

      assert Engine.melee_accuracy(blinded, []) < Engine.melee_accuracy(participant(), [])
      assert Engine.melee_accuracy(drained, []) < Engine.melee_accuracy(participant(), [])
    end

    test "accuracy stays inside the roll" do
      hopeless = %{
        participant("p1", "attackers")
        | mana: 0,
          active_states: [%{"state" => "blinded", "intensity" => 100}]
      }

      assert Engine.melee_accuracy(hopeless, ["ice", "flooded", "rubble", "gale"]) == 5
      assert Engine.melee_accuracy(participant(), ["clear", "crystal", "warded"]) <= 100
    end

    test "an unknown environment tag is neutral ground" do
      assert Engine.melee_accuracy(participant(), ["charged-fire", "collapsed-reality"]) ==
               Engine.melee_accuracy(participant(), [])
    end
  end

  describe "cost" do
    test "a swing is paid for out of the pool" do
      resolution = strike(4_242, participant_with_weapon())

      assert %{event_type: "manifestation_strike", payload: payload} =
               Enum.find(resolution.events, &(&1.event_type == "manifestation_strike"))

      assert payload["mana_cost"] == 6
      # 100 in the pool, capped regen, six spent on the swing.
      assert resolution.participant_updates["p1"].mana == 94
    end

    test "an empty pool cannot swing at all" do
      # A heavy blade costs more than a drained caster gets back in a turn.
      heavy = %{@weapon | "power" => 40}
      attacker = %{participant("p1", "attackers") | mana: 0, active_states: [heavy]}
      resolution = strike(4_242, attacker, [], heavy)

      assert Enum.any?(resolution.events, &(&1.event_type == "insufficient_mana"))
      refute Enum.any?(resolution.events, &(&1.event_type == "manifestation_strike"))
      assert resolution.combat_attrs.sides["defenders"]["shared_hp"] == 100
    end
  end

  describe "the roll" do
    test "broken ground lands fewer blows than clear ground" do
      clear = Enum.count(1..80, &strike_landed?(&1, ["clear"]))
      broken = Enum.count(1..80, &strike_landed?(&1, ["ice", "flooded", "rubble"]))

      assert clear > broken
      # Neither is a foregone conclusion: the roll is real in both directions.
      assert broken > 0
      assert clear < 80
    end
  end

  defp strike_landed?(seed, environment) do
    seed
    |> strike(participant_with_weapon(), environment)
    |> Map.fetch!(:events)
    |> Enum.any?(&(&1.event_type == "manifestation_strike"))
  end

  defp strike(seed, attacker, environment \\ [], weapon \\ @weapon) do
    combat = %{combat_fixture() | seed: seed, environment_tags: environment}

    Engine.resolve_turn(
      combat,
      %Turn{number: 1, status: :locked},
      [attacker, participant("p2", "defenders")],
      [
        %Action{
          participant_id: "p1",
          action_type: :manifestation_strike,
          target_side: "defenders",
          payload: %{
            "snapshot" => %{
              "kind" => "manifestation_strike",
              "manifestation" => weapon,
              "target_side" => "defenders",
              "target_participant_id" => "p2"
            }
          }
        }
      ]
    )
  end

  defp participant_with_weapon do
    %{participant("p1", "attackers") | active_states: [@weapon]}
  end

  defp combat_fixture do
    %Combat{
      id: "melee-combat",
      turn_number: 2,
      seed: 4_242,
      environment_tags: [],
      metadata: %{},
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participant(id \\ "p1", side \\ "attackers") do
    %Participant{
      id: id,
      character_id: "character-#{id}",
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
      character: %Character{id: "character-#{id}", level: 10}
    }
  end
end
