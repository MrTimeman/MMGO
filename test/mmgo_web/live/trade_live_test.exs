defmodule MMGOWeb.TradeLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.BlackMarket
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Market
  alias MMGO.NPCShops
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 5_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    character = character_fixture(realm, city, "trader", "Trader")
    seller = character_fixture(realm, city, "seller", "Seller")
    {:ok, _funds} = Economy.grant_from_treasury(realm, character, 500)

    {:ok, ore_template} =
      Inventory.create_item_template(%{
        code: "trade_live_ore",
        name: "Trade Live Ore",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, character_ore} = Inventory.grant_item(character, ore_template, %{quantity: 4})
    {:ok, seller_ore} = Inventory.grant_item(seller, ore_template, %{quantity: 2})

    {:ok, shop} =
      NPCShops.create_shop(city, %{
        code: "trade_live_shop",
        name: "Trade Live Shop",
        description: "Real offers for the LiveView test."
      })

    {:ok, offer} =
      NPCShops.add_offer(shop, %{
        item_template_id: ore_template.id,
        buy_price: 10,
        sell_price: 4,
        item_durability: 0
      })

    {:ok, %{listing: listing}} =
      Market.create_listing(seller, seller_ore, %{quantity: 1, unit_price: 25, tax_rate_bps: 500})

    {:ok, %{offer: black_offer}} =
      BlackMarket.create_offer(seller, seller_ore, %{quantity: 1, unit_price: 30})

    %{
      character: character,
      seller: seller,
      character_ore: character_ore,
      offer: offer,
      listing: listing,
      black_offer: black_offer
    }
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/trade")
  end

  test "runs real NPC and legal-market transactions", %{
    conn: conn,
    character: character,
    character_ore: character_ore,
    offer: offer,
    listing: listing
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/trade")

    assert has_element?(view, "#trade-shop-offer-#{offer.id}")
    assert has_element?(view, "#trade-listing-#{listing.id}")

    view |> element("#trade-buy-#{offer.id}") |> render_click()
    assert Inventory.get_inventory_item!(character_ore.id).quantity == 5

    view
    |> form("#trade-sell-form", %{
      "shop_sell" => %{
        "offer_id" => offer.id,
        "inventory_item_id" => character_ore.id,
        "quantity" => "1"
      }
    })
    |> render_submit()

    assert Inventory.get_inventory_item!(character_ore.id).quantity == 4

    view |> element("#trade-buy-listing-#{listing.id}") |> render_click()
    assert Inventory.get_inventory_item!(character_ore.id).quantity == 5
  end

  test "buys a fixed grimoire tier through the city trade catalog", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/trade")

    assert has_element?(view, "#trade-grimoire-catalog")
    assert has_element?(view, "#trade-grimoire-tier-scholar", "20 формул")

    view
    |> element("#trade-buy-grimoire-scholar")
    |> render_click()

    assert Enum.any?(Grimoires.list_grimoires_for_character(character.id), fn grimoire ->
             grimoire.metadata["purchase_tier"] == "scholar" and grimoire.capacity == 20 and
               grimoire.weight == 4
           end)

    assert has_element?(view, "#trade-balance", "150")
  end

  test "accepts a real black-market offer through the scoped browser flow", %{
    conn: conn,
    character: character,
    black_offer: black_offer
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/trade")

    assert has_element?(view, "#trade-black-offer-#{black_offer.id}")
    view |> element("#trade-accept-black-offer-#{black_offer.id}") |> render_click()

    [deal] = BlackMarket.list_deals_for_character(character.id)
    assert deal.offer_id == black_offer.id
    assert deal.status == :awaiting_delivery
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
