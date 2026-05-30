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

# Pixel coordinates are relative to the 2000×2000 world_map.png
upsert_location = fn realm, attrs ->
  case Worlds.get_location_by_slug(realm.id, attrs.slug) do
    nil ->
      {:ok, loc} = Worlds.create_location(realm, attrs)
      loc
    loc ->
      loc
  end
end

upsert_route = fn realm, attrs ->
  existing =
    Worlds.list_routes_for_location(attrs.origin_location_id)
    |> Enum.find(fn r ->
      r.origin_location_id == attrs.origin_location_id and
        r.destination_location_id == attrs.destination_location_id
    end)

  unless existing do
    {:ok, _} = Worlds.create_route(realm, attrs)
  end
end

capital_city = upsert_location.(canonical_realm, %{
  slug: "capital-city",
  name: "Столица",
  kind: :city,
  x: 960,
  y: 1040,
  safe_zone: true,
  metadata: %{"description" => "Главный город королевства. Здесь расположены Академия, рынки и таверны."}
})

tower = upsert_location.(canonical_realm, %{
  slug: "the-tower",
  name: "Башня",
  kind: :tower,
  x: 830,
  y: 385,
  safe_zone: false,
  metadata: %{"description" => "Единственное место, где работает магия. Здесь начинается подземелье."}
})

northeast_city = upsert_location.(canonical_realm, %{
  slug: "northeast-city",
  name: "Восточный Предел",
  kind: :city,
  x: 1470,
  y: 600,
  safe_zone: true,
  metadata: %{"description" => "Торговый город на востоке. Известен рынками редких ингредиентов."}
})

south_town = upsert_location.(canonical_realm, %{
  slug: "south-town",
  name: "Южный Форт",
  kind: :city,
  x: 1055,
  y: 1345,
  safe_zone: true,
  metadata: %{"description" => "Небольшой укреплённый город на юге. Отправная точка для экспедиций."}
})

far_south_village = upsert_location.(canonical_realm, %{
  slug: "far-south-village",
  name: "Дальняя Слобода",
  kind: :wilderness,
  x: 945,
  y: 1840,
  safe_zone: false,
  metadata: %{"description" => "Отдалённое поселение. Опасно, но богато редкими травами."}
})

mountain_watchtower = upsert_location.(canonical_realm, %{
  slug: "mountain-watchtower",
  name: "Горная Стража",
  kind: :wilderness,
  x: 660,
  y: 855,
  safe_zone: false,
  metadata: %{"description" => "Заброшенная сторожевая башня в горах. Говорят, здесь есть тайные пути."}
})

# Roads visible on the map
upsert_route.(canonical_realm, %{
  name: "Тракт: Столица — Башня",
  origin_location_id: capital_city.id,
  destination_location_id: tower.id,
  travel_days: 10,
  risk_level: 35,
  bidirectional: true,
  realm_id: canonical_realm.id
})

upsert_route.(canonical_realm, %{
  name: "Тракт: Столица — Восточный Предел",
  origin_location_id: capital_city.id,
  destination_location_id: northeast_city.id,
  travel_days: 8,
  risk_level: 25,
  bidirectional: true,
  realm_id: canonical_realm.id
})

upsert_route.(canonical_realm, %{
  name: "Тракт: Столица — Южный Форт",
  origin_location_id: capital_city.id,
  destination_location_id: south_town.id,
  travel_days: 6,
  risk_level: 20,
  bidirectional: true,
  realm_id: canonical_realm.id
})

upsert_route.(canonical_realm, %{
  name: "Тропа: Южный Форт — Дальняя Слобода",
  origin_location_id: south_town.id,
  destination_location_id: far_south_village.id,
  travel_days: 7,
  risk_level: 55,
  bidirectional: true,
  realm_id: canonical_realm.id
})

upsert_route.(canonical_realm, %{
  name: "Горная тропа: Башня — Горная Стража",
  origin_location_id: tower.id,
  destination_location_id: mountain_watchtower.id,
  travel_days: 4,
  risk_level: 60,
  bidirectional: true,
  realm_id: canonical_realm.id
})

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
