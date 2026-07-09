defmodule MMGOWeb.InventoryLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Play
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 830,
        y: 385,
        safe_zone: false
      })

    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 35,
        bidirectional: true
      })

    :ok
  end

  test "redirects visitors without a local play session", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play/continue"}}} = live(conn, ~p"/inventory")
  end

  test "renders the session character's real inventory and carry state", %{conn: conn} do
    {:ok, %{challenger: character}} = Play.start_new_local_session()

    {:ok, view, _html} = live(session_conn(conn, character.id), ~p"/inventory")

    assert has_element?(view, "#inventory-screen")
    assert has_element?(view, "#inventory-character-location")
    assert has_element?(view, "#inventory-carry")
    assert has_element?(view, "#inventory-food-summary")
    assert has_element?(view, "#inventory-items")
    assert has_element?(view, "#inventory-search-form")
  end

  test "filters real carried items by category", %{conn: conn} do
    {:ok, %{challenger: character}} = Play.start_new_local_session()

    {:ok, template} =
      Inventory.create_item_template(%{
        code: "inventory_test_ingredient",
        name: "Inventory Test Ingredient",
        item_type: :ingredient,
        stackable: false,
        weight: 2,
        max_durability: 3,
        nutrition_units: 0,
        actions: []
      })

    {:ok, item} = Inventory.grant_item(character, template)
    {:ok, view, _html} = live(session_conn(conn, character.id), ~p"/inventory")

    view
    |> element("#inventory-category-ингредиенты")
    |> render_click()

    assert has_element?(view, "#inventory-item-#{item.id}")
  end

  defp session_conn(conn, character_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:demo_character_id, character_id)
  end
end
