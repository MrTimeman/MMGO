defmodule MMGO.BlackMarketTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.BlackMarket
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "shadow-alley",
        name: "Shadow Alley",
        kind: :city,
        x: 30,
        y: 30,
        safe_zone: true
      })

    seller = character_fixture(realm, location, "smuggler", "Smuggler")
    buyer = character_fixture(realm, location, "buyer", "Buyer")

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "smuggled_ore",
        name: "Smuggled Ore",
        item_type: :tool,
        stackable: true,
        weight: 2,
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
        code: "smuggled_sword",
        name: "Smuggled Sword",
        item_type: :weapon,
        stackable: false,
        weight: 5,
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

    {:ok, ore_item} = Inventory.grant_item(seller, ore_template, %{quantity: 4})
    {:ok, sword_item} = Inventory.grant_item(seller, sword_template)
    {:ok, _buyer_funds} = Economy.grant_from_treasury(realm, buyer, 200)

    %{
      realm: realm,
      seller: seller,
      buyer: buyer,
      ore_item: ore_item,
      sword_item: sword_item,
      ore_template: ore_template
    }
  end

  test "create_offer/3 creates an active untaxed offer without reserving inventory", %{
    seller: seller,
    ore_item: ore_item
  } do
    assert {:ok, %{offer: offer}} =
             BlackMarket.create_offer(seller, ore_item, %{quantity: 2, unit_price: 15})

    assert offer.status == :active
    reloaded_item = Inventory.get_inventory_item!(ore_item.id)
    assert reloaded_item.reserved_quantity == 0
    assert Inventory.available_quantity(reloaded_item) == 4
  end

  test "accept_offer/2 transfers money immediately and leaves delivery pending", %{
    realm: realm,
    seller: seller,
    buyer: buyer,
    ore_item: ore_item
  } do
    {:ok, seller_account} = Economy.ensure_character_account(seller)
    {:ok, buyer_account} = Economy.ensure_character_account(buyer)
    treasury = Economy.treasury_account_for_realm(realm.id)

    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, ore_item, %{quantity: 2, unit_price: 15})

    assert {:ok, %{deal: deal, offer: committed_offer}} = BlackMarket.accept_offer(offer, buyer)

    assert deal.status == :awaiting_delivery
    assert committed_offer.status == :committed
    assert Economy.get_account!(seller_account.id).current_balance == 30
    assert Economy.get_account!(buyer_account.id).current_balance == 170
    assert Economy.get_account!(treasury.id).current_balance == 800
  end

  test "fulfill_deal/2 transfers stackable goods to the buyer", %{
    seller: seller,
    buyer: buyer,
    ore_item: ore_item,
    ore_template: ore_template
  } do
    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, ore_item, %{quantity: 3, unit_price: 10})

    {:ok, %{deal: deal}} = BlackMarket.accept_offer(offer, buyer)

    assert {:ok, %{deal: fulfilled_deal}} = BlackMarket.fulfill_deal(deal, seller)

    assert fulfilled_deal.status == :fulfilled
    seller_item = Inventory.get_inventory_item!(ore_item.id)
    assert seller_item.quantity == 1

    buyer_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: buyer.id,
        item_template_id: ore_template.id
      )

    assert buyer_item.quantity == 3
  end

  test "fulfill_deal/2 transfers non-stackable goods to the buyer", %{
    seller: seller,
    buyer: buyer,
    sword_item: sword_item
  } do
    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, sword_item, %{quantity: 1, unit_price: 50})

    {:ok, %{deal: deal}} = BlackMarket.accept_offer(offer, buyer)

    assert {:ok, %{deal: fulfilled_deal, item_result: transferred_item}} =
             BlackMarket.fulfill_deal(deal, seller)

    assert fulfilled_deal.status == :fulfilled
    assert transferred_item.character_id == buyer.id
    assert Repo.get!(Inventory.InventoryItem, sword_item.id).character_id == buyer.id
  end

  test "default_deal/3 marks the deal as a scam/default", %{
    seller: seller,
    buyer: buyer,
    ore_item: ore_item
  } do
    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, ore_item, %{quantity: 2, unit_price: 10})

    {:ok, %{deal: deal}} = BlackMarket.accept_offer(offer, buyer)

    assert {:ok, %{deal: defaulted_deal, offer: defaulted_offer}} =
             BlackMarket.default_deal(deal, seller, "never delivered")

    assert defaulted_deal.status == :defaulted
    assert defaulted_deal.metadata["default_reason"] == "never delivered"
    assert defaulted_offer.status == :defaulted
  end

  test "fulfill_deal/2 fails if the seller no longer has the promised goods", %{
    seller: seller,
    buyer: buyer,
    ore_item: ore_item
  } do
    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, ore_item, %{quantity: 3, unit_price: 10})

    {:ok, %{deal: deal}} = BlackMarket.accept_offer(offer, buyer)

    ore_item
    |> Inventory.InventoryItem.changeset(%{quantity: 1})
    |> Repo.update!()

    assert {:error, changeset} = BlackMarket.fulfill_deal(deal, seller)
    assert %{status: ["seller no longer has the promised goods"]} = errors_on(changeset)
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
