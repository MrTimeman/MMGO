defmodule MMGO.Combat.ManifestationUpkeepTest do
  @moduledoc """
  What it costs to keep something standing: every school sustains its
  manifestations turn by turn, except earth, which locks the mana away instead.
  """

  use ExUnit.Case, async: true

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Action, Combat, Engine, Participant, Turn}
  alias MMGO.Spells.{FailureProfile, Manifestation, Spell, SpellEffect}

  test "a standing weapon drains its summoner every turn" do
    weapon = %{
      "state" => "summoned_weapon",
      "source_spell_id" => "spell-1",
      "display_name" => "Призванный клинок",
      "power" => 12,
      "remaining_turns" => 3,
      "applied_on_turn" => 1,
      "upkeep" => 3
    }

    attacker = %{participant("p1", "attackers") | mana: 50, active_states: [weapon]}
    resolution = resolve([attacker, participant("p2", "defenders")], [])

    assert %{payload: %{"paid" => 3}} =
             Enum.find(resolution.events, &(&1.event_type == "manifestation_upkeep"))

    # 50 in the pool, 10 back at the start of the turn, 3 to keep the blade.
    assert resolution.participant_updates["p1"].mana == 57
  end

  test "what the caster cannot pay for, the caster cannot keep" do
    creature = %{
      "state" => "summoned_creature",
      "source_spell_id" => "spell-1",
      "display_name" => "Призванный страж",
      "hp" => 18,
      "power" => 7,
      "remaining_turns" => 3,
      "applied_on_turn" => 1,
      "upkeep" => 40
    }

    attacker = %{participant("p1", "attackers") | mana: 0, active_states: [creature]}
    resolution = resolve([attacker, participant("p2", "defenders")], [])

    assert %{payload: payload} =
             Enum.find(resolution.events, &(&1.event_type == "summon_destroyed"))

    assert payload["reason"] == "mana_exhausted"
    assert resolution.participant_updates["p1"].active_states == []
    # Nothing was paid for a creature that could not be kept.
    assert resolution.participant_updates["p1"].mana == 10
  end

  describe "earth" do
    test "locks the mana that made the manifestation instead of draining" do
      resolution = resolve(participants(), [cast(earth_shield_spell())])
      update = resolution.participant_updates["p1"]

      shield = Enum.find(update.active_states, &(&1["state"] == "summoned_shield"))

      assert shield["locked_mana"] == 30
      refute Map.has_key?(shield, "upkeep")

      assert update.locked_mana == 30
      # The cast was paid for out of the pool, and the ceiling now sits 30 lower.
      assert update.mana == 70
    end

    test "the locked capacity is unavailable until the manifestation ends" do
      standing = resolve(participants(), [cast(earth_shield_spell())])
      update = standing.participant_updates["p1"]

      carried = %{
        participant("p1", "attackers")
        | mana: update.mana,
          locked_mana: update.locked_mana,
          active_states: update.active_states
      }

      # Several quiet turns of regen cannot refill past the locked ceiling.
      held =
        Enum.reduce(1..6, carried, fn _turn, attacker ->
          resolution = resolve([attacker, participant("p2", "defenders")], [])
          update = resolution.participant_updates["p1"]
          %{attacker | mana: update.mana, locked_mana: update.locked_mana}
        end)

      assert held.mana == 70
      assert held.locked_mana == 30
    end

    test "the hold is released when the manifestation goes" do
      standing = resolve(participants(), [cast(earth_shield_spell())])
      update = standing.participant_updates["p1"]

      # The shield is gone: expired, shattered or dispelled — the pool does not
      # care which. The turn it leaves is the turn the hold lifts.
      dispelled = %{
        participant("p1", "attackers")
        | mana: update.mana,
          locked_mana: update.locked_mana,
          active_states: []
      }

      released = resolve([dispelled, participant("p2", "defenders")], [])
      assert released.participant_updates["p1"].locked_mana == 0

      freed = %{
        dispelled
        | mana: released.participant_updates["p1"].mana,
          locked_mana: released.participant_updates["p1"].locked_mana
      }

      # With the hold lifted, the pool fills all the way again.
      recovered = resolve([freed, participant("p2", "defenders")], [])
      assert recovered.participant_updates["p1"].mana == 80
    end
  end

  defp resolve(participants, actions) do
    Engine.resolve_turn(
      combat_fixture(),
      %Turn{number: 2, status: :locked},
      participants,
      actions
    )
  end

  defp cast(spell) do
    %Action{
      participant_id: "p1",
      action_type: :cast_spell,
      spell: spell,
      spell_id: spell.id,
      target_side: "attackers"
    }
  end

  defp earth_shield_spell do
    %Spell{
      id: "earth-shield",
      creator_character_id: "character-p1",
      school: :earth,
      targeting: :self,
      delivery_form: :self,
      power: 10,
      fatigue_cost: 30,
      cooldown_turns: 0,
      environment_tags: [],
      environment_mode: :none,
      effects: [
        %SpellEffect{
          applies_to: :caster,
          state: "shielded",
          intensity: 6,
          variance: 0,
          duration: 2,
          tags: []
        }
      ],
      manifestation: %Manifestation{
        kind: :held_shield,
        display_name: "Каменный щит",
        hp: 24,
        duration_turns: 4
      },
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

  defp combat_fixture do
    %Combat{
      id: "upkeep-combat",
      turn_number: 2,
      seed: 909,
      environment_tags: [],
      metadata: %{},
      sides: %{
        "attackers" => %{"label" => "Attackers", "shared_hp" => 100, "max_shared_hp" => 100},
        "defenders" => %{"label" => "Defenders", "shared_hp" => 100, "max_shared_hp" => 100}
      }
    }
  end

  defp participants do
    [participant("p1", "attackers"), participant("p2", "defenders")]
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
end
