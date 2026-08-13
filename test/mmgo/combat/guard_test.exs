defmodule MMGO.Combat.GuardTest do
  @moduledoc """
  Active defence: parry and block are a turn spent standing ready, and they are
  a different thing from a magical shield absorbing on its own.
  """

  use ExUnit.Case, async: true

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, ActionSnapshot, Combat, Engine, Participant, Turn}
  alias MMGO.Spells.{FailureProfile, Spell, SpellEffect}

  @shield %{
    "state" => "summoned_shield",
    "source_spell_id" => "spell-shield",
    "display_name" => "Призванный щит",
    "hp" => 40,
    "remaining_turns" => 3,
    "applied_on_turn" => 1,
    "upkeep" => 2
  }

  @weapon %{
    "state" => "summoned_weapon",
    "source_spell_id" => "spell-blade",
    "display_name" => "Призванный клинок",
    "power" => 12,
    "remaining_turns" => 3,
    "applied_on_turn" => 1,
    "upkeep" => 3
  }

  describe "what you may raise" do
    test "bare hands are always a block and never a parry" do
      participant = participant("p2", "defenders")

      assert ActionSnapshot.guard_sources(:block, participant) == ["bare"]
      assert ActionSnapshot.guard_sources(:parry, participant) == []
    end

    test "what you hold decides how much good it does" do
      holding = %{participant("p2", "defenders") | active_states: [@shield, @weapon]}

      # A shield first: it is the thing actually made for this.
      assert ActionSnapshot.guard_sources(:block, holding) ==
               ["summoned_shield", "summoned_weapon", "bare"]

      # Only a blade can turn a blow aside.
      assert ActionSnapshot.guard_sources(:parry, holding) == ["summoned_weapon"]

      assert ActionSnapshot.guard_efficiency(:block, "summoned_shield") >
               ActionSnapshot.guard_efficiency(:block, "summoned_weapon")

      assert ActionSnapshot.guard_efficiency(:block, "summoned_weapon") >
               ActionSnapshot.guard_efficiency(:block, "bare")
    end
  end

  describe "block" do
    test "softens the blow by what was raised against it" do
      defender = %{participant("p2", "defenders") | active_states: [@weapon]}

      unguarded = resolve([attacker(), defender], [strike()])

      guarded =
        resolve([attacker(), defender], [strike(), guard("p2", :block, "summoned_weapon")])

      # A ten-point blow, forty per cent of it turned by a blade held flat.
      assert unguarded.combat_attrs.sides["defenders"]["shared_hp"] == 90
      assert guarded.combat_attrs.sides["defenders"]["shared_hp"] == 94

      guard = guarded |> impact() |> Map.fetch!("guard")

      assert guard["source"] == "summoned_weapon"
      assert guard["absorbed"] == 4
    end

    test "a guard is good for one blow" do
      defender = %{participant("p2", "defenders") | active_states: [@weapon]}

      resolution =
        resolve([attacker(), defender], [strike(), guard("p2", :block, "summoned_weapon")])

      refute Enum.any?(
               resolution.participant_updates["p2"].active_states,
               &(&1["state"] == "guarding")
             )
    end

    test "a stronger guard turns more of the blow" do
      shield_bearer = %{participant("p2", "defenders") | active_states: [@shield]}
      bare = participant("p2", "defenders")

      with_shield =
        resolve([attacker(), shield_bearer], [strike(), guard("p2", :block, "summoned_shield")])

      with_hands = resolve([attacker(), bare], [strike(), guard("p2", :block, "bare")])

      assert guard_absorbed(with_shield) > guard_absorbed(with_hands)
    end

    test "raising a guard costs mana" do
      defender = %{participant("p2", "defenders") | active_states: [@shield]}
      resolution = resolve([attacker(), defender], [guard("p2", :block, "summoned_shield")])

      assert %{payload: %{"mana_cost" => 4}} =
               Enum.find(resolution.events, &(&1.event_type == "guard_raised"))
    end
  end

  describe "parry" do
    test "turns a blow aside completely or not at all" do
      defender = %{participant("p2", "defenders") | active_states: [@weapon]}

      outcomes =
        for seed <- 1..40 do
          resolution =
            resolve([attacker(), defender], [strike(), guard("p2", :parry, "summoned_weapon")],
              seed: seed
            )

          resolution.combat_attrs.sides["defenders"]["shared_hp"]
        end

      # Either the blow was turned entirely or it landed in full: nothing between.
      assert Enum.uniq(outcomes) |> Enum.sort() == [90, 100]
      assert 100 in outcomes
      assert 90 in outcomes
    end

    test "a failed parry says so" do
      defender = %{participant("p2", "defenders") | active_states: [@weapon]}

      failed =
        Enum.find(1..40, fn seed ->
          [attacker(), defender]
          |> resolve([guard("p2", :parry, "summoned_weapon")], seed: seed)
          |> Map.fetch!(:events)
          |> Enum.any?(&(&1.event_type == "parry_failed"))
        end)

      assert failed, "no seed in the sample failed a parry"
    end
  end

  test "passive magical absorption is a separate thing from the active choice" do
    # A magical shield absorbs whether or not the defender chose to defend, and
    # it takes what the active guard leaves rather than replacing it.
    defender = %{
      participant("p2", "defenders")
      | active_states: [%{"state" => "shielded", "intensity" => 5, "remaining_turns" => 2}]
    }

    damage = resolve([attacker(), defender], [strike(), guard("p2", :block, "bare")]) |> impact()

    # Ten points: two turned by bare hands, five soaked by the ward, three land.
    assert damage["guard"]["absorbed"] == 2
    assert damage["shield_absorbed"] == 5
    assert damage["damage"] == 3
  end

  defp guard_absorbed(resolution), do: resolution |> impact() |> get_in(["guard", "absorbed"])

  # A spell's damage is reported inside the effect that dealt it.
  defp impact(resolution) do
    resolution.events
    |> Enum.find(&(&1.event_type == "spell_cast"))
    |> Map.fetch!(:payload)
    |> Map.fetch!("effects")
    |> hd()
  end

  defp resolve(participants, actions, opts \\ []) do
    combat = %{combat_fixture() | seed: Keyword.get(opts, :seed, 4_242)}

    Engine.resolve_turn(combat, %Turn{number: 2, status: :locked}, participants, actions)
  end

  defp strike do
    spell = spell_fixture()

    %Action{
      participant_id: "p1",
      action_type: :cast_spell,
      spell: spell,
      spell_id: spell.id,
      target_side: "defenders"
    }
  end

  defp guard(participant_id, mode, source) do
    %Action{
      participant_id: participant_id,
      action_type: mode,
      payload: %{
        "snapshot" => %{
          "kind" => to_string(mode),
          "guard_source" => source,
          "efficiency" => ActionSnapshot.guard_efficiency(mode, source)
        }
      }
    }
  end

  defp attacker, do: participant("p1", "attackers")

  defp combat_fixture do
    %Combat{
      id: "guard-combat",
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

  defp participant(id, side) do
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

  defp spell_fixture do
    %Spell{
      id: "guard-spell",
      creator_character_id: "character-p1",
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      power: 10,
      fatigue_cost: 10,
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
