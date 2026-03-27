defmodule MMGO.DungeonsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Dungeons.{NodeState, Run}
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 260,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 20,
        bidirectional: true
      })

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon",
        name: "Tower Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor_one} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})
    {:ok, floor_two} = Dungeons.create_floor(dungeon, %{number: 2, name: "Lower Halls"})

    {:ok, entrance_node} =
      Dungeons.create_node(floor_one, %{
        slug: "entrance",
        name: "Entrance Hall",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 5
      })

    {:ok, rest_node} =
      Dungeons.create_node(floor_one, %{
        slug: "rest",
        name: "Rest Chamber",
        kind: :rest,
        x: 1,
        y: 0,
        threat_level: 0
      })

    {:ok, deeper_node} =
      Dungeons.create_node(floor_two, %{
        slug: "deeper",
        name: "Deeper Hall",
        kind: :room,
        x: 2,
        y: 0,
        threat_level: 25
      })

    {:ok, _entrance_link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: rest_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    {:ok, _descent_link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: rest_node.id,
        to_node_id: deeper_node.id,
        travel_cost: 2,
        bidirectional: false
      })

    leader = character_fixture(realm, tower, "leader-mage", "Leader Mage")
    member = character_fixture(realm, tower, "member-mage", "Member Mage")
    traveler = character_fixture(realm, city, "traveler-mage", "Traveler Mage")

    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Tower Delvers"})
    {:ok, %{membership: _membership}} = Parties.add_member(party, member)
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    %{
      realm: realm,
      city: city,
      tower: tower,
      route: route,
      dungeon: dungeon,
      entrance_node: entrance_node,
      rest_node: rest_node,
      deeper_node: deeper_node,
      expedition: expedition,
      traveler: traveler
    }
  end

  test "enter_dungeon/3 creates an active run at the entrance node", %{
    expedition: expedition,
    dungeon: dungeon,
    entrance_node: entrance_node
  } do
    assert {:ok, %{run: run, node_state: node_state}} =
             Dungeons.enter_dungeon(expedition, dungeon)

    assert run.status == :active
    assert run.current_node_id == entrance_node.id
    assert node_state.status == :current
    assert node_state.node_id == entrance_node.id
  end

  test "move_run/3 progresses through linked nodes and updates node state", %{
    expedition: expedition,
    dungeon: dungeon,
    rest_node: rest_node,
    deeper_node: deeper_node
  } do
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    assert {:ok, %{run: moved_run}} = Dungeons.move_run(run, rest_node.id)
    assert moved_run.current_node_id == rest_node.id
    assert moved_run.steps_taken == 1

    assert {:ok, %{run: deeper_run}} =
             Dungeons.move_run(moved_run, deeper_node.id, leave_status: :cleared)

    assert deeper_run.current_node_id == deeper_node.id
    assert deeper_run.current_floor_id == deeper_node.floor_id
    assert deeper_run.steps_taken == 3

    rest_state = Repo.get_by!(NodeState, run_id: run.id, node_id: rest_node.id)
    assert rest_state.status == :cleared
  end

  test "update_node_state/3 attaches encounter and resource state to a run node", %{
    expedition: expedition,
    dungeon: dungeon,
    entrance_node: entrance_node
  } do
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    assert {:ok, node_state} =
             Dungeons.update_node_state(run, entrance_node.id, %{
               encounter_status: :cleared,
               resource_status: :depleted,
               metadata: %{"loot" => "claimed"}
             })

    assert node_state.encounter_status == :cleared
    assert node_state.resource_status == :depleted
    assert node_state.metadata["loot"] == "claimed"
  end

  test "end_run/3 marks a dungeon run as completed", %{expedition: expedition, dungeon: dungeon} do
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    assert {:ok, %Run{} = updated_run} = Dungeons.end_run(run, :completed)
    assert updated_run.status == :completed
    assert updated_run.ended_at
  end

  test "enter_dungeon/3 rejects expeditions not at the entrance location", %{
    city: city,
    traveler: traveler,
    dungeon: dungeon
  } do
    traveler =
      traveler
      |> Character.travel_changeset(%{current_location_id: city.id})
      |> Repo.update!()

    {:ok, %{party: party}} = Parties.create_party(traveler, %{name: "Lost Party"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    assert {:error, changeset} = Dungeons.enter_dungeon(expedition, dungeon)

    assert %{status: ["expedition must start at the dungeon entrance location"]} =
             errors_on(changeset)
  end

  test "enter_dungeon/3 rejects expeditions that already have an active run", %{
    expedition: expedition,
    dungeon: dungeon
  } do
    assert {:ok, %{run: _run}} = Dungeons.enter_dungeon(expedition, dungeon)
    assert {:error, changeset} = Dungeons.enter_dungeon(expedition, dungeon)
    assert %{status: ["expedition already has an active dungeon run"]} = errors_on(changeset)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
