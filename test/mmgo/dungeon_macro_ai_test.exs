defmodule MMGO.DungeonMacroAiTest do
  use MMGO.DataCase, async: true

  alias MMGO.AI.Request
  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Repo
  alias MMGO.Worlds

  defmodule ScriptedDungeonTickProvider do
    @behaviour MMGO.AI.Provider

    def compile_spell(_prompt_payload, _opts), do: {:error, :unused}
    def narrate_turn(_prompt_payload, _opts), do: {:error, :unused}
    def orchestrate_combat(_prompt_payload, _opts), do: {:error, :unused}

    def tick_dungeon(prompt_payload, _opts) do
      floor_id =
        prompt_payload
        |> Map.fetch!(:user_prompt)
        |> Jason.decode!()
        |> get_in(["floors", Access.at(0), "id"])

      {:ok,
       %{
         "floor_directives" => [
           %{
             "floor_id" => floor_id,
             "threat_delta" => 4,
             "resource_delta" => -2,
             "connection_shift" => "block",
             "anomaly_tag" => "volatile"
           }
         ],
         "summary" => "pressure spike on the upper floor"
       }}
    end
  end

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

  test "maintain_dungeon_by_id/2 applies scripted dungeon tick directives", %{
    dungeon: dungeon,
    room: room,
    link_a: link_a
  } do
    assert {:ok, %{state: state}} =
             Dungeons.maintain_dungeon_by_id(
               dungeon.id,
               now: ~U[2026-03-28 12:00:00Z],
               provider: ScriptedDungeonTickProvider
             )

    assert state.metadata["ai_tick"]["mode"] == "ai"
    [directive] = state.metadata["ai_tick"]["floor_directives"]
    assert directive["anomaly_tag"] == "volatile"
    assert directive["connection_shift"] == "block"
    assert directive["resource_delta"] == -2
    assert directive["threat_delta"] == 4

    node_override = Repo.get_by!(Dungeons.NodeOverride, dungeon_id: dungeon.id, node_id: room.id)
    assert node_override.threat_bias == 6
    assert node_override.anomaly_tag == "volatile"

    link_state = Repo.get_by!(Dungeons.LinkState, dungeon_id: dungeon.id, link_id: link_a.id)
    assert link_state.status == :blocked

    assert Repo.aggregate(Request, :count, :id) == 1
    assert Repo.one!(Request).kind == :dungeon_tick
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
