defmodule MMGO.Combat.EngineTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, RNG, Turn}
  alias MMGO.Spells.{FailureProfile, Spell, SpellEffect}

  test "resolve_turn/4 is deterministic for the same inputs" do
    spell = spell_fixture()
    combat = combat_fixture()
    turn = %Turn{number: 1, status: :locked}
    participants = participants_fixture()

    actions = [
      %Action{
        participant_id: "p1",
        action_type: :cast_spell,
        spell: spell,
        spell_id: spell.id,
        target_side: "defenders"
      }
    ]

    assert Engine.resolve_turn(combat, turn, participants, actions) ==
             Engine.resolve_turn(combat, turn, participants, actions)
  end

  property "bounded_noise/3 always stays within the requested variance" do
    check all(seed <- integer(1..1_000_000), variance <- integer(0..20)) do
      noise = RNG.bounded_noise(seed, [:spell, :impact], variance)

      assert noise >= -variance
      assert noise <= variance
    end
  end

  defp combat_fixture do
    %Combat{
      id: "combat-1",
      turn_number: 1,
      seed: 12_345,
      environment_tags: [],
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participants_fixture do
    [
      %Participant{
        id: "p1",
        character_id: "c1",
        side: "attackers",
        position: 0,
        status: :ready,
        fatigue: 0,
        cooldowns: %{},
        active_states: [],
        character: %Character{id: "c1", level: 15}
      },
      %Participant{
        id: "p2",
        character_id: "c2",
        side: "defenders",
        position: 0,
        status: :ready,
        fatigue: 0,
        cooldowns: %{},
        active_states: [],
        character: %Character{id: "c2", level: 8}
      }
    ]
  end

  defp spell_fixture do
    %Spell{
      id: "spell-1",
      creator_character_id: "c1",
      school: :fire,
      targeting: :enemy,
      delivery_form: :sphere,
      fatigue_cost: 4,
      cooldown_turns: 1,
      environment_tags: ["charred"],
      environment_mode: :add,
      effects: [
        %SpellEffect{
          applies_to: :target,
          state: "impact",
          intensity: 14,
          variance: 2,
          duration: 0
        }
      ],
      interaction_rules: [],
      failure_profile: %FailureProfile{
        difficulty: 5,
        base_success_rate: 90,
        partial_success_rate: 5,
        backlash_damage: 0
      }
    }
  end
end
