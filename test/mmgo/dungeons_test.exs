defmodule MMGO.DungeonsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Dungeons.{NodeState, Run}
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Parties.Expedition
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

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "dungeon_test_ration",
        name: "Dungeon Test Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    {:ok, _rations} = Inventory.grant_item(leader, ration_template, %{quantity: 10})

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
      party: party,
      expedition: expedition,
      leader: leader,
      member: member,
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
    entrance_encounter = Dungeons.current_encounter_for_run(run.id)

    assert {:ok, %{encounter: _resolved_encounter}} =
             Dungeons.resolve_encounter(entrance_encounter, :avoided)

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

  test "move_run/3 requires the current encounter to be resolved", %{
    expedition: expedition,
    dungeon: dungeon,
    rest_node: rest_node
  } do
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    assert {:error, changeset} = Dungeons.move_run(run, rest_node.id)
    assert %{status: ["current encounter must be resolved before moving"]} = errors_on(changeset)
  end

  test "movement consumes snapshotted food and turns later starvation into shared HP drain", %{
    expedition: expedition,
    dungeon: dungeon,
    rest_node: rest_node,
    deeper_node: deeper_node
  } do
    expedition =
      expedition
      |> Expedition.changeset(%{
        food_units_snapshot: 2,
        metadata: %{
          "survival" => %{
            "food_units_initial" => 2,
            "food_units_remaining" => 2,
            "food_units_consumed" => 0,
            "foodless_game_days" => 0,
            "shared_hp_drain" => 0,
            "movement_penalty_days" => 0
          }
        }
      })
      |> Repo.update!()

    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)
    entrance_encounter = Dungeons.current_encounter_for_run(run.id)

    assert {:ok, %{encounter: _resolved_encounter}} =
             Dungeons.resolve_encounter(entrance_encounter, :avoided)

    assert {:ok, %{run: rested_run, survival: rested_survival}} =
             Dungeons.move_run(run, rest_node.id)

    assert rested_run.steps_taken == 1
    assert rested_survival.food_units_remaining == 0
    assert rested_survival.food_units_consumed == 2
    assert rested_survival.foodless_game_days == 0

    assert {:ok, %{run: starving_run, expedition: updated_expedition, survival: survival}} =
             Dungeons.move_run(rested_run, deeper_node.id, leave_status: :cleared)

    assert starving_run.steps_taken == 5
    assert survival.food_units_remaining == 0
    assert survival.foodless_game_days == 2
    assert survival.shared_hp_drain == 2

    assert %{
             "food_units_remaining" => 0,
             "food_units_consumed" => 2,
             "foodless_game_days" => 2,
             "shared_hp_drain" => 2,
             "last_movement" => %{
               "food_units_required" => 4,
               "food_shortage_units" => 4,
               "movement_penalty_days" => 2
             }
           } = updated_expedition.metadata["survival"]

    encounter = Dungeons.current_encounter_for_run(starving_run.id)
    assert {:ok, %{combat: combat}} = Dungeons.start_encounter_combat(encounter)
    assert combat.sides["party"]["shared_hp"] == 198
    assert combat.metadata["survival"]["shared_hp_drain"] == 2
  end

  test "overweight expeditions pay the snapshotted carry penalty on every move", %{
    expedition: expedition,
    dungeon: dungeon,
    rest_node: rest_node
  } do
    expedition =
      expedition
      |> Expedition.changeset(%{carried_weight: 81, carry_capacity: 80})
      |> Repo.update!()

    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)
    entrance_encounter = Dungeons.current_encounter_for_run(run.id)

    assert {:ok, %{encounter: _resolved_encounter}} =
             Dungeons.resolve_encounter(entrance_encounter, :avoided)

    assert {:ok, %{run: moved_run, survival: survival}} = Dungeons.move_run(run, rest_node.id)

    assert survival.encumbered?
    assert moved_run.steps_taken == 2
    assert survival.movement_penalty_days == 1
  end

  test "harvesting spends one durable game-day per resource and awards server XP", %{
    expedition: expedition,
    dungeon: dungeon,
    leader: leader,
    member: member
  } do
    assert {:ok, %{run: run, content: %{resource_cache: resource_cache}}} =
             Dungeons.enter_dungeon(expedition, dungeon,
               resource: %{
                 resource_code: "test_scavenged_shard",
                 status: :available,
                 quantity_total: 2,
                 quantity_remaining: 2
               }
             )

    assert {:ok,
            %{
              resource_cache: updated_cache,
              run: updated_run,
              expedition: updated_expedition,
              character: updated_character,
              xp_awarded: 3,
              party_xp_awarded: 6,
              xp_rewards: xp_rewards,
              harvest_game_days: 1,
              survival: survival
            }} = Dungeons.harvest_resource(resource_cache, leader, 1)

    assert updated_cache.status == :available
    assert updated_cache.quantity_remaining == 1
    assert updated_cache.metadata["last_harvest_game_days"] == 1
    assert updated_cache.metadata["last_harvest_xp"] == 6
    assert updated_cache.metadata["last_harvest_xp_per_member"] == 3
    assert updated_run.steps_taken == run.steps_taken
    assert updated_run.metadata["scavenging_game_days"] == 1
    assert updated_character.xp == 3
    assert Enum.map(xp_rewards, & &1.amount) == [3, 3]

    assert MapSet.new(Enum.map(xp_rewards, & &1.character_id)) ==
             MapSet.new([leader.id, member.id])

    assert survival.food_units_consumed == 2
    assert survival.food_units_remaining == 8

    assert %{
             "activity" => "scavenging",
             "game_days" => 1,
             "food_units_required" => 2,
             "food_units_consumed" => 2
           } = updated_expedition.metadata["survival"]["last_activity"]

    assert {:ok,
            %{
              resource_cache: depleted_cache,
              run: depleted_run,
              xp_rewards: next_xp_rewards,
              party_xp_awarded: 6
            }} = Dungeons.harvest_resource(updated_cache, leader, 1)

    assert depleted_cache.status == :depleted
    assert depleted_run.metadata["scavenging_game_days"] == 2
    assert Enum.map(next_xp_rewards, & &1.amount) == [3, 3]

    reward_codes = Enum.map(xp_rewards ++ next_xp_rewards, & &1.reward_code)
    assert Enum.uniq(reward_codes) == reward_codes
    assert Repo.get!(Character, leader.id).xp == 6
    assert Repo.get!(Character, member.id).xp == 6

    assert {:error, changeset} = Dungeons.harvest_resource(depleted_cache, leader, 1)
    assert %{status: ["resource cache is depleted"]} = errors_on(changeset)
    assert Repo.get!(Character, leader.id).xp == 6
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

    assert {:ok, %{run: %Run{} = updated_run, xp_rewards: xp_rewards}} =
             Dungeons.end_run(run, :completed)

    assert updated_run.status == :completed
    assert updated_run.ended_at
    assert xp_rewards != []
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

  test "loot policies are agreements and do not block eligible expedition members", %{
    realm: realm,
    party: party,
    leader: leader,
    member: member,
    expedition: expedition,
    dungeon: dungeon,
    entrance_node: entrance_node
  } do
    assert {:ok, _party} = Parties.set_loot_policy(party, leader, "leader")
    assert {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    encounter = Repo.get_by!(MMGO.Dungeons.Encounter, run_id: run.id, node_id: entrance_node.id)
    assert {:ok, %{loot_drops: [loot_drop]}} = Dungeons.resolve_encounter(encounter, :cleared)

    assert {:ok, _treasury_account} = MMGO.Economy.ensure_treasury_account(realm, 100)

    assert {:ok, %{loot_drop: claimed_loot}} = Dungeons.claim_loot(loot_drop, member)
    assert claimed_loot.claimed_by_character_id == member.id
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
