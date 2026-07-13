defmodule MMGOWeb.ActionHubLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Inventory
  alias MMGO.Organizations
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "activity-realm", name: "Activity Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "activity-city",
        name: "Activity City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "activity-tower",
        name: "Activity Tower",
        kind: :tower,
        x: 200,
        y: 200,
        safe_zone: false
      })

    {:ok, watchtower} =
      Worlds.create_location(realm, %{
        slug: "activity-watchtower",
        name: "Activity Watchtower",
        kind: :wilderness,
        x: 150,
        y: 150,
        safe_zone: false
      })

    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: "Activity Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 2,
        risk_level: 10,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "activity_ration",
        name: "Activity Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, scavenged_template} =
      Inventory.create_item_template(%{
        code: "activity_scrap",
        name: "Activity Scrap",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        actions: []
      })

    {:ok, resource_cache} =
      MMGO.Scavenging.ensure_resource_cache(city, %{
        resource_code: "activity_scraps",
        quantity_total: 2,
        quantity_remaining: 2,
        respawn_game_days: 7,
        item_template_id: scavenged_template.id
      })

    character = character_fixture(realm, city, "activity-player", "Activity Player")
    nearby = character_fixture(realm, city, "activity-nearby", "Activity Nearby")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    %{
      realm: realm,
      city: city,
      watchtower: watchtower,
      character: character,
      nearby: nearby,
      resource_cache: resource_cache,
      tower: tower
    }
  end

  test "renders the scoped character's persisted city event and trusted options", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/event")

    assert has_element?(view, "#activity-hub")
    assert has_element?(view, "#activity-event-body")
    assert has_element?(view, "#activity-world-date")
    assert has_element?(view, "#activity-option-academy")
    assert has_element?(view, "#activity-option-shops", "рынок, обмен и сделки")
    assert has_element?(view, "#activity-open-inventory")
    assert has_element?(view, "#activity-survival-state")
    assert has_element?(view, "#atmosphere-audio[data-ambient-cue='city']")
  end

  test "a trusted event action navigates to its server-owned route", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/event")

    view
    |> element("#activity-option-academy")
    |> render_click()

    assert_redirect(view, "/academy/bulletin-board")
  end

  test "starts a persisted nearby-player encounter and hides attack in a safe zone", %{
    conn: conn,
    character: character,
    nearby: nearby
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/event")

    assert has_element?(view, "#activity-nearby-#{nearby.id}")

    view
    |> element("#activity-start-encounter-#{nearby.id}")
    |> render_click()

    [encounter] = MMGO.Overworld.list_open_encounters_for_character(character.id)

    assert has_element?(view, "#activity-encounter-#{encounter.id}")
    assert has_element?(view, "#activity-encounter-#{encounter.id}-greet")
    refute has_element?(view, "#activity-encounter-#{encounter.id}-attack")

    view
    |> element("#activity-encounter-#{encounter.id}-greet")
    |> render_click()

    assert has_element?(view, "#activity-encounter-#{encounter.id}")
    refute has_element?(view, "#activity-encounter-#{encounter.id}-greet")
  end

  test "starts a persisted scoped scavenging attempt from an available cache", %{
    conn: conn,
    character: character,
    resource_cache: resource_cache
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/event")

    assert has_element?(view, "#activity-scavenge-cache-#{resource_cache.id}")

    view
    |> element("#activity-start-scavenge-#{resource_cache.id}")
    |> render_click()

    [attempt | _] = MMGO.Scavenging.list_attempts_for_character(character.id)

    assert has_element?(view, "#activity-attempt-#{attempt.id}")
    refute has_element?(view, "#activity-start-scavenge-#{resource_cache.id}")

    assert {:ok, %{attempt: completed_attempt}} =
             MMGO.Scavenging.complete_attempt_by_id(attempt.id, force: true)

    view
    |> element("#activity-refresh-scavenging")
    |> render_click()

    assert has_element?(view, "#activity-scavenge-result-#{completed_attempt.id}")
  end

  test "a player in transit is sent to the travel screen instead of an arrival event", %{
    conn: conn,
    character: character,
    tower: tower
  } do
    assert {:ok, %{journey: journey}} = MMGO.Play.start_journey(character, tower.slug)

    assert {:error, {:live_redirect, %{to: "/travel"}}} =
             live(session_conn(conn, character), ~p"/event")

    assert journey.character_id == character.id
  end

  test "the action hub carries a scoped player from the rumor to a real cult passage", %{
    conn: conn,
    realm: realm,
    city: city,
    watchtower: watchtower,
    tower: tower,
    character: character
  } do
    keeper = character_fixture(realm, watchtower, "activity-cult-keeper", "Activity Cult Keeper")

    assert {:ok, %{organization: _cult}} =
             Organizations.create_organization(keeper, :cult, "Activity Hidden Passage", %{
               fast_travel_enabled: true,
               linked_location_ids: [city.id, watchtower.id, tower.id],
               metadata: %{
                 "secret_cult" => true,
                 "discovery_city_id" => city.id,
                 "discovery_watchtower_id" => watchtower.id,
                 "passage_destination_id" => tower.id
               }
             })

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/event")
    assert has_element?(view, "#secret-cult-hear-rumor")

    view |> element("#secret-cult-hear-rumor") |> render_click()
    assert has_element?(view, "#secret-cult-rumor-heard")

    character
    |> Character.travel_changeset(%{current_location_id: watchtower.id})
    |> Repo.update!()

    view |> element("#activity-refresh-scavenging") |> render_click()
    assert has_element?(view, "#secret-cult-reveal-passage")

    view |> element("#secret-cult-reveal-passage") |> render_click()
    assert has_element?(view, "#secret-cult-passage-open")
    assert has_element?(view, "#secret-cult-travel-#{tower.id}")

    view |> element("#secret-cult-travel-#{tower.id}") |> render_click()
    assert has_element?(view, "#secret-cult-travel-#{city.id}")
  end

  defp session_conn(conn, character) do
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
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
