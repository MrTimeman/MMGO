defmodule MMGO.ReputationTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.BlackMarket
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Market
  alias MMGO.Repo
  alias MMGO.Reputation
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "square",
        name: "Square",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    seller = character_fixture(realm, location, "seller", "Seller")
    buyer = character_fixture(realm, location, "buyer", "Buyer")

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "crime_ore",
        name: "Crime Ore",
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

    {:ok, seller_item} = Inventory.grant_item(seller, ore_template, %{quantity: 4})
    {:ok, _buyer_funds} = Economy.grant_from_treasury(realm, buyer, 200)
    {:ok, seller_account} = Economy.ensure_character_account(seller)
    {:ok, buyer_account} = Economy.ensure_character_account(buyer)

    %{
      realm: realm,
      seller: seller,
      buyer: buyer,
      seller_item: seller_item,
      seller_account: seller_account,
      buyer_account: buyer_account
    }
  end

  test "record_crime/3 creates a profile and sanctions the character", %{seller: seller} do
    assert {:ok, %{profile: profile, crime_record: crime_record}} =
             Reputation.record_crime(seller, :black_market_default, %{
               severity: 20,
               fine_amount: 30,
               market_ban_game_days: 14
             })

    assert profile.reputation_score == -20
    assert profile.crime_count == 1
    assert profile.outstanding_fine == 30
    assert profile.market_ban_until
    assert profile.npc_hostility_level > 0
    assert crime_record.crime_type == "black_market_default"
    refute Reputation.market_access_allowed?(seller.id)
  end

  test "pay_fine/2 transfers money to treasury and clears sanctions when paid off", %{
    realm: realm,
    seller: seller
  } do
    {:ok, %{profile: _profile}} =
      Reputation.record_crime(seller, :black_market_default, %{
        severity: 20,
        fine_amount: 25,
        market_ban_game_days: 14
      })

    treasury = Economy.treasury_account_for_realm(realm.id)
    {:ok, seller_account} = Economy.ensure_character_account(seller)
    {:ok, _funding} = Economy.grant_from_treasury(realm, seller, 30)

    assert {:ok, %{profile: updated_profile}} = Reputation.pay_fine(seller, 25)

    assert updated_profile.outstanding_fine == 0
    assert is_nil(updated_profile.market_ban_until)
    assert Economy.get_account!(seller_account.id).current_balance == 5
    assert Economy.get_account!(treasury.id).current_balance == 795
  end

  test "black market defaults automatically create a crime record", %{
    seller: seller,
    buyer: buyer,
    seller_item: seller_item
  } do
    {:ok, %{offer: offer}} =
      BlackMarket.create_offer(seller, seller_item, %{quantity: 2, unit_price: 10})

    {:ok, %{deal: deal}} = BlackMarket.accept_offer(offer, buyer)

    assert {:ok, %{deal: defaulted_deal}} = BlackMarket.default_deal(deal, seller, "ran away")

    assert defaulted_deal.status == :defaulted
    crimes = Reputation.list_crimes_for_character(seller.id)
    assert length(crimes) == 1
    assert hd(crimes).crime_type == "black_market_default"
  end

  test "legal market rejects sanctioned sellers and buyers", %{
    seller: seller,
    buyer: buyer,
    seller_item: seller_item
  } do
    {:ok, %{profile: _profile}} =
      Reputation.record_crime(seller, :black_market_default, %{
        severity: 20,
        fine_amount: 10,
        market_ban_game_days: 7
      })

    assert {:error, changeset} =
             Market.create_listing(seller, seller_item, %{
               quantity: 1,
               unit_price: 10,
               tax_rate_bps: 500
             })

    assert %{status: ["seller is banned from the legal market"]} = errors_on(changeset)

    {:ok, %{profile: _profile}} =
      Reputation.record_crime(buyer, :smuggling, %{
        severity: 10,
        fine_amount: 5,
        market_ban_game_days: 7
      })

    {:ok, fresh_seller} =
      fresh_character_with_goods(seller.realm_id, "freshseller", "Fresh Seller")

    {:ok, listing_item} =
      Inventory.grant_item(
        fresh_seller,
        Repo.get!(Inventory.ItemTemplate, seller_item.item_template_id),
        %{quantity: 2}
      )

    {:ok, %{listing: listing}} =
      Market.create_listing(fresh_seller, listing_item, %{
        quantity: 1,
        unit_price: 10,
        tax_rate_bps: 500
      })

    assert {:error, changeset} = Market.purchase_listing(listing, buyer)
    assert %{status: ["buyer is banned from the legal market"]} = errors_on(changeset)
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

  defp fresh_character_with_goods(realm_id, handle, name) do
    realm = Repo.get!(Worlds.Realm, realm_id)
    location = Repo.get_by!(Worlds.Location, realm_id: realm.id)
    {:ok, character_fixture(realm, location, handle, name)}
  end
end
