defmodule MMGO.InventoryTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "inventory-mage", "Inventory Mage")

    %{character: character}
  end

  test "grant_item/3 merges stackable items", %{character: character} do
    {:ok, potion_template} =
      Inventory.create_item_template(%{
        code: "fire_phial",
        name: "Fire Phial",
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
              %{applies_to: :target, state: "burning", intensity: 4, variance: 0, duration: 2}
            ]
          }
        ]
      })

    assert {:ok, _item} = Inventory.grant_item(character, potion_template, %{quantity: 2})
    assert {:ok, item} = Inventory.grant_item(character, potion_template, %{quantity: 3})

    assert item.quantity == 5
    assert Repo.aggregate(InventoryItem, :count, :id) == 1
  end

  test "grant_item/3 creates separate rows for non-stackable items", %{character: character} do
    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "training_sword",
        name: "Training Sword",
        item_type: :weapon,
        stackable: false,
        weight: 2,
        max_durability: 20,
        actions: [
          %{
            key: "strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 2,
            effects: [
              %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
            ]
          }
        ]
      })

    assert {:ok, item_a} = Inventory.grant_item(character, sword_template)
    assert {:ok, item_b} = Inventory.grant_item(character, sword_template)

    assert item_a.id != item_b.id
    assert Repo.aggregate(InventoryItem, :count, :id) == 2
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
