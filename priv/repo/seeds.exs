alias MMGO.Dungeons
alias MMGO.Economy
alias MMGO.Inventory.ItemTemplate
alias MMGO.Repo
alias MMGO.Worlds
alias MMGO.Worlds.Realm

ensure_location = fn realm, attrs ->
  case Worlds.get_location_by_slug(realm.id, attrs.slug) do
    nil ->
      {:ok, location} =
        Worlds.create_location(realm, %{
          slug: attrs.slug,
          name: attrs.name,
          kind: attrs.kind,
          x: attrs.x,
          y: attrs.y,
          safe_zone: attrs.safe_zone
        })

      location

    location ->
      {:ok, location} =
        location
        |> Worlds.change_location(%{x: attrs.x, y: attrs.y})
        |> Repo.update()

      location
  end
end

ensure_route = fn realm, attrs ->
  route_exists? =
    Worlds.list_routes_for_location(attrs.origin_location_id)
    |> Enum.any?(fn route ->
      route.origin_location_id == attrs.origin_location_id and
        route.destination_location_id == attrs.destination_location_id
    end)

  if route_exists? do
    :ok
  else
    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: attrs.name,
        origin_location_id: attrs.origin_location_id,
        destination_location_id: attrs.destination_location_id,
        travel_days: attrs.travel_days,
        risk_level: attrs.risk_level,
        bidirectional: attrs.bidirectional
      })

    :ok
  end
end

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
  ensure_location.(canonical_realm, %{
    slug: "capital-city",
    name: "Capital City",
    kind: :city,
    x: 1159,
    y: 872,
    safe_zone: true
  })

amber_harbor =
  ensure_location.(canonical_realm, %{
    slug: "amber-harbor",
    name: "Amber Harbor",
    kind: :city,
    x: 1136,
    y: 640,
    safe_zone: true
  })

ash_crossing =
  ensure_location.(canonical_realm, %{
    slug: "ash-crossing",
    name: "Ash Crossing",
    kind: :wilderness,
    x: 1422,
    y: 753,
    safe_zone: false
  })

watchpoint =
  ensure_location.(canonical_realm, %{
    slug: "watchpoint",
    name: "Watchpoint",
    kind: :wilderness,
    x: 1163,
    y: 1193,
    safe_zone: false
  })

tower =
  ensure_location.(canonical_realm, %{
    slug: "the-tower",
    name: "The Tower",
    kind: :tower,
    x: 1760,
    y: 448,
    safe_zone: false
  })

ensure_route.(canonical_realm, %{
  name: "Capital Road to the Tower",
  origin_location_id: capital_city.id,
  destination_location_id: tower.id,
  travel_days: 10,
  risk_level: 35,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "Merchant Wake",
  origin_location_id: capital_city.id,
  destination_location_id: amber_harbor.id,
  travel_days: 3,
  risk_level: 8,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "Ash Road",
  origin_location_id: capital_city.id,
  destination_location_id: ash_crossing.id,
  travel_days: 4,
  risk_level: 18,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "Harbor Trace",
  origin_location_id: amber_harbor.id,
  destination_location_id: ash_crossing.id,
  travel_days: 5,
  risk_level: 24,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "Watchers' Spur",
  origin_location_id: ash_crossing.id,
  destination_location_id: watchpoint.id,
  travel_days: 4,
  risk_level: 46,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "Pilgrim Stair",
  origin_location_id: ash_crossing.id,
  destination_location_id: tower.id,
  travel_days: 7,
  risk_level: 52,
  bidirectional: true
})

ensure_route.(canonical_realm, %{
  name: "High Watch Road",
  origin_location_id: watchpoint.id,
  destination_location_id: tower.id,
  travel_days: 5,
  risk_level: 68,
  bidirectional: true
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

ensure_ingredient = fn attrs ->
  case Repo.get_by(ItemTemplate, code: attrs.code) do
    nil ->
      %ItemTemplate{}
      |> ItemTemplate.changeset(%{
        code: attrs.code,
        name: attrs.name,
        item_type: :ingredient,
        description: attrs.description,
        qualities: attrs.qualities,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0
      })
      |> Repo.insert!()

    existing ->
      existing
  end
end

base_ingredients = [
  # Fire
  %{
    code: "ember-moss",
    name: "Ember Moss",
    description:
      "A rust-red moss found near volcanic vents. Burns to the touch. Excellent catalyst for fire brews but notoriously unstable.",
    qualities: ["fire_catalyst", "volatile"]
  },
  %{
    code: "magma-shard",
    name: "Magma Shard",
    description:
      "A crystallized fragment of cooled lava, still warm to the touch. Corrodes container walls if left unbound.",
    qualities: ["fire_catalyst", "corrosive"]
  },
  %{
    code: "searing-petal",
    name: "Searing Petal",
    description:
      "Thin petals from a heat-resistant desert flower. Carries fire affinity but burns clean with no dangerous residue.",
    qualities: ["fire_catalyst", "stabilizing"]
  },
  # Restoration
  %{
    code: "moonleaf",
    name: "Moonleaf",
    description:
      "A soft silver-green leaf harvested at night. The base of most healing draughts, mild and reliable.",
    qualities: ["restorative", "purifying"]
  },
  %{
    code: "healers-root",
    name: "Healer's Root",
    description:
      "A dense fibrous root from the wetlands. Slow to process but provides sustained healing that holds with binding agents.",
    qualities: ["restorative", "binding"]
  },
  %{
    code: "dewdrop-fungus",
    name: "Dewdrop Fungus",
    description:
      "A small white mushroom found in cool cave systems. Extremely stable in solution — the alchemist's safety net.",
    qualities: ["restorative", "stabilizing"]
  },
  # Structure & Duration
  %{
    code: "ironwood-bark",
    name: "Ironwood Bark",
    description:
      "Dried bark from an ironwood tree, dense and resinous. Unremarkable alone but indispensable in complex brews.",
    qualities: ["binding", "stabilizing"]
  },
  %{
    code: "spider-silk-extract",
    name: "Spider Silk Extract",
    description:
      "A viscous extract from dungeon spider webs. Exceptional binding properties and unusual magical conductivity.",
    qualities: ["binding", "conductive"]
  },
  # Arcane & Utility
  %{
    code: "glowstone-dust",
    name: "Glowstone Dust",
    description:
      "Ground from naturally occurring luminous mineral deposits. Core ingredient for visibility potions and detection brews.",
    qualities: ["luminous", "conductive"]
  },
  %{
    code: "witchwood-ash",
    name: "Witchwood Ash",
    description:
      "Ash from a ritually burned witchwood branch. A potent magical amplifier, unpredictable without a stabilizer.",
    qualities: ["arcane", "volatile"]
  },
  %{
    code: "nullweave-fiber",
    name: "Nullweave Fiber",
    description:
      "Pale fibers from a plant that grows only where old spells have faded. Suppresses residual magical contamination.",
    qualities: ["purifying", "stabilizing"]
  },
  # Offensive
  %{
    code: "viper-venom",
    name: "Viper Venom",
    description:
      "Extracted from overworld vipers. Potent in small doses but degrades quickly without a preserving stabilizer.",
    qualities: ["toxic", "volatile"]
  },
  %{
    code: "thornwood-extract",
    name: "Thornwood Extract",
    description:
      "A resin from thornwood branches. Corrodes soft materials slowly but binds well, useful in sustained corrosive brews.",
    qualities: ["corrosive", "binding"]
  },
  %{
    code: "blacksalt",
    name: "Blacksalt",
    description:
      "A black mineral salt from deep dungeon seams. Toxic in quantity, numbing in trace amounts.",
    qualities: ["toxic", "numbing"]
  },
  # Control
  %{
    code: "dream-poppy",
    name: "Dream Poppy",
    description:
      "Dried petals from a rare flower found in sheltered dungeon alcoves. The primary ingredient in sleep preparations.",
    qualities: ["soporific", "numbing"]
  }
]

Enum.each(base_ingredients, ensure_ingredient)
