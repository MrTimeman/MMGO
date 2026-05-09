defmodule MMGOWeb.PlayApiControllerTest do
  use MMGOWeb.ConnCase, async: false

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 120,
        y: 180,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 860,
        y: 260,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 35,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "travel_ration",
        name: "Travel Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    %{realm: realm, city: city, tower: tower, route: route, ration_template: ration_template}
  end

  test "state bootstraps a reusable browser character", %{conn: conn} do
    conn = get(conn, ~p"/api/play/state")
    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert state["realm"]["name"] == "Canonical Realm"
    assert state["current_location"]["slug"] == "capital-city"
    assert length(state["available_routes"]) == 1
    assert state["supplies"]["food_units_available"] >= 0

    browser_character_id = state["character"]["id"]

    conn =
      conn
      |> recycle()
      |> get(~p"/api/play/state")

    repeated_payload = json_response(conn, 200)
    assert get_in(repeated_payload, ["state", "character", "id"]) == browser_character_id
  end

  test "journeys endpoint starts travel for the session character", %{
    conn: conn,
    realm: realm,
    city: city,
    route: route,
    tower: tower,
    ration_template: ration_template
  } do
    character = character_fixture(realm, city, "traveler", "Traveler")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    conn =
      conn
      |> init_test_session(%{play_character_id: character.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/journeys", Jason.encode!(%{route_id: route.id}))

    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert get_in(state, ["active_journey", "to_location_id"]) == tower.id
    assert get_in(state, ["active_journey", "from_location_id"]) == city.id
    assert state["player"]["traveling"] == true
    assert state["available_routes"] == []
    assert %Travel.Journey{} = Travel.active_journey(character.id)
  end

  test "state completes a due journey and lands at the destination", %{
    conn: conn,
    realm: realm,
    city: city,
    tower: tower,
    route: route,
    ration_template: ration_template
  } do
    character = character_fixture(realm, city, "returner", "Returner")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    started_at =
      DateTime.add(
        DateTime.utc_now(),
        -(Clock.game_days_to_real_seconds(route.travel_days) + 120),
        :second
      )

    assert {:ok, %{journey: _journey}} =
             Travel.start_journey(character, route, started_at: started_at)

    conn =
      conn
      |> init_test_session(%{play_character_id: character.id})
      |> get(~p"/api/play/state")

    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert state["active_journey"] == nil
    assert get_in(state, ["current_location", "id"]) == tower.id

    updated_character = Repo.get!(Character, character.id)
    assert updated_character.current_location_id == tower.id
  end

  test "journeys endpoint rejects routes disconnected from the current location", %{
    conn: conn,
    realm: realm,
    tower: tower,
    ration_template: ration_template
  } do
    {:ok, outpost} =
      Worlds.create_location(realm, %{
        slug: "northern-outpost",
        name: "Northern Outpost",
        kind: :wilderness,
        x: 980,
        y: 120,
        safe_zone: false
      })

    {:ok, off_route} =
      Worlds.create_route(realm, %{
        name: "Outpost Spur",
        origin_location_id: outpost.id,
        destination_location_id: tower.id,
        travel_days: 6,
        risk_level: 55,
        bidirectional: false
      })

    character = character_fixture(realm, tower, "anchored", "Anchored")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    conn =
      conn
      |> init_test_session(%{play_character_id: character.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/journeys", Jason.encode!(%{route_id: off_route.id}))

    payload = json_response(conn, 422)

    assert payload["ok"] == false

    assert get_in(payload, ["details", "route_id"]) == [
             "route is not connected to the character's current location"
           ]
  end

  test "demo reset returns the session character to the entry city and clears travel", %{
    conn: conn,
    realm: realm,
    city: city,
    route: route,
    ration_template: ration_template
  } do
    character = character_fixture(realm, city, "demoer", "Demoer")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})
    assert {:ok, %{journey: _journey}} = Travel.start_journey(character, route)

    conn =
      conn
      |> init_test_session(%{play_character_id: character.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/demo/reset", Jason.encode!(%{}))

    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert state["active_journey"] == nil
    assert get_in(state, ["current_location", "id"]) == city.id
    assert state["player"]["traveling"] == false

    [latest_journey] = Travel.list_journeys_for_character(character.id)
    assert latest_journey.status == :cancelled
  end

  test "utility spells endpoint reveals a hidden dungeon node for the session character", %{
    conn: conn,
    realm: realm,
    tower: tower
  } do
    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "utility-dungeon",
        name: "Utility Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Gloam Ring"})

    {:ok, entrance_node} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Vault Threshold",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 1
      })

    {:ok, hidden_node} =
      Dungeons.create_node(floor, %{
        slug: "hidden-alcove",
        name: "Hidden Alcove",
        kind: :room,
        x: 1,
        y: 0,
        threat_level: 3,
        metadata: %{"hidden" => true}
      })

    leader = character_fixture(realm, tower, "utility-mage", "Utility Mage")

    {:ok, spell} =
      Spells.create_spell(leader, %{
        name: "Lux Revelio",
        formula: "Lux Revelio",
        school: :order,
        spell_type: :utility,
        targeting: :zone,
        delivery_form: :zone,
        effects: [
          %{applies_to: :environment, state: "revealed", intensity: 1, variance: 0, duration: 1}
        ],
        failure_profile: %{difficulty: 4, base_success_rate: 95, partial_success_rate: 4}
      })

    {:ok, grimoire} =
      Grimoires.create_grimoire(leader, %{name: "Survey Book", capacity: 4, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)

    {:ok, %{activate_grimoire: _grimoire}} =
      Grimoires.activate_grimoire(leader, Grimoires.get_grimoire!(grimoire.id))

    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Surveyors"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    assert {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    conn =
      conn
      |> init_test_session(%{play_character_id: leader.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/utility-spells", Jason.encode!(%{spell_id: spell.id}))

    payload = json_response(conn, 200)

    assert payload["ok"] == true
    assert get_in(payload, ["state", "dungeon", "current_node_name"]) == entrance_node.name
    assert get_in(payload, ["state", "magic", "utility_spells"]) != []

    hidden_state = Repo.get_by!(Dungeons.NodeState, run_id: run.id, node_id: hidden_node.id)

    assert hidden_state.metadata["revealed"] == true
    assert Enum.any?(hidden_state.metadata["environment_states"], &(&1["state"] == "revealed"))
  end

  test "dungeon state exposes the expedition map, exits, and extraction readiness", %{
    conn: conn,
    realm: realm,
    tower: tower
  } do
    %{
      dungeon: dungeon,
      entrance_node: entrance_node,
      rest_node: rest_node,
      run: run,
      leader: leader
    } =
      dungeon_run_fixture(realm, tower, "state")

    conn =
      conn
      |> init_test_session(%{play_character_id: leader.id})
      |> get(~p"/api/play/dungeons/state")

    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert state["dungeon_name"] == dungeon.name
    assert state["current_node"]["id"] == entrance_node.id
    assert state["current_node"]["description"] =~ "Башней"
    assert state["extraction"]["can_ascent"] == true
    assert state["progress"]["known_nodes"] == 2
    assert state["progress"]["available_resources"] == 1

    assert [%{"id" => rest_node_id}] = state["current_node"]["exits"]
    assert rest_node_id == rest_node.id
    assert Enum.any?(state["nodes"], &(&1["id"] == rest_node.id and &1["reachable"] == true))

    conn =
      conn
      |> recycle()
      |> init_test_session(%{play_character_id: leader.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/dungeons/extract", Jason.encode!(%{}))

    extract_payload = json_response(conn, 200)
    assert extract_payload["ok"] == true
    assert get_in(extract_payload, ["result", "status"]) == "completed"
    assert Repo.reload!(run).status == :completed
  end

  test "dungeon move keeps already visited adjacent rooms reachable", %{
    conn: conn,
    realm: realm,
    tower: tower
  } do
    %{
      entrance_node: entrance_node,
      rest_node: rest_node,
      deeper_node: deeper_node,
      leader: leader
    } =
      dungeon_run_fixture(realm, tower, "move")

    conn =
      conn
      |> init_test_session(%{play_character_id: leader.id})
      |> put_json_csrf_header()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/play/dungeons/move", Jason.encode!(%{to_node_id: rest_node.id}))

    payload = json_response(conn, 200)
    state = payload["state"]

    assert payload["ok"] == true
    assert state["current_node"]["id"] == rest_node.id

    entrance_payload = Enum.find(state["nodes"], &(&1["id"] == entrance_node.id))
    assert entrance_payload["state"] == "visited"
    assert entrance_payload["reachable"] == true

    exit_ids = Enum.map(state["current_node"]["exits"], & &1["id"])
    assert entrance_node.id in exit_ids
    assert deeper_node.id in exit_ids
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: name,
        handle: "#{handle}-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, level: 7})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp dungeon_run_fixture(realm, tower, slug_suffix) do
    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon-#{slug_suffix}",
        name: "Tower Dungeon #{slug_suffix}",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})

    {:ok, entrance_node} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Tower Gate",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 0
      })

    {:ok, rest_node} =
      Dungeons.create_node(floor, %{
        slug: "rest",
        name: "Lantern Niche",
        kind: :rest,
        x: 1,
        y: 0,
        threat_level: 0
      })

    {:ok, deeper_node} =
      Dungeons.create_node(floor, %{
        slug: "deeper",
        name: "Cold Gallery",
        kind: :room,
        x: 2,
        y: 0,
        threat_level: 0
      })

    {:ok, _entry_link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: rest_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    {:ok, _gallery_link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: rest_node.id,
        to_node_id: deeper_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    leader = character_fixture(realm, tower, "delver-#{slug_suffix}", "Delver #{slug_suffix}")
    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Tower Survey"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    %{
      dungeon: dungeon,
      entrance_node: entrance_node,
      rest_node: rest_node,
      deeper_node: deeper_node,
      leader: leader,
      run: run
    }
  end

  defp put_json_csrf_header(conn) do
    put_req_header(conn, "x-csrf-token", Phoenix.Controller.get_csrf_token())
  end
end
