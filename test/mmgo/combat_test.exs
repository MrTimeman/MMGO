defmodule MMGO.CombatTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.{Event, Participant}
  alias MMGO.Grimoires
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

    _attacker_grimoire = grimoire_fixture(attacker, fireball, "Attacker's Grimoire")
    _defender_grimoire = grimoire_fixture(defender, ward, "Defender's Grimoire")

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
    combat = Combat.get_combat!(combat.id)
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
    combat = Combat.get_combat!(combat.id)
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

  test "silenced casters cannot cast prepared spells", %{
    combat: combat,
    attacker: attacker,
    fireball: fireball
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    attacker_participant
    |> Participant.changeset(%{
      active_states: [%{"state" => "silenced", "remaining_turns" => 2, "intensity" => 1}]
    })
    |> Repo.update!()

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: fireball.id,
               target_side: "defenders"
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    blocked_event = Repo.get_by!(Event, combat_id: combat.id, event_type: "action_blocked")
    assert blocked_event.payload["state"] == "silenced"
  end

  test "passive wards reserve mana and halve incoming damage while active", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    impact_spell =
      spell_fixture(attacker, %{
        name: "Ferrum Impetus",
        formula: "Ferrum Impetus Magnus",
        school: :earth,
        targeting: :enemy,
        delivery_form: :beam,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 20, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    passive_ward =
      spell_fixture(defender, %{
        name: "Ward of Glasswater",
        formula: "Aqua Aegis Teneo",
        school: :water,
        spell_type: :passive,
        mana_reservation: 30,
        targeting: :self,
        delivery_form: :self,
        fatigue_cost: 0,
        effects: [
          %{applies_to: :caster, state: "warded", intensity: 50, variance: 0, duration: 3}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    _attacker_grimoire = grimoire_fixture(attacker, impact_spell, "Attacker's Strike Book")
    _defender_grimoire = grimoire_fixture(defender, passive_ward, "Defender's Ward Book")

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{
               action_type: :cast_spell,
               spell_id: passive_ward.id
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    defender_after_toggle =
      Repo.get_by!(Participant, combat_id: combat.id, character_id: defender.id)

    mana = defender_after_toggle.metadata["mana"]

    assert mana["reserved_mana"] == 30
    assert mana["max_mana"] == mana["base_max_mana"] - 30

    reloaded = Combat.get_combat!(combat.id)

    assert {:ok, _action} =
             Combat.submit_action(reloaded, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: impact_spell.id,
               target_side: "defenders"
             })

    assert {:ok, %CombatSchema{} = resolved_combat} = Combat.resolve_turn(reloaded)
    assert resolved_combat.sides["defenders"]["shared_hp"] == 90

    passive_event = Repo.get_by!(Event, combat_id: combat.id, event_type: "passive_toggled")
    assert passive_event.payload["mode"] == "on"
  end

  test "spells not inscribed in the active grimoire are rejected", %{
    realm: realm,
    attacker: attacker,
    defender: defender
  } do
    other_spell =
      spell_fixture(attacker, %{
        name: "Terra Murus",
        formula: "Terra Murus Magnus",
        school: :earth,
        targeting: :enemy,
        delivery_form: :wall,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 15, variance: 0, duration: 0}
        ],
        failure_profile: %{difficulty: 5, base_success_rate: 95, partial_success_rate: 4}
      })

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: other_spell.id,
               target_side: "defenders"
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    rejected_event = Repo.get_by!(Event, combat_id: combat.id, event_type: "spell_not_prepared")
    assert rejected_event.payload["spell_id"] == other_spell.id
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

  defp grimoire_fixture(character, spells, name) do
    spells = List.wrap(spells)

    {:ok, grimoire} = Grimoires.create_grimoire(character, %{name: name, capacity: 6, weight: 1})

    Enum.reduce(spells, grimoire, fn spell, current_grimoire ->
      {:ok, _entry} =
        Grimoires.inscribe_spell(Grimoires.get_grimoire!(current_grimoire.id), spell)

      Grimoires.get_grimoire!(current_grimoire.id)
    end)

    {:ok, %{activate_grimoire: activated_grimoire}} =
      Grimoires.activate_grimoire(character, Grimoires.get_grimoire!(grimoire.id))

    activated_grimoire
  end
end
