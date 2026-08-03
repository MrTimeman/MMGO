defmodule MMGO.Combat.ActionSnapshotTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.{Action, Event}
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "snapshot-realm", name: "Snapshot Realm", is_default: true})

    attacker = character_fixture(realm, "snapshot-attacker", "Snapshot Attacker")
    defender = character_fixture(realm, "snapshot-defender", "Snapshot Defender")
    foreign = character_fixture(realm, "snapshot-foreign", "Snapshot Foreign")

    spell = spell_fixture(attacker, "Ignis Prima")
    foreign_spell = spell_fixture(foreign, "Aqua Aliena", %{school: :water})
    activate_grimoire(attacker, spell)

    {:ok, phial_template} =
      Inventory.create_item_template(%{
        code: "snapshot_phial",
        name: "Snapshot Phial",
        item_type: :potion,
        stackable: true,
        weight: 1,
        max_durability: 0,
        actions: [
          %{
            key: "throw",
            action_kind: :throw,
            targeting: :enemy,
            quantity_cost: 1,
            effects: [
              %{applies_to: :target, state: "frozen", intensity: 4, variance: 0, duration: 1}
            ]
          }
        ]
      })

    {:ok, phial} = Inventory.grant_item(attacker, phial_template, %{quantity: 2})

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    %{
      realm: realm,
      attacker: attacker,
      defender: defender,
      foreign: foreign,
      spell: spell,
      foreign_spell: foreign_spell,
      phial: phial,
      combat: combat
    }
  end

  test "submission stores a canonical cast snapshot rather than raw client payload", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, %Action{} = action} =
             Combat.submit_action(combat, participant.id, %{
               "action_type" => "cast_spell",
               "spell_id" => spell.id,
               "target_side" => "defenders",
               "incantation" => "  ignis   radius  ",
               "payload" => %{"invented_effect" => "nope"}
             })

    assert action.spell_id == spell.id
    assert action.target_side == "defenders"

    assert %{"kind" => "cast_spell", "incantation" => "Ignis Radius"} =
             action.payload["snapshot"]

    assert action.payload["snapshot"]["spell"]["incantation_slots"] == %{
             "actio" => "Ignis",
             "forma" => "Minima"
           }

    refute Map.has_key?(action.payload, "invented_effect")
  end

  test "submission rejects every malformed incantation without crashing", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    for incantation <- [String.duplicate("A", 181), String.duplicate("A", 33), 42] do
      assert {:error, :invalid_incantation} =
               Combat.submit_action(combat, participant.id, %{
                 "action_type" => "cast_spell",
                 "spell_id" => spell.id,
                 "target_side" => "defenders",
                 "incantation" => incantation
               })
    end

    assert Repo.aggregate(Action, :count, :id) == 0
  end

  test "submission seals valid break conditions and rejects unknown persisted snapshot values", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    {:ok, spell} =
      Spells.update_spell(spell, %{
        effects: [
          %{
            applies_to: :target,
            state: "burning",
            intensity: 4,
            variance: 0,
            duration: 2,
            break_conditions: ["water_spell"]
          }
        ]
      })

    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    assert [
             %{
               "state" => "burning",
               "break_conditions" => ["water_spell"]
             }
           ] = action.payload["snapshot"]["spell"]["effects"]

    malformed_payload =
      put_in(
        action.payload,
        ["snapshot", "spell", "effects", Access.at(0), "break_conditions"],
        ["untrusted_break"]
      )

    action
    |> Action.changeset(%{payload: malformed_payload})
    |> Repo.update!()

    assert {:ok, _resolved_combat} = Combat.resolve_turn(combat, force?: true)

    assert %{"reason" => "invalid_snapshot"} =
             Repo.get_by!(Event, combat_id: combat.id, event_type: "invalid_action").payload
  end

  test "submission rejects foreign spells and forged combat targets before persistence", %{
    combat: combat,
    attacker: attacker,
    spell: spell,
    foreign_spell: foreign_spell
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:error, :spell_not_owned} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: foreign_spell.id,
               target_side: "defenders"
             })

    assert {:error, :invalid_target} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "made-up-side"
             })

    assert Repo.aggregate(Action, :count, :id) == 0
  end

  test "a locked turn cannot replace its already approved action", %{
    combat: combat,
    attacker: attacker,
    defender: defender,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    assert {:ok, _wait} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    assert {:error, :turn_locked} =
             Combat.submit_action(Combat.get_combat!(combat.id), attacker_participant.id, %{
               action_type: :wait
             })
  end

  test "quantity-consuming tool actions reserve before lock and consume on resolution", %{
    combat: combat,
    attacker: attacker,
    defender: defender,
    phial: phial
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :use_item,
               inventory_item_id: phial.id,
               target_side: "defenders",
               payload: %{"tool_action" => "throw"}
             })

    assert %{quantity: 2, reserved_quantity: 1} = Inventory.get_inventory_item!(phial.id)

    assert {:ok, _wait} =
             Combat.submit_action(combat, defender_participant.id, %{action_type: :wait})

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    assert %{quantity: 1, reserved_quantity: 0} = Inventory.get_inventory_item!(phial.id)
  end

  test "replacing an open consumable action releases its reservation", %{
    combat: combat,
    attacker: attacker,
    phial: phial
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :use_item,
               inventory_item_id: phial.id,
               target_side: "defenders",
               payload: %{"tool_action" => "throw"}
             })

    assert %{reserved_quantity: 1} = Inventory.get_inventory_item!(phial.id)

    assert {:ok, %Action{action_type: :wait}} =
             Combat.submit_action(combat, participant.id, %{action_type: :wait})

    assert %{quantity: 2, reserved_quantity: 0} = Inventory.get_inventory_item!(phial.id)
  end

  test "resolution keeps the sealed spell snapshot after the spell record changes", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    {:ok, spell} =
      Spells.update_spell(spell, %{
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0,
          volatility: 0
        }
      })

    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    assert {:ok, _mutated_spell} =
             Spells.update_spell(spell, %{
               effects: [
                 %{applies_to: :target, state: "impact", intensity: 0, variance: 0, duration: 0}
               ]
             })

    assert {:ok, _resolved_combat} = Combat.resolve_turn(combat, force?: true)

    event = Repo.get_by!(Event, combat_id: combat.id, event_type: "spell_cast")

    assert Enum.any?(event.payload["effects"], fn effect ->
             effect["state"] == "impact" and effect["damage"] > 0
           end)
  end

  test "a malformed persisted snapshot fails closed instead of reading a live spell", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    action
    |> Action.changeset(%{payload: %{"snapshot" => %{"kind" => "cast_spell"}}})
    |> Repo.update!()

    assert {:ok, _resolved_combat} = Combat.resolve_turn(combat, force?: true)

    assert %{"reason" => "invalid_snapshot"} =
             Repo.get_by!(Event, combat_id: combat.id, event_type: "invalid_action").payload
  end

  test "a snapshot whose keyed seals contradict its formula fails closed", %{
    combat: combat,
    attacker: attacker,
    spell: spell
  } do
    combat = Combat.get_combat!(combat.id)
    participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, action} =
             Combat.submit_action(combat, participant.id, %{
               action_type: :cast_spell,
               spell_id: spell.id,
               target_side: "defenders"
             })

    malformed_payload =
      put_in(
        action.payload,
        ["snapshot", "spell", "incantation_slots", "actio"],
        "Aqua"
      )

    action
    |> Action.changeset(%{payload: malformed_payload})
    |> Repo.update!()

    assert {:ok, _resolved_combat} = Combat.resolve_turn(combat, force?: true)

    assert %{"reason" => "invalid_snapshot"} =
             Repo.get_by!(Event, combat_id: combat.id, event_type: "invalid_action").payload
  end

  defp activate_grimoire(character, spell) do
    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Snapshot Grimoire", capacity: 4, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, %{activate_grimoire: _grimoire}} = Grimoires.activate_grimoire(character, grimoire)
  end

  defp spell_fixture(character, name, attrs \\ %{}) do
    defaults = %{
      name: name,
      formula: "Ignis Minima",
      incantation_slots: %{"actio" => "Ignis", "forma" => "Minima"},
      school: :fire,
      description: "A snapshot test spell.",
      targeting: :enemy,
      delivery_form: :sphere,
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
    }

    {:ok, spell} = Spells.create_spell(character, Map.merge(defaults, attrs))
    spell
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
  end
end
