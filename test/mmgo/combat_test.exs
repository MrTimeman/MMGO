defmodule MMGO.CombatTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.{Event, Participant}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    attacker = character_fixture("attacker", realm, "Attacker One")
    defender = character_fixture("defender", realm, "Defender One")

    fireball =
      spell_fixture(attacker, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        targeting: :enemy,
        delivery_form: :sphere,
        tags: ["fire", "projectile"],
        effects: [
          %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0},
          %{applies_to: :target, state: "burning", intensity: 5, variance: 0, duration: 2}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    ward =
      spell_fixture(defender, %{
        name: "Aegis Murus",
        formula: "Aegis Murus Levis",
        school: :order,
        targeting: :self,
        delivery_form: :wall,
        tags: ["warding"],
        effects: [
          %{applies_to: :caster, state: "shielded", intensity: 8, variance: 0, duration: 1}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ],
        sides: %{
          attackers: %{"label" => "Red", "shared_hp" => 100, "max_shared_hp" => 100},
          defenders: %{"label" => "Blue", "shared_hp" => 100, "max_shared_hp" => 100}
        }
      })

    %{
      realm: realm,
      attacker: attacker,
      defender: defender,
      fireball: fireball,
      ward: ward,
      combat: combat
    }
  end

  test "resolve_turn/1 applies deterministic spell damage and states", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Repo.preload(combat, participants: [:character])
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, %CombatSchema{} = resolved_combat} = Combat.resolve_turn(combat)
    assert resolved_combat.turn_number == 2

    defenders = resolved_combat.sides["defenders"]
    assert defenders["shared_hp"] < defenders["max_shared_hp"]

    defender_participant = Repo.get_by!(Participant, combat_id: combat.id, side: "defenders")
    assert Enum.any?(defender_participant.active_states, &(&1["state"] == "burning"))
    assert Repo.aggregate(Event, :count, :id) > 0
  end

  test "shielded states absorb incoming impact damage", %{
    combat: combat,
    attacker: attacker,
    defender: defender,
    fireball: fireball,
    ward: ward
  } do
    combat = Repo.preload(combat, participants: [:character])
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{
               action_type: :cast_spell,
               spell_id: ward.id
             })

    assert {:ok, _combat} = Combat.resolve_turn(combat)

    reloaded = Combat.get_combat!(combat.id)

    assert {:ok, _action} =
             Combat.submit_action(reloaded, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, %CombatSchema{} = resolved_again} = Combat.resolve_turn(reloaded)
    defenders = resolved_again.sides["defenders"]

    assert defenders["shared_hp"] > 70

    defender_after = Repo.get_by!(Participant, combat_id: combat.id, character_id: defender.id)
    refute Enum.any?(defender_after.active_states, &(&1["state"] == "shielded"))
  end

  defp character_fixture(handle, realm, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 12})
    |> Repo.insert!()
  end

  defp spell_fixture(character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end
end
