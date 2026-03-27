defmodule MMGO.MarketTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Market
  alias MMGO.Repo
  alias MMGO.Survival
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "market-square",
        name: "Market Square",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    seller = character_fixture(realm, location, "seller", "Seller")
    buyer = character_fixture(realm, location, "buyer", "Buyer")

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "market_ration",
        name: "Market Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "market_ore",
        name: "Market Ore",
        item_type: :tool,
        stackable: true,
        weight: 3,
        max_durability: 0,
        nutrition_units: 0,
        actions: [
          %{
            key: "use",
            action_kind: :repair,
            targeting: :self,
            effects: [
              %{
                applies_to: :caster,
                state: "regenerating",
                intensity: 1,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      })

    {:ok, sword_template} =
      Inventory.create_item_template(%{
        code: "market_sword",
        name: "Market Sword",
        item_type: :weapon,
        stackable: false,
        weight: 4,
        max_durability: 12,
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

    {:ok, ration_item} = Inventory.grant_item(seller, ration_template, %{quantity: 10})
    {:ok, ore_item} = Inventory.grant_item(seller, ore_template, %{quantity: 4})
    {:ok, sword_item} = Inventory.grant_item(seller, sword_template)
    {:ok, _buyer_funds} = Economy.grant_from_treasury(realm, buyer, 200)

    %{
      realm: realm,
      seller: seller,
      buyer: buyer,
      ration_item: ration_item,
      ore_item: ore_item,
      sword_item: sword_item,
      ration_template: ration_template,
      ore_template: ore_template,
      sword_template: sword_template
    }
  end

  test "create_listing/3 reserves quantity and reduces available food units", %{
    seller: seller,
    ration_item: ration_item
  } do
    assert {:ok, %{listing: listing, inventory_item: updated_item}} =
             Market.create_listing(seller, ration_item, %{
               quantity: 5,
               unit_price: 3,
               tax_rate_bps: 500
             })

    assert listing.status == :active
    assert updated_item.reserved_quantity == 5
    assert Inventory.available_quantity(updated_item) == 5
    assert Survival.food_units_available(seller) == 5
  end

  test "cancel_listing/2 releases reserved quantity", %{seller: seller, ore_item: ore_item} do
    {:ok, %{listing: listing}} =
      Market.create_listing(seller, ore_item, %{quantity: 2, unit_price: 10, tax_rate_bps: 500})

    assert {:ok, %{listing: cancelled_listing, inventory_item: updated_item}} =
             Market.cancel_listing(listing, seller)

    assert cancelled_listing.status == :cancelled
    assert updated_item.reserved_quantity == 0
    assert Inventory.available_quantity(updated_item) == 4
  end

  test "purchase_listing/2 settles money with tax and transfers stackable items", %{
    realm: realm,
    seller: seller,
    buyer: buyer,
    ore_item: ore_item,
    ore_template: ore_template
  } do
    {:ok, seller_account} = Economy.ensure_character_account(seller)
    {:ok, buyer_account} = Economy.ensure_character_account(buyer)
    treasury = Economy.treasury_account_for_realm(realm.id)

    {:ok, %{listing: listing}} =
      Market.create_listing(seller, ore_item, %{quantity: 2, unit_price: 20, tax_rate_bps: 1000})

    assert {:ok, %{listing: sold_listing}} = Market.purchase_listing(listing, buyer)

    assert sold_listing.status == :sold
    assert sold_listing.buyer_character_id == buyer.id
    assert Economy.get_account!(seller_account.id).current_balance == 36
    assert Economy.get_account!(buyer_account.id).current_balance == 160
    assert Economy.get_account!(treasury.id).current_balance == 804

    seller_item = Inventory.get_inventory_item!(ore_item.id)
    assert seller_item.quantity == 2
    assert seller_item.reserved_quantity == 0

    buyer_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: buyer.id,
        item_template_id: ore_template.id
      )

    assert buyer_item.quantity == 2
  end

  test "purchase_listing/2 transfers non-stackable items to the buyer", %{
    seller: seller,
    buyer: buyer,
    sword_item: sword_item
  } do
    {:ok, %{listing: listing}} =
      Market.create_listing(seller, sword_item, %{quantity: 1, unit_price: 50, tax_rate_bps: 0})

    assert {:ok, %{listing: sold_listing, item_result: transferred_item}} =
             Market.purchase_listing(listing, buyer)

    assert sold_listing.status == :sold
    assert transferred_item.character_id == buyer.id
    assert transferred_item.reserved_quantity == 0
    assert Repo.get!(Inventory.InventoryItem, sword_item.id).character_id == buyer.id
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
