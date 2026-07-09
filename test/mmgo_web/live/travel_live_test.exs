defmodule MMGOWeb.TravelLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Economy
  alias MMGO.Play
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

    %{tower: tower}
  end

  test "redirects visitors without a local play session", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play/continue"}}} = live(conn, ~p"/travel")
  end

  test "renders the active server-timed journey", %{conn: conn, tower: tower} do
    {:ok, %{challenger: character}} = Play.start_new_local_session()
    {:ok, %{journey: journey}} = Play.start_journey(character.id, "the-tower")

    {:ok, view, _html} = live(session_conn(conn, character.id), ~p"/travel")

    assert has_element?(view, "#travel-screen")
    assert has_element?(view, "#travel-progress-panel")
    assert has_element?(view, "#travel-supplies-panel")
    assert has_element?(view, "#travel-waypoint-0")
    assert has_element?(view, "#travel-waypoint-2")
    assert has_element?(view, "#travel-open-inventory")
    assert journey.to_location_id == tower.id
  end

  test "returns to the map after the journey has arrived", %{conn: conn} do
    {:ok, %{challenger: character}} = Play.start_new_local_session()
    {:ok, %{journey: journey}} = Play.start_journey(character.id, "the-tower")
    assert {:ok, _result} = Travel.complete_journey_by_id(journey.id, force: true)

    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} =
             live(session_conn(conn, character.id), ~p"/travel")

    assert flash["info"] =~ "active journey"
  end

  defp session_conn(conn, character_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:demo_character_id, character_id)
  end
end
