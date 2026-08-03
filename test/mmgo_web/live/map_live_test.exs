defmodule MMGOWeb.MapLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, scoped_realm} =
      Worlds.create_realm(%{slug: "scoped-realm", name: "Scoped Realm", is_default: false})

    {:ok, scoped_city} =
      Worlds.create_location(scoped_realm, %{
        slug: "amber-harbor",
        name: "Amber Harbor",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, scoped_tower} =
      Worlds.create_location(scoped_realm, %{
        slug: "the-tower",
        name: "The Tower",
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

    %{character: character, destination: scoped_tower, nearby: nearby, outsider: outsider}
  end

  test "uses the current scope realm and real world overlay data", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(scoped_conn(conn, character), ~p"/map")

    assert has_element?(view, "#world-map[phx-hook='HexMap']")
    assert has_element?(view, "#map-world-clock[aria-expanded='false']")
    assert has_element?(view, "#map-current-location", "Янтарная Гавань")
    assert has_element?(view, "#map-character-panel")
    assert has_element?(view, "#map-nearby-count", "Рядом: 1")
    refute has_element?(view, "#map-activity-link")
    refute has_element?(view, "#map-panel-close")
    refute has_element?(view, "#map-panel-open")
    refute has_element?(view, "#game-primary-nav")
    assert has_element?(view, "#map-account-menu-toggle[aria-expanded='false']")
    refute has_element?(view, "#map-account-menu")
    refute has_element?(view, "#map-notifications-history")
    refute has_element?(view, "#atmosphere-audio")
    refute has_element?(view, "a[href='/healthz']")

    view |> element("#map-world-clock") |> render_click()
    assert has_element?(view, "#map-world-clock[aria-expanded='true']")
    assert has_element?(view, "#map-world-calendar[role='dialog']")
    assert has_element?(view, "#map-world-calendar .ovl-cal__season.is-now")
    assert has_element?(view, "#map-world-calendar .ovl-cal__month-mark.is-now")
    assert has_element?(view, "#map-world-calendar .ovl-cal__day[aria-current='date']")
    assert has_element?(view, "#map-world-calendar .ovl-cal__day[aria-label='28-й день']")
    refute has_element?(view, "#map-character-panel")

    view |> element("#map-world-calendar-close") |> render_click()
    assert has_element?(view, "#map-world-clock[aria-expanded='false']")
    refute has_element?(view, "#map-world-calendar")
    assert has_element?(view, "#map-character-panel")

    view |> render_hook("map_location_selected", %{"selected" => true})
    refute has_element?(view, "#map-character-panel")

    view |> render_hook("map_location_selected", %{"selected" => false})
    assert has_element?(view, "#map-character-panel")

    view |> element("#map-account-menu-toggle") |> render_click()
    assert has_element?(view, "#map-account-menu-toggle[aria-expanded='true']")
    assert has_element?(view, "#map-account-menu")
    assert has_element?(view, "#map-account-inventory[href='/inventory']")
    assert has_element?(view, "#map-account-characters[href='/characters']")

    view |> render_click("close_account_menu")
    refute has_element?(view, "#map-account-menu")
  end

  test "an already-open socket cannot act after its profile is frozen", %{
    conn: conn,
    character: character
  } do
    sibling =
      %Character{account_id: character.account_id, realm_id: character.realm_id}
      |> Character.changeset(%{name: "Frozen Sibling", status: :frozen})
      |> Repo.insert!()

    {:ok, view, _html} = live(scoped_conn(conn, character), ~p"/map")
    assert {:ok, _sibling} = Accounts.switch_character(character.account_id, sibling.id)

    view |> element("#map-account-menu-toggle") |> render_click()
    assert_redirect(view, ~p"/characters")
  end

  test "an active profile without an assigned location does not crash the map", %{
    conn: conn,
    character: character
  } do
    unplaced_character =
      character
      |> Character.travel_changeset(%{current_location_id: nil})
      |> Repo.update!()

    {:ok, view, _html} = live(scoped_conn(conn, unplaced_character), ~p"/map")

    assert has_element?(view, "#world-map[phx-hook='HexMap']")
    assert has_element?(view, "#map-current-location", "неизвестное место")
    assert has_element?(view, "#map-account-menu-toggle")
  end

  test "a sealed spirit can project to every location with a distinct map action", %{
    conn: conn,
    character: character
  } do
    realm = Worlds.get_realm!(character.realm_id)

    {:ok, hidden_annex} =
      Worlds.create_location(realm, %{
        slug: "hidden-annex",
        name: "Hidden Annex",
        kind: :wilderness,
        x: 400,
        y: 400,
        safe_zone: false
      })

    sealed_character =
      character
      |> Character.changeset(%{
        metadata: %{
          "profile_kind" => "sealed_spirit",
          "hidden_presence" => true,
          "sealed_anchor_location_id" => character.current_location_id
        }
      })
      |> Repo.update!()

    {:ok, view, _html} = live(scoped_conn(conn, sealed_character), ~p"/map")

    assert_push_event(view, "map_state", %{locations: locations})
    annex_payload = Enum.find(locations, &(&1.slug == "hidden-annex"))
    assert annex_payload.can_travel
    assert annex_payload.travel_mode == "spirit"
    assert annex_payload.travel_label == "Духовный переход"

    view |> render_hook("location_clicked", %{"slug" => hidden_annex.slug})
    assert Accounts.get_character!(character.id).current_location_id == hidden_annex.id
  end

  test "calendar and active journey slips never occupy the mobile bottom edge together", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(scoped_conn(conn, character), ~p"/map")

    view |> render_hook("location_clicked", %{"slug" => "the-tower"})
    assert has_element?(view, "#active-journey-card")

    assert has_element?(
             view,
             "#active-journey-card .map-journey-slip__place--destination",
             "Башня"
           )

    view |> element("#map-world-clock") |> render_click()
    assert has_element?(view, "#map-world-calendar")
    refute has_element?(view, "#active-journey-card")
    refute has_element?(view, "#map-character-panel")

    view |> element("#map-world-calendar-close") |> render_click()
    refute has_element?(view, "#map-world-calendar")
    assert has_element?(view, "#active-journey-card")
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
