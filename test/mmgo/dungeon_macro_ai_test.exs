defmodule MMGO.DungeonMacroAiTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "tower",
        name: "Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "macro-dungeon",
        name: "Macro Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper"})

    {:ok, entrance} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Entrance",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 5
      })

    {:ok, room} =
      Dungeons.create_node(floor, %{
        slug: "room",
        name: "Room",
        kind: :room,
        x: 1,
        y: 0,
        threat_level: 10
      })

    {:ok, rest} =
      Dungeons.create_node(floor, %{
        slug: "rest",
        name: "Rest",
        kind: :rest,
        x: 2,
        y: 0,
        threat_level: 0
      })

    {:ok, link_a} =
      Dungeons.create_link(dungeon, %{
        from_node_id: entrance.id,
        to_node_id: room.id,
        travel_cost: 1,
        bidirectional: true
      })

    {:ok, _link_b} =
      Dungeons.create_link(dungeon, %{
        from_node_id: room.id,
        to_node_id: rest.id,
        travel_cost: 1,
        bidirectional: true
      })

    character = character_fixture(realm, tower, "macrodelver", "Macro Delver")
    {:ok, %{party: party}} = MMGO.Parties.create_party(character, %{name: "Macro Delvers"})
    {:ok, %{expedition: expedition}} = MMGO.Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)

    %{dungeon: dungeon, run: run, room: room, link_a: link_a}
  end

  test "maintain_dungeon_by_id/2 creates state and node/link overrides", %{dungeon: dungeon} do
    assert {:ok, %{state: state, node_overrides: node_overrides, link_states: link_states}} =
             Dungeons.maintain_dungeon_by_id(dungeon.id)

    assert state.cycle_number == 1
    assert node_overrides != []
    assert link_states != []
  end

  test "maintenance can block links and movement respects blocked state", %{
    dungeon: dungeon,
    run: run,
    room: room,
    link_a: link_a
  } do
    {:ok, _result} = Dungeons.maintain_dungeon_by_id(dungeon.id, now: ~U[2026-03-28 12:00:00Z])

    link_state = Repo.get_by!(Dungeons.LinkState, dungeon_id: dungeon.id, link_id: link_a.id)

    if link_state.status == :blocked do
      assert {:error, changeset} = Dungeons.move_run(run, room.id)

      assert %{status: ["target node path is currently blocked by the dungeon"]} =
               errors_on(changeset)
    else
      assert {:ok, %{run: updated_run}} = Dungeons.move_run(run, room.id)
      assert updated_run.current_node_id == room.id
    end
  end

  test "node overrides influence generated encounter threat", %{
    dungeon: dungeon,
    run: run,
    room: room
  } do
    {:ok, %{node_overrides: _node_overrides}} =
      Dungeons.maintain_dungeon_by_id(dungeon.id, now: ~U[2026-03-28 12:00:00Z])

    assert {:ok, %{run: moved_run}} = Dungeons.move_run(run, room.id)
    encounter = Dungeons.current_encounter_for_run(moved_run.id)
    node_override = Repo.get_by!(Dungeons.NodeOverride, dungeon_id: dungeon.id, node_id: room.id)

    assert encounter.threat_level >= max(room.threat_level + node_override.threat_bias, 1)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
