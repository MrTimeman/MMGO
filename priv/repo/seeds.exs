alias MMGO.Dungeons
alias MMGO.Economy
alias MMGO.Repo
alias MMGO.Worlds
alias MMGO.Worlds.Realm

canonical_realm =
  case Repo.get_by(Realm, slug: "canonical") do
    nil ->
      Repo.insert!(%Realm{
        slug: "canonical",
        name: "Canonical Realm",
        status: :active,
        ruleset_version: 1,
        is_default: true,
        metadata: %{"description" => "Default MMGO realm for local development"}
      })

    realm ->
      realm
  end

{:ok, _treasury_account} = Economy.ensure_treasury_account(canonical_realm, 1_000_000_000)

capital_city =
  case Worlds.get_location_by_slug(canonical_realm.id, "capital-city") do
    nil ->
      {:ok, location} =
        Worlds.create_location(canonical_realm, %{
          slug: "capital-city",
          name: "Capital City",
          kind: :city,
          x: 120,
          y: 180,
          safe_zone: true
        })

      location

    location ->
      location
  end

tower =
  case Worlds.get_location_by_slug(canonical_realm.id, "the-tower") do
    nil ->
      {:ok, location} =
        Worlds.create_location(canonical_realm, %{
          slug: "the-tower",
          name: "The Tower",
          kind: :tower,
          x: 860,
          y: 260,
          safe_zone: false
        })

      location

    location ->
      location
  end

case Worlds.list_routes_for_location(capital_city.id)
     |> Enum.find(fn route ->
       route.origin_location_id == capital_city.id and route.destination_location_id == tower.id
     end) do
  nil ->
    {:ok, _route} =
      Worlds.create_route(canonical_realm, %{
        name: "Capital Road to the Tower",
        origin_location_id: capital_city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 35,
        bidirectional: true
      })

  _route ->
    :ok
end

canonical_dungeon =
  case Dungeons.get_dungeon_by_slug(canonical_realm.id, "tower-dungeon") do
    nil ->
      {:ok, dungeon} =
        Dungeons.create_dungeon(canonical_realm, %{
          slug: "tower-dungeon",
          name: "Tower Dungeon",
          status: :active,
          entrance_location_id: tower.id
        })

      dungeon

    dungeon ->
      dungeon
  end

upper_halls =
  case Repo.get_by(Dungeons.Floor, dungeon_id: canonical_dungeon.id, number: 1) do
    nil ->
      {:ok, floor} = Dungeons.create_floor(canonical_dungeon, %{number: 1, name: "Upper Halls"})
      floor

    floor ->
      floor
  end

entrance_node =
  case Repo.get_by(Dungeons.Node, floor_id: upper_halls.id, slug: "entrance") do
    nil ->
      {:ok, node} =
        Dungeons.create_node(upper_halls, %{
          slug: "entrance",
          name: "Entrance Hall",
          kind: :entrance,
          x: 0,
          y: 0,
          threat_level: 5
        })

      node

    node ->
      node
  end

rest_node =
  case Repo.get_by(Dungeons.Node, floor_id: upper_halls.id, slug: "rest-chamber") do
    nil ->
      {:ok, node} =
        Dungeons.create_node(upper_halls, %{
          slug: "rest-chamber",
          name: "Rest Chamber",
          kind: :rest,
          x: 1,
          y: 0,
          threat_level: 0
        })

      node

    node ->
      node
  end

case Repo.get_by(Dungeons.Link, from_node_id: entrance_node.id, to_node_id: rest_node.id) do
  nil ->
    {:ok, _link} =
      Dungeons.create_link(canonical_dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: rest_node.id,
        travel_cost: 1,
        bidirectional: true
      })

  _link ->
    :ok
end
