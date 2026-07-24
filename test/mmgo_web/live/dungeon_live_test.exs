defmodule MMGOWeb.DungeonLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Parties
  alias MMGO.Parties.Expedition
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    {:ok, dungeon} =
      Dungeons.create_dungeon(realm, %{
        slug: "tower-dungeon",
        name: "Tower Dungeon",
        status: :active,
        entrance_location_id: tower.id
      })

    {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Upper Halls"})

    {:ok, entrance} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Entrance Hall",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 0
      })

    {:ok, rest} =
      Dungeons.create_node(floor, %{
        slug: "rest",
        name: "Rest Chamber",
        kind: :rest,
        x: 1,
        y: 0,
        threat_level: 0
      })

    {:ok, danger} =
      Dungeons.create_node(floor, %{
        slug: "danger",
        name: "Fang Gallery",
        kind: :room,
        x: 0,
        y: 1,
        threat_level: 5
      })

    for target <- [rest, danger] do
      {:ok, _link} =
        Dungeons.create_link(dungeon, %{
          from_node_id: entrance.id,
          to_node_id: target.id,
          travel_cost: 1,
          bidirectional: true
        })
    end

    leader = character_fixture(realm, tower, "dungeon-leader", "Dungeon Leader")
    {:ok, %{party: party}} = Parties.create_party(leader, %{name: "Tower Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)

    %{
      leader: leader,
      party: party,
      expedition: expedition,
      entrance: entrance,
      rest: rest,
      danger: danger
    }
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/dungeon")
  end

  test "shows the party's loot agreement without implying an enforced claim rule", %{
    conn: conn,
    leader: leader,
    party: party
  } do
    assert {:ok, _party} = Parties.set_loot_policy(party, leader, "leader")

    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")

    assert has_element?(view, "#dungeon-loot-policy")
    assert has_element?(view, "#dungeon-loot-policy-value", "Решает лидер")
    assert has_element?(view, "#dungeon-loot-policy-note")
  end

  test "renders the persisted expedition survival ledger instead of live inventory", %{
    conn: conn,
    leader: leader,
    expedition: expedition
  } do
    expedition =
      expedition
      |> Expedition.changeset(%{
        food_units_snapshot: 6,
        daily_food_demand: 2,
        carried_weight: 18,
        carry_capacity: 12,
        metadata: %{
          "survival" => %{
            "food_units_initial" => 6,
            "food_units_remaining" => 0,
            "food_units_consumed" => 6,
            "foodless_game_days" => 2,
            "shared_hp_drain" => 2,
            "movement_penalty_days" => 2
          }
        }
      })
      |> Repo.update!()

    assert expedition.id

    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")

    assert has_element?(view, "#dungeon-supplies")
    assert has_element?(view, "#dungeon-survival-food", "0")
    assert has_element?(view, "#dungeon-survival-carry", "18 / 12")
    assert has_element?(view, "#dungeon-overloaded")
    assert has_element?(view, "#dungeon-starvation-risk")
  end

  test "enters, moves, harvests, and extracts through the persisted expedition", %{
    conn: conn,
    leader: leader,
    expedition: expedition,
    entrance: entrance,
    rest: rest
  } do
    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")
    assert has_element?(view, "#dungeon-entry")

    view |> element("#dungeon-enter") |> render_click()
    assert has_element?(view, "#dungeon-current-node")
    assert has_element?(view, "#dungeon-node-#{entrance.id}")

    view |> element("#dungeon-move-#{rest.id}") |> render_click()
    run = Dungeons.active_run_for_expedition(expedition.id)

    resource =
      run.id |> Dungeons.list_resource_caches_for_run() |> Enum.find(&(&1.node_id == rest.id))

    assert has_element?(view, "#dungeon-resource-#{resource.id}")
    assert has_element?(view, "#dungeon-scavenging-time", "1 игровой день")

    xp_before = Repo.get!(Character, leader.id).xp

    view |> element("#dungeon-harvest-#{resource.id}") |> render_click()

    assert Dungeons.get_resource_cache!(resource.id).quantity_remaining ==
             resource.quantity_remaining - 1

    assert Dungeons.get_run!(run.id).metadata["scavenging_game_days"] == 1
    assert Repo.get!(Character, leader.id).xp == xp_before + 3

    view |> element("#dungeon-move-#{entrance.id}") |> render_click()
    view |> element("#dungeon-extract") |> render_click()
    assert has_element?(view, "#dungeon-no-expedition")
  end

  test "shows the Return Ritual loadout requirement before exposing the action", %{
    conn: conn,
    leader: leader
  } do
    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")
    view |> element("#dungeon-enter") |> render_click()

    assert has_element?(view, "#dungeon-return-ritual-readiness")
    refute has_element?(view, "#dungeon-return-ritual")
  end

  test "exposes a real pending encounter and lets the party explicitly avoid it", %{
    conn: conn,
    leader: leader,
    expedition: expedition,
    entrance: entrance,
    danger: danger
  } do
    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")
    view |> element("#dungeon-enter") |> render_click()
    view |> element("#dungeon-move-#{danger.id}") |> render_click()

    assert has_element?(view, "#dungeon-encounter")
    assert has_element?(view, "#dungeon-avoid-encounter")

    refute has_element?(view, "#atmosphere-audio")

    view |> element("#dungeon-avoid-encounter") |> render_click()

    run = Dungeons.active_run_for_expedition(expedition.id)
    assert Dungeons.current_encounter_for_run(run.id).status == :avoided
    assert has_element?(view, "#dungeon-move-#{entrance.id}")
  end

  test "shows a persisted club route plan before dungeon entry", %{
    conn: conn,
    leader: leader,
    expedition: expedition
  } do
    expedition
    |> Expedition.changeset(%{
      metadata: %{
        "club_route_plan" => %{
          "status" => "available",
          "xp_bonus_bps" => 1_000
        }
      }
    })
    |> Repo.update!()

    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")

    assert has_element?(view, "#dungeon-route-plan")
    assert has_element?(view, "#dungeon-route-plan-status", "план готов")
  end

  test "starts the current persisted encounter and routes the party to real combat", %{
    conn: conn,
    leader: leader,
    expedition: expedition,
    danger: danger
  } do
    {:ok, view, _html} = live(session_conn(conn, leader), ~p"/dungeon")
    view |> element("#dungeon-enter") |> render_click()
    view |> element("#dungeon-move-#{danger.id}") |> render_click()

    assert {:error, {:live_redirect, %{to: combat_path}}} =
             view |> element("#dungeon-start-combat") |> render_click()

    assert String.starts_with?(combat_path, "/combat/")
    run = Dungeons.active_run_for_expedition(expedition.id)
    assert Dungeons.current_encounter_for_run(run.id).status == :active
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

  defp session_conn(conn, character) do
    account = Repo.get!(Account, character.account_id)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
