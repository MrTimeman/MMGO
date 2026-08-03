alias MMGO.Accounts.{Account, Character}
alias MMGO.Academy
alias MMGO.Academia.Professor
alias MMGO.Dungeons
alias MMGO.Economy
alias MMGO.Inventory
alias MMGO.Inventory.ItemTemplate
alias MMGO.Organizations
alias MMGO.Organizations.Organization
alias MMGO.Repo
alias MMGO.Scavenging
alias MMGO.Worlds
alias MMGO.Worlds.Realm

canonical_realm =
  case Repo.get_by(Realm, slug: "canonical") do
    nil ->
      Repo.insert!(%Realm{
        slug: "canonical",
        name: "Основной мир",
        status: :active,
        ruleset_version: 1,
        is_default: true,
        metadata: %{"description" => "Основной мир закрытой альфы MMGO"}
      })

    realm ->
      if realm.name == "Canonical Realm" do
        realm
        |> Ecto.Changeset.change(%{
          name: "Основной мир",
          metadata: %{"description" => "Основной мир закрытой альфы MMGO"}
        })
        |> Repo.update!()
      else
        realm
      end
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
      |> Worlds.change_location(attrs)
      |> Repo.update!()
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

capital_city =
  upsert_location.(canonical_realm, %{
    slug: "capital-city",
    name: "Столица",
    kind: :city,
    x: 960,
    y: 1040,
    safe_zone: true,
    metadata: %{
      "description" => "Главный город королевства. Здесь расположены Академия, рынки и таверны.",
      "base_purchase_price" => 500
    }
  })

ensure_npc_professor = fn handle, name ->
  account =
    Repo.get_by(Account, handle: handle) ||
      Repo.insert!(
        Account.registration_changeset(%Account{}, %{
          display_name: name,
          handle: handle,
          settings: %{"npc" => true}
        })
      )

  character =
    Repo.get_by(Character, account_id: account.id, realm_id: canonical_realm.id) ||
      Repo.insert!(
        Character.changeset(%Character{account_id: account.id, realm_id: canonical_realm.id}, %{
          name: name,
          status: :active,
          level: 30,
          xp: 0,
          metadata: %{"npc" => true, "academy_faculty" => true}
        })
      )

  character =
    if character.current_location_id == capital_city.id do
      character
    else
      character
      |> Character.travel_changeset(%{current_location_id: capital_city.id})
      |> Repo.update!()
    end

  Repo.get_by(Professor, character_id: character.id, status: :active) ||
    Repo.insert!(
      Professor.changeset(%Professor{}, %{
        character_id: character.id,
        realm_id: canonical_realm.id,
        status: :active,
        appointed_at: DateTime.utc_now(),
        metadata: %{"npc_faculty" => true}
      })
    )
end

for {handle, name} <- [
      {"academy-professor-aurelia", "Профессор Аурелия"},
      {"academy-professor-boreas", "Профессор Борей"},
      {"academy-professor-cyran", "Профессор Сиран"}
    ] do
  ensure_npc_professor.(handle, name)
end

_seeded_courses = Academy.seed_courses_for_realm(canonical_realm.id)

tower =
  upsert_location.(canonical_realm, %{
    slug: "the-tower",
    name: "Башня",
    kind: :tower,
    x: 830,
    y: 385,
    safe_zone: false,
    metadata: %{
      "description" => "Единственное место, где работает магия. Здесь начинается подземелье.",
      "base_build_price" => 400,
      "base_build_game_days" => 35,
      "base_build_materials" => %{"construction_material" => 8}
    }
  })

northeast_city =
  upsert_location.(canonical_realm, %{
    slug: "northeast-city",
    name: "Восточный Предел",
    kind: :city,
    x: 1470,
    y: 600,
    safe_zone: true,
    metadata: %{
      "description" => "Торговый город на востоке. Известен рынками редких ингредиентов.",
      "base_purchase_price" => 650
    }
  })

south_town =
  upsert_location.(canonical_realm, %{
    slug: "south-town",
    name: "Южный Форт",
    kind: :city,
    x: 1055,
    y: 1345,
    safe_zone: true,
    metadata: %{
      "description" => "Небольшой укреплённый город на юге. Отправная точка для экспедиций.",
      "base_purchase_price" => 425
    }
  })

far_south_village =
  upsert_location.(canonical_realm, %{
    slug: "far-south-village",
    name: "Дальняя Слобода",
    kind: :wilderness,
    x: 945,
    y: 1840,
    safe_zone: false,
    metadata: %{
      "description" => "Отдалённое поселение. Опасно, но богато редкими травами.",
      "base_build_price" => 225,
      "base_build_game_days" => 21,
      "base_build_materials" => %{"construction_material" => 5}
    }
  })

mountain_watchtower =
  upsert_location.(canonical_realm, %{
    slug: "mountain-watchtower",
    name: "Горная Стража",
    kind: :wilderness,
    x: 660,
    y: 855,
    safe_zone: false,
    metadata: %{
      "description" => "Заброшенная сторожевая башня в горах. Говорят, здесь есть тайные пути.",
      "base_build_price" => 300,
      "base_build_game_days" => 28,
      "base_build_materials" => %{"construction_material" => 6}
    }
  })

construction_material =
  Repo.get_by(ItemTemplate, code: "construction_material") ||
    case Inventory.create_item_template(%{
           code: "construction_material",
           name: "Строевой камень",
           item_type: :ingredient,
           stackable: true,
           weight: 2,
           max_durability: 0,
           nutrition_units: 0,
           tags: ["construction", "scavenged"],
           actions: [],
           metadata: %{
             "alchemical_primitives" => %{"earth" => 3, "binding" => 2}
           }
         }) do
      {:ok, template} -> template
      {:error, _changeset} -> Repo.get_by!(ItemTemplate, code: "construction_material")
    end

for location <- [tower, far_south_village, mountain_watchtower] do
  {:ok, _cache} =
    Scavenging.ensure_resource_cache(location, %{
      resource_code: "construction_material",
      item_template_id: construction_material.id,
      quantity_total: 12,
      quantity_remaining: 12,
      respawn_game_days: 21,
      metadata: %{"purpose" => "base_construction"}
    })
end

secret_cult_account =
  Repo.get_by(Account, handle: "secret-cult-keeper") ||
    Repo.insert!(
      Account.registration_changeset(%Account{}, %{
        display_name: "Хранитель Тайного Культа",
        handle: "secret-cult-keeper",
        settings: %{"npc" => true}
      })
    )

secret_cult_founder =
  Repo.get_by(Character, account_id: secret_cult_account.id, realm_id: canonical_realm.id) ||
    Repo.insert!(
      Character.changeset(
        %Character{account_id: secret_cult_account.id, realm_id: canonical_realm.id},
        %{
          name: "Хранитель Тайного Культа",
          status: :active,
          level: 40,
          xp: 0,
          metadata: %{"npc" => true, "secret_cult_keeper" => true}
        }
      )
    )

if not is_nil(secret_cult_founder.current_location_id) do
  secret_cult_founder
  |> Character.travel_changeset(%{current_location_id: nil})
  |> Repo.update!()
end

secret_cult_metadata = %{
  "seeded" => true,
  "secret_cult" => true,
  "description" => "Хранители подземных путей между Столицей, Горной Стражей и Башней.",
  "discovery_city_id" => capital_city.id,
  "discovery_watchtower_id" => mountain_watchtower.id,
  "passage_destination_id" => tower.id
}

secret_cult_linked_location_ids =
  [capital_city.id, mountain_watchtower.id, tower.id, far_south_village.id]
  |> Enum.uniq()

case Organizations.list_active_organizations_for_realm(canonical_realm.id)
     |> Enum.find(&(&1.name == "Тайный Культ")) do
  nil ->
    {:ok, %{organization: _secret_cult}} =
      Organizations.create_organization(secret_cult_founder, :cult, "Тайный Культ", %{
        fast_travel_enabled: true,
        linked_location_ids: secret_cult_linked_location_ids,
        metadata: secret_cult_metadata
      })

    :ok

  %Organization{} = secret_cult ->
    secret_cult
    |> Organization.changeset(%{
      fast_travel_enabled: true,
      linked_location_ids: secret_cult_linked_location_ids,
      metadata: Map.merge(secret_cult.metadata || %{}, secret_cult_metadata)
    })
    |> Repo.update!()

    :ok
end

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
          name: "Подземелье Башни",
          status: :active,
          entrance_location_id: tower.id
        })

      dungeon

    dungeon ->
      if dungeon.name == "Tower Dungeon" do
        dungeon |> Ecto.Changeset.change(name: "Подземелье Башни") |> Repo.update!()
      else
        dungeon
      end
  end

upper_halls =
  case Repo.get_by(Dungeons.Floor, dungeon_id: canonical_dungeon.id, number: 1) do
    nil ->
      {:ok, floor} = Dungeons.create_floor(canonical_dungeon, %{number: 1, name: "Верхние залы"})
      floor

    floor ->
      if floor.name == "Upper Halls" do
        floor |> Ecto.Changeset.change(name: "Верхние залы") |> Repo.update!()
      else
        floor
      end
  end

entrance_node =
  case Repo.get_by(Dungeons.Node, floor_id: upper_halls.id, slug: "entrance") do
    nil ->
      {:ok, node} =
        Dungeons.create_node(upper_halls, %{
          slug: "entrance",
          name: "Входной зал",
          kind: :entrance,
          x: 0,
          y: 0,
          threat_level: 5
        })

      node

    node ->
      if node.name == "Entrance Hall" do
        node |> Ecto.Changeset.change(name: "Входной зал") |> Repo.update!()
      else
        node
      end
  end

rest_node =
  case Repo.get_by(Dungeons.Node, floor_id: upper_halls.id, slug: "rest-chamber") do
    nil ->
      {:ok, node} =
        Dungeons.create_node(upper_halls, %{
          slug: "rest-chamber",
          name: "Комната отдыха",
          kind: :rest,
          x: 1,
          y: 0,
          threat_level: 0
        })

      node

    node ->
      if node.name == "Rest Chamber" do
        node |> Ecto.Changeset.change(name: "Комната отдыха") |> Repo.update!()
      else
        node
      end
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

ensure_floor = fn number, name ->
  case Repo.get_by(Dungeons.Floor, dungeon_id: canonical_dungeon.id, number: number) do
    nil ->
      {:ok, floor} = Dungeons.create_floor(canonical_dungeon, %{number: number, name: name})
      floor

    floor ->
      floor
  end
end

ensure_node = fn floor, attrs ->
  case Repo.get_by(Dungeons.Node, floor_id: floor.id, slug: attrs.slug) do
    nil ->
      {:ok, node} = Dungeons.create_node(floor, attrs)
      node

    node ->
      node
  end
end

ensure_link = fn from_node, to_node, attrs ->
  case Repo.get_by(Dungeons.Link, from_node_id: from_node.id, to_node_id: to_node.id) do
    nil ->
      {:ok, _link} =
        Dungeons.create_link(
          canonical_dungeon,
          %{
            from_node_id: from_node.id,
            to_node_id: to_node.id,
            travel_cost: 1,
            bidirectional: true,
            metadata: %{}
          }
          |> Map.merge(attrs)
        )

      :ok

    _link ->
      :ok
  end
end

# The shipped Tower has seven linked floors, each with a real graph node path.
# Content remains dynamic at run time; these are canonical navigation anchors,
# not a static demo screen.
floor_specs = [
  {2, "Галереи Резонанса", "resonance-gallery", "Галерея Резонанса", :room, 22},
  {3, "Сады Пепла", "ash-garden", "Сады Пепла", :hazard, 34},
  {4, "Архив Печатей", "seal-archive", "Архив Печатей", :room, 46},
  {5, "Колокольные Колодцы", "bell-wells", "Колокольные Колодцы", :hazard, 58},
  {6, "Зеркальный Предел", "mirror-reach", "Зеркальный Предел", :room, 70},
  {7, "Сердце Башни", "tower-heart", "Сердце Башни", :boss, 90}
]

Enum.reduce(floor_specs, rest_node, fn {number, floor_name, slug, node_name, node_kind, threat},
                                       previous_node ->
  floor = ensure_floor.(number, floor_name)

  ascent =
    ensure_node.(floor, %{
      slug: "floor-#{number}-ascent",
      name: "Подъём на уровень #{number}",
      kind: :stairs_up,
      x: 0,
      y: 0,
      threat_level: 0
    })

  challenge =
    ensure_node.(floor, %{
      slug: slug,
      name: node_name,
      kind: node_kind,
      x: 1,
      y: 0,
      threat_level: threat
    })

  onward =
    if number == 7 do
      exit_node =
        ensure_node.(floor, %{
          slug: "tower-heart-exit",
          name: "Путь к поверхности",
          kind: :exit,
          x: 2,
          y: 0,
          threat_level: 0
        })

      exit_node
    else
      ensure_node.(floor, %{
        slug: "floor-#{number}-descent",
        name: "Спуск в глубину",
        kind: :stairs_down,
        x: 2,
        y: 0,
        threat_level: 0
      })
    end

  ensure_link.(previous_node, ascent, %{})
  ensure_link.(ascent, challenge, %{})
  ensure_link.(challenge, onward, %{})
  onward
end)

# The main ascent is deliberately stable, while each floor also has a small,
# fixed set of navigational choices. The dungeon maintenance system can still
# alter availability at runtime; these anchors ensure that the shipped Tower
# is a graph rather than a single corridor from the first seed.
floor_for = fn number ->
  Repo.get_by!(Dungeons.Floor, dungeon_id: canonical_dungeon.id, number: number)
end

node_for = fn slug ->
  Dungeons.get_node_by_slug_in_dungeon(canonical_dungeon.id, slug) ||
    raise "Tower topology anchor #{slug} was not seeded"
end

ensure_topology_node = fn floor_number, attrs ->
  floor_number
  |> floor_for.()
  |> ensure_node.(attrs)
end

provisioning_nook =
  ensure_topology_node.(1, %{
    slug: "provisioning-nook",
    name: "Кладовая делверов",
    kind: :rest,
    x: 1,
    y: 1,
    threat_level: 0,
    metadata: %{
      "seeded" => true,
      "topology_role" => "side_resource",
      "resource_hint" => "rest_supplies"
    }
  })

cinder_cache =
  ensure_topology_node.(3, %{
    slug: "cinder-cache",
    name: "Пепельный схрон",
    kind: :room,
    x: 1,
    y: 1,
    threat_level: 18,
    metadata: %{
      "seeded" => true,
      "topology_role" => "dead_end_resource",
      "resource_hint" => "salvage"
    }
  })

sealed_annex =
  ensure_topology_node.(4, %{
    slug: "sealed-annex",
    name: "Запечатанный придел",
    kind: :room,
    x: 1,
    y: 1,
    threat_level: 20,
    metadata: %{
      "seeded" => true,
      "topology_role" => "alternate_passage",
      "route_note" => "Тихий обход главного архива"
    }
  })

quiet_well =
  ensure_topology_node.(5, %{
    slug: "quiet-well",
    name: "Тихий колодец",
    kind: :rest,
    x: 1,
    y: 1,
    threat_level: 0,
    metadata: %{
      "seeded" => true,
      "topology_role" => "side_resource",
      "resource_hint" => "rest_supplies"
    }
  })

mirror_bridge =
  ensure_topology_node.(6, %{
    slug: "mirror-bridge",
    name: "Мост отражений",
    kind: :room,
    x: 1,
    y: 1,
    threat_level: 42,
    metadata: %{
      "seeded" => true,
      "topology_role" => "alternate_passage",
      "route_note" => "Опасный проход в обход центральных залов"
    }
  })

heart_sanctum =
  ensure_topology_node.(7, %{
    slug: "heart-sanctum",
    name: "Святилище под Сердцем",
    kind: :rest,
    x: 1,
    y: 1,
    threat_level: 0,
    metadata: %{
      "seeded" => true,
      "topology_role" => "dead_end_resource",
      "resource_hint" => "rest_supplies"
    }
  })

# Floor 1 begins with a recoverable supply detour. It is a true dead end, so
# expeditions must pay the return journey if they choose the resources.
ensure_link.(node_for.("rest-chamber"), provisioning_nook, %{
  metadata: %{"route_role" => "side_resource", "route_shape" => "dead_end"}
})

# A discovered service stair on floor 2 skips the Resonance Gallery entirely:
# one step instead of the two-step main route through the challenge node.
ensure_link.(node_for.("floor-2-ascent"), node_for.("floor-2-descent"), %{
  travel_cost: 1,
  metadata: %{"route_role" => "shortcut", "route_shape" => "hidden_connection"}
})

# The Ash Gardens offer salvage but no onward passage.
ensure_link.(node_for.("ash-garden"), cinder_cache, %{
  metadata: %{"route_role" => "side_resource", "route_shape" => "dead_end"}
})

# Floors 4 and 6 have alternate through-routes. They form loops with the
# existing main passages instead of forcing every expedition through one room.
ensure_link.(node_for.("floor-4-ascent"), sealed_annex, %{
  metadata: %{"route_role" => "alternate_passage"}
})

ensure_link.(sealed_annex, node_for.("floor-4-descent"), %{
  metadata: %{"route_role" => "alternate_passage"}
})

ensure_link.(node_for.("bell-wells"), quiet_well, %{
  metadata: %{"route_role" => "side_resource", "route_shape" => "dead_end"}
})

ensure_link.(node_for.("floor-6-ascent"), mirror_bridge, %{
  metadata: %{"route_role" => "alternate_passage"}
})

ensure_link.(mirror_bridge, node_for.("floor-6-descent"), %{
  metadata: %{"route_role" => "alternate_passage"}
})

ensure_link.(node_for.("tower-heart"), heart_sanctum, %{
  metadata: %{"route_role" => "side_resource", "route_shape" => "dead_end"}
})
