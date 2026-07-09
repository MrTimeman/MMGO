defmodule MMGOWeb.SpellbookLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, capital_city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    {:ok, the_tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 100,
        y: 100,
        safe_zone: false
      })

    character = character_fixture(realm, capital_city, "spellcaster", "Spellcaster")

    %{realm: realm, capital_city: capital_city, the_tower: the_tower, character: character}
  end

  defp session_conn(conn, character_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:demo_character_id, character_id)
  end

  test "unauthenticated visitors are redirected to /play/continue", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play/continue"}}} = live(conn, ~p"/spellbook")
  end

  test "a character in the capital city is redirected to the map with an in-world flash", %{
    conn: conn,
    character: character
  } do
    conn = session_conn(conn, character.id)

    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} = live(conn, ~p"/spellbook")
    assert flash["error"] =~ "Magic only works at the Tower"
  end

  test "a character at the Tower can access the spellbook", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    move_to(character, the_tower)
    conn = session_conn(conn, character.id)

    {:ok, _view, html} = live(conn, ~p"/spellbook")

    # The spellbook renders in-world (Russian) once the caster is at the Tower.
    assert html =~ "Создание заклинания"
  end

  defp move_to(character, location) do
    character
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
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
