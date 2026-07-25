defmodule MMGOWeb.MapLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, scoped_realm} =
      Worlds.create_realm(%{slug: "scoped-realm", name: "Scoped Realm", is_default: false})

    {:ok, scoped_city} =
      Worlds.create_location(scoped_realm, %{
        slug: "scoped-city",
        name: "Scoped City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, scoped_tower} =
      Worlds.create_location(scoped_realm, %{
        slug: "scoped-tower",
        name: "Scoped Tower",
        kind: :tower,
        x: 200,
        y: 200,
        safe_zone: false
      })

    {:ok, _route} =
      Worlds.create_route(scoped_realm, %{
        name: "Scoped Road",
        origin_location_id: scoped_city.id,
        destination_location_id: scoped_tower.id,
        travel_days: 2,
        risk_level: 10,
        bidirectional: true
      })

    {:ok, default_realm} =
      Worlds.create_realm(%{slug: "default-realm", name: "Default Realm", is_default: true})

    {:ok, default_city} =
      Worlds.create_location(default_realm, %{
        slug: "default-city",
        name: "Default City",
        kind: :city,
        x: 50,
        y: 50,
        safe_zone: true
      })

    character = character_fixture(scoped_realm, scoped_city, "scoped-player", "Scoped Player")
    nearby = character_fixture(scoped_realm, scoped_city, "nearby-player", "Nearby Player")
    outsider = character_fixture(default_realm, default_city, "outsider", "Outsider")

    %{character: character, nearby: nearby, outsider: outsider}
  end

  test "uses the current scope realm and real world overlay data", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(scoped_conn(conn, character), ~p"/map")

    assert has_element?(view, "#world-map[phx-hook='HexMap']")
    assert has_element?(view, "#map-world-clock")
    assert has_element?(view, "#map-current-location")
    assert has_element?(view, "#map-activity-link")
    assert has_element?(view, "#map-character-panel")
    assert has_element?(view, "#map-panel-close")
    assert has_element?(view, "#map-nearby-count", "Рядом: 1")
    assert has_element?(view, "#game-primary-nav")
    refute has_element?(view, "#map-notifications-history")
    refute has_element?(view, "#atmosphere-audio")
    refute has_element?(view, "a[href='/healthz']")

    view |> element("#map-panel-close") |> render_click()
    refute has_element?(view, "#map-character-panel")
    assert has_element?(view, "#map-panel-open")

    view |> element("#map-panel-open") |> render_click()
    assert has_element?(view, "#map-character-panel")
  end

  defp scoped_conn(conn, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, character.account_id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
