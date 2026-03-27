defmodule MMGO.ToolActionsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Combat.{Event, Participant}
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    attacker = character_fixture(realm, "tool-attacker", "Tool Attacker")
    defender = character_fixture(realm, "tool-defender", "Tool Defender")

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "iron_sword",
        name: "Iron Sword",
        item_type: :weapon,
        stackable: false,
        weight: 3,
        max_durability: 24,
        actions: [
          %{
            key: "strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 3,
            effects: [
              %{applies_to: :target, state: "impact", intensity: 14, variance: 0, duration: 0}
            ]
          }
        ]
      })

    {:ok, shield_template} =
      Inventory.create_item_template(%{
        code: "oak_shield",
        name: "Oak Shield",
        item_type: :shield,
        stackable: false,
        weight: 3,
        max_durability: 18,
        actions: [
          %{
            key: "raise_shield",
            action_kind: :raise_shield,
            targeting: :self,
            durability_cost: 2,
            effects: [
              %{applies_to: :caster, state: "shielded", intensity: 9, variance: 0, duration: 1}
            ]
          }
        ]
      })

    {:ok, potion_template} =
      Inventory.create_item_template(%{
        code: "ice_phial",
        name: "Ice Phial",
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

    {:ok, sword} = Inventory.grant_item(attacker, sword_template)
    {:ok, shield} = Inventory.grant_item(defender, shield_template)
    {:ok, potion} = Inventory.grant_item(attacker, potion_template, %{quantity: 2})

    {:ok, %{combat: combat}} =
      Combat.create_duel(realm, %{
        participants: [
          %{character_id: attacker.id, side: "attackers", position: 0},
          %{character_id: defender.id, side: "defenders", position: 0}
        ]
      })

    %{
      combat: combat,
      attacker: attacker,
      defender: defender,
      sword: sword,
      shield: shield,
      potion: potion
    }
  end

  test "weapon strikes consume durability and damage the enemy side", %{
    combat: combat,
    attacker: attacker,
    sword: sword
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :use_item,
               inventory_item_id: sword.id,
               target_side: "defenders",
               payload: %{"tool_action" => "strike"}
             })

    assert {:ok, %CombatSchema{} = resolved_combat} = Combat.resolve_turn(combat)
    assert resolved_combat.sides["defenders"]["shared_hp"] < 100

    sword_after = Inventory.get_inventory_item!(sword.id)
    assert sword_after.durability == 21
  end

  test "shield actions apply shielded and absorb a later strike", %{
    combat: combat,
    attacker: attacker,
    defender: defender,
    sword: sword,
    shield: shield
  } do
    combat = Combat.get_combat!(combat.id)
    defender_participant = Enum.find(combat.participants, &(&1.character_id == defender.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, defender_participant.id, %{
               action_type: :use_item,
               inventory_item_id: shield.id,
               payload: %{"tool_action" => "raise_shield"}
             })

    assert {:ok, _combat} = Combat.resolve_turn(combat)

    defender_after_guard =
      Repo.get_by!(Participant, combat_id: combat.id, character_id: defender.id)

    assert Enum.any?(defender_after_guard.active_states, &(&1["state"] == "shielded"))

    reloaded = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(reloaded.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(reloaded, attacker_participant.id, %{
               action_type: :use_item,
               inventory_item_id: sword.id,
               target_side: "defenders",
               payload: %{"tool_action" => "strike"}
             })

    assert {:ok, %CombatSchema{} = resolved_again} = Combat.resolve_turn(reloaded)
    assert resolved_again.sides["defenders"]["shared_hp"] > 90

    defender_after = Repo.get_by!(Participant, combat_id: combat.id, character_id: defender.id)
    refute Enum.any?(defender_after.active_states, &(&1["state"] == "shielded"))
  end

  test "thrown potions consume quantity and apply deterministic states", %{
    combat: combat,
    attacker: attacker,
    potion: potion
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :use_item,
               inventory_item_id: potion.id,
               target_side: "defenders",
               payload: %{"tool_action" => "throw"}
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    potion_after = Inventory.get_inventory_item!(potion.id)
    assert potion_after.quantity == 1

    defender_after = Repo.get_by!(Participant, combat_id: combat.id, side: "defenders")
    assert Enum.any?(defender_after.active_states, &(&1["state"] == "frozen"))
  end

  test "using someone else's item is rejected", %{
    combat: combat,
    attacker: attacker,
    shield: shield
  } do
    combat = Combat.get_combat!(combat.id)
    attacker_participant = Enum.find(combat.participants, &(&1.character_id == attacker.id))

    assert {:ok, _action} =
             Combat.submit_action(combat, attacker_participant.id, %{
               action_type: :use_item,
               inventory_item_id: shield.id,
               payload: %{"tool_action" => "raise_shield"}
             })

    assert {:ok, _resolved} = Combat.resolve_turn(combat)

    unauthorized_event =
      Repo.get_by!(Event, combat_id: combat.id, event_type: "unauthorized_item")

    assert unauthorized_event.payload["inventory_item_id"] == shield.id
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
