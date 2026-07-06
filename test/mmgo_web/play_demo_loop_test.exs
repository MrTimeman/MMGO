defmodule MMGOWeb.PlayDemoLoopTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Survival
  alias MMGO.Travel
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

    %{city: city, tower: tower}
  end

  test "GET /play/new prepares a local character and redirects to map", %{
    conn: conn,
    city: city
  } do
    conn = get(conn, ~p"/play/new")

    assert redirected_to(conn) == ~p"/map"

    character =
      Account
      |> Repo.get_by!(handle: "demo-player-1")
      |> Repo.preload(:characters)
      |> Map.fetch!(:characters)
      |> List.first()
      |> Repo.preload(:current_location)

    assert character.status == :active
    assert character.current_location_id == city.id
    assert Survival.food_units_available(character) >= 30
    assert Repo.get_by!(EconomyAccount, character_id: character.id).current_balance == 1_000

    assert Enum.any?(
             Inventory.list_inventory_for_character(character.id),
             &(&1.item_template.code == "demo_lumen_dust")
           )

    assert [%{name: "Ember Spark"}] = Spells.list_spells_for_character(character.id)
    assert %{status: :active} = Grimoires.active_grimoire_for_character(character.id)
  end

  test "GET /api/play/state exposes playable location and routes", %{conn: conn} do
    conn =
      conn
      |> get(~p"/play/new")
      |> recycle()
      |> get(~p"/api/play/state")

    response = json_response(conn, 200)

    assert response["character"]["name"] == "Demo Wizard"
    assert response["character"]["current_location"]["slug"] == "capital-city"
    assert [%{"destination" => %{"slug" => "the-tower"}}] = response["routes"]
    assert response["active_journey"] == nil
  end

  test "map LiveView starts a journey from a reachable route", %{conn: conn, tower: tower} do
    conn =
      conn
      |> get(~p"/play/new")
      |> recycle()

    {:ok, view, _html} = live(conn, ~p"/map")

    assert has_element?(view, "#map-character-panel")

    view
    |> element("#world-map")
    |> render_hook("location_clicked", %{"slug" => "the-tower"})

    account = Repo.get_by!(Account, handle: "demo-player-1")
    character = Repo.get_by!(Character, account_id: account.id)
    journey = Travel.active_journey(character.id) |> Repo.preload(:to_location)

    assert journey.to_location_id == tower.id
    assert journey.to_location.slug == "the-tower"
    assert has_element?(view, "#active-journey-card")
  end

  test "GET /play/continue keeps local progress and POST /api/play/reset rebuilds it", %{
    conn: conn
  } do
    conn =
      conn
      |> get(~p"/play/new")
      |> recycle()

    account = Repo.get_by!(Account, handle: "demo-player-1")
    character = Repo.get_by!(Character, account_id: account.id)

    {:ok, %{journey: journey}} = MMGO.Play.start_journey(character.id, "the-tower")

    continued_conn = get(conn, ~p"/play/continue")

    assert get_session(continued_conn, :demo_character_id) == character.id
    assert Travel.active_journey(character.id).id == journey.id

    reset_conn =
      continued_conn
      |> recycle()
      |> post(~p"/api/play/reset")

    assert %{"ok" => true, "character_id" => reset_character_id} = json_response(reset_conn, 200)
    assert reset_character_id == character.id
    assert Travel.active_journey(character.id) == nil
    assert Repo.get!(Travel.Journey, journey.id).status == :cancelled
  end

  test "GET /demo/start remains a continue alias", %{conn: conn} do
    conn = get(conn, ~p"/demo/start")

    assert redirected_to(conn) == ~p"/map"
    assert get_session(conn, :demo_character_id)
  end
end
