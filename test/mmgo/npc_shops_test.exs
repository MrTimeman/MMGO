defmodule MMGO.NPCShopsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.NPCShops
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    buyer = character_fixture(realm, city, "buyer", "Buyer")
    seller = character_fixture(realm, city, "seller", "Seller")
    {:ok, _buyer_funds} = Economy.grant_from_treasury(realm, buyer, 100)

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "npc_ore",
        name: "NPC Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "npc_sword",
        name: "NPC Sword",
        item_type: :weapon,
        stackable: false,
        weight: 4,
        max_durability: 10,
        nutrition_units: 0,
        actions: [
          %{
            key: "strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 1,
            effects: [
              %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
            ]
          }
        ]
      })

    {:ok, _seller_ore} = Inventory.grant_item(seller, ore_template, %{quantity: 3})
    {:ok, shop} = NPCShops.create_shop(city, %{code: "general-store", name: "General Store"})

    {:ok, ore_offer} =
      NPCShops.add_offer(shop, %{
        item_template_id: ore_template.id,
        buy_price: 8,
        sell_price: 4,
        item_durability: 0
      })

    {:ok, sword_offer} =
      NPCShops.add_offer(shop, %{
        item_template_id: sword_template.id,
        buy_price: 30,
        sell_price: 10,
        item_durability: 10
      })

    %{
      realm: realm,
      city: city,
      buyer: buyer,
      seller: seller,
      shop: shop,
      ore_offer: ore_offer,
      sword_offer: sword_offer,
      ore_template: ore_template,
      sword_template: sword_template
    }
  end

  test "buy/3 transfers money and grants items", %{
    realm: realm,
    buyer: buyer,
    sword_offer: sword_offer,
    sword_template: sword_template
  } do
    {:ok, buyer_account} = Economy.ensure_character_account(buyer)
    treasury = Economy.treasury_account_for_realm(realm.id)

    assert {:ok, %{economy: _economy, item_result: item_result}} =
             NPCShops.buy(buyer, sword_offer, 1)

    assert item_result.item_template_id == sword_template.id
    assert Economy.get_account!(buyer_account.id).current_balance == 70
    assert Economy.get_account!(treasury.id).current_balance == 930
  end

  test "sell/4 pays characters from the treasury and consumes inventory", %{
    realm: realm,
    seller: seller,
    ore_offer: ore_offer,
    ore_template: ore_template
  } do
    inventory_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: seller.id,
        item_template_id: ore_template.id
      )

    {:ok, seller_account} = Economy.ensure_character_account(seller)
    treasury = Economy.treasury_account_for_realm(realm.id)

    assert {:ok, %{payout: payout}} = NPCShops.sell(seller, ore_offer, inventory_item, 2)
    assert payout == 8
    assert Economy.get_account!(seller_account.id).current_balance == 8
    assert Economy.get_account!(treasury.id).current_balance == 892

    updated_item = Inventory.get_inventory_item!(inventory_item.id)
    assert updated_item.quantity == 1
  end

  test "donate_to_charity/2 and pay_tuition/2 use system accounts", %{realm: realm, buyer: buyer} do
    {:ok, _charity} = NPCShops.ensure_charity_fund_account(realm)
    {:ok, _extra_funds} = Economy.grant_from_treasury(realm, buyer, 50)
    {:ok, buyer_account} = Economy.ensure_character_account(buyer)

    assert {:ok, _donation} = NPCShops.donate_to_charity(buyer, 20)
    assert {:ok, _tuition} = NPCShops.pay_tuition(buyer, 10)

    assert Economy.get_account!(buyer_account.id).current_balance == 120
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
