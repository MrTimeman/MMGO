defmodule MMGO.DungeonContentTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Dungeons.Encounter
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Parties.Reward
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury_account} = Economy.ensure_treasury_account(realm, 10_000)

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 260,
        safe_zone: false
      })

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon",
        name: "Tower Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor_one} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})

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

    {:ok, _link} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance_node.id,
        to_node_id: rest_node.id,
        travel_cost: 1,
        bidirectional: true
      })

    {:ok, herb_template} =
      Inventory.create_item_template(%{
        code: "dungeon_herb",
        name: "Dungeon Herb",
        item_type: :tool,
        stackable: true,
        weight: 1,
        max_durability: 0,
        actions: [
          %{
            key: "use",
            action_kind: :repair,
            targeting: :self,
            effects: [
              %{
                applies_to: :caster,
                state: "regenerating",
                intensity: 1,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      })

    character = character_fixture(realm, tower, "delver", "Delver")
    outsider = character_fixture(realm, tower, "outsider", "Outsider")
    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    %{
      realm: realm,
      tower: tower,
      dungeon: dungeon,
      entrance_node: entrance_node,
      rest_node: rest_node,
      herb_template: herb_template,
      character: character,
      outsider: outsider,
      expedition: expedition,
      run: run
    }
  end

  test "entering and moving a run materializes encounter and resource state", %{
    run: run,
    entrance_node: entrance_node,
    rest_node: rest_node
  } do
    entrance_encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)
    assert entrance_encounter.status == :pending

    assert {:ok, %{content: content}} = Dungeons.move_run(run, rest_node.id)
    assert content.resource_cache.status == :available
    assert content.resource_cache.resource_code == "rest_supplies"
  end

  test "resolve_encounter/3 creates default currency loot and updates node state", %{
    run: run,
    entrance_node: entrance_node,
    character: character,
    expedition: expedition
  } do
    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)

    assert {:ok,
            %{
              encounter: resolved_encounter,
              loot_drops: [loot_drop],
              node_state: node_state,
              xp_rewards: xp_rewards
            }} =
             Dungeons.resolve_encounter(encounter, :cleared)

    assert resolved_encounter.status == :cleared
    assert loot_drop.reward_kind == :currency
    assert node_state.encounter_status == :cleared
    assert Enum.map(xp_rewards, & &1.character_id) == [character.id]

    assert Enum.map(Parties.list_rewards_for_expedition(expedition.id), & &1.id) ==
             Enum.map(xp_rewards, & &1.id)
  end

  test "resolve_encounter/3 distributes XP shares to all active expedition members", %{
    realm: realm,
    tower: tower,
    dungeon: dungeon,
    entrance_node: entrance_node
  } do
    leader = character_fixture(realm, tower, "leader-two", "Leader Two")
    supporter = character_fixture(realm, tower, "supporter", "Supporter")
    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Second Delvers"})
    {:ok, %{membership: _membership}} = Parties.add_member(party, supporter)
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)
    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)

    assert {:ok, %{xp_rewards: xp_rewards}} = Dungeons.resolve_encounter(encounter, :cleared)

    assert length(xp_rewards) == 2
    assert Enum.sort(Enum.map(xp_rewards, & &1.amount)) == [15, 15]

    reward_codes = Enum.map(xp_rewards, & &1.reward_code)
    assert Enum.uniq(reward_codes) == reward_codes
    assert Repo.aggregate(Reward, :count, :id) == 2
  end

  test "claim_loot/3 transfers currency from the treasury to an eligible expedition member", %{
    realm: realm,
    run: run,
    entrance_node: entrance_node,
    character: character
  } do
    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)
    {:ok, %{loot_drops: [loot_drop]}} = Dungeons.resolve_encounter(encounter, :cleared)

    assert {:ok, %{loot_drop: updated_loot_drop}} = Dungeons.claim_loot(loot_drop, character)

    assert updated_loot_drop.status == :claimed
    assert updated_loot_drop.claimed_by_character_id == character.id

    {:ok, character_account} = Economy.ensure_character_account(character)
    assert Economy.get_account!(character_account.id).current_balance == loot_drop.amount
    assert balance_sum(realm.id) == 10_000
  end

  test "claim_loot/3 rejects characters outside the expedition", %{
    run: run,
    entrance_node: entrance_node,
    outsider: outsider
  } do
    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)
    {:ok, %{loot_drops: [loot_drop]}} = Dungeons.resolve_encounter(encounter, :cleared)

    assert {:error, changeset} = Dungeons.claim_loot(loot_drop, outsider)

    assert %{status: ["character must belong to the expedition that earned this loot"]} =
             errors_on(changeset)
  end

  test "resolve_encounter/3 can create item loot that is granted through inventory", %{
    run: run,
    entrance_node: entrance_node,
    character: character,
    herb_template: herb_template
  } do
    encounter = Repo.get_by!(Encounter, run_id: run.id, node_id: entrance_node.id)

    {:ok, %{loot_drops: [loot_drop]}} =
      Dungeons.resolve_encounter(encounter, :cleared, %{
        loot_drops: [
          %{reward_kind: :item_template, amount: 2, item_template_id: herb_template.id}
        ]
      })

    assert {:ok, %{loot_drop: updated_loot_drop}} = Dungeons.claim_loot(loot_drop, character)
    assert updated_loot_drop.status == :claimed

    inventory_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: herb_template.id
      )

    assert inventory_item.quantity == 2
  end

  test "harvest_resource/4 depletes the cache and grants items when linked to an item template",
       %{run: run, rest_node: rest_node, character: character, herb_template: herb_template} do
    {:ok, %{content: %{resource_cache: rest_cache}}} =
      Dungeons.move_run(run, rest_node.id,
        resource: %{
          resource_code: "herbs",
          quantity_total: 3,
          quantity_remaining: 3,
          item_template_id: herb_template.id
        }
      )

    assert {:ok, %{resource_cache: updated_cache}} =
             Dungeons.harvest_resource(rest_cache, character, 2)

    assert updated_cache.quantity_remaining == 1
    assert updated_cache.status == :available

    inventory_item =
      Repo.get_by!(Inventory.InventoryItem,
        character_id: character.id,
        item_template_id: herb_template.id
      )

    assert inventory_item.quantity == 2

    assert {:ok, %{resource_cache: depleted_cache}} =
             Dungeons.harvest_resource(updated_cache, character, 1)

    assert depleted_cache.quantity_remaining == 0
    assert depleted_cache.status == :depleted
  end

  test "end_run/3 grants completion XP shares", %{run: run, expedition: expedition} do
    assert {:ok, %{run: finished_run, xp_rewards: xp_rewards}} = Dungeons.end_run(run, :completed)

    assert finished_run.status == :completed
    assert length(xp_rewards) == 1
    assert hd(xp_rewards).source_type == :run

    assert Parties.list_rewards_for_expedition(expedition.id)
           |> Enum.any?(&(&1.source_type == :run))
  end

  defp balance_sum(realm_id) do
    Economy.list_accounts_for_realm(realm_id)
    |> Enum.reduce(0, fn account, acc -> acc + account.current_balance end)
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
