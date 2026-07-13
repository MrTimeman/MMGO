defmodule MMGOWeb.DefeatLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Dungeons
  alias MMGO.Inventory
  alias MMGO.Parties
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

    {:ok, _entrance} =
      Dungeons.create_node(floor, %{
        slug: "entrance",
        name: "Entrance Hall",
        kind: :entrance,
        x: 0,
        y: 0,
        threat_level: 0
      })

    character = character_fixture(realm, tower)

    {:ok, template} =
      Inventory.create_item_template(%{
        code: "defeat-live-relic",
        name: "Defeat Live Relic",
        item_type: :ingredient,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 0,
        actions: []
      })

    {:ok, _item} = Inventory.grant_item(character, template, %{quantity: 2})
    {:ok, %{party: party}} = Parties.create_party(character, %{name: "Fallen Delvers"})
    {:ok, %{expedition: expedition}} = Parties.start_expedition(party)
    {:ok, %{run: run}} = Dungeons.enter_dungeon(expedition, dungeon)
    {:ok, %{drops: [drop | _rest]}} = Dungeons.fail_run_with_sacrifice(run)

    %{character: character, drop: drop}
  end

  test "renders the actual sacrifice ledger for the scoped character", %{
    conn: conn,
    character: character,
    drop: drop
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/defeat")

    assert has_element?(view, "#defeat-screen")
    assert has_element?(view, "#defeat-drop-#{drop.id}")
    assert has_element?(view, "#defeat-kept-xp")
    assert has_element?(view, "#defeat-return-location")
  end

  defp character_fixture(realm, location) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Fallen Live", handle: "fallen-live"})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: "Fallen Live", status: :active, level: 10, xp: 0})
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
