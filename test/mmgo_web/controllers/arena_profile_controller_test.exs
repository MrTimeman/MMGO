defmodule MMGOWeb.ArenaProfileControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.{Arena, Grimoires}
  alias MMGO.Accounts.{Account, Character, CharacterProfiles}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "arena-profile-web", name: "Арена", is_default: true})

    {:ok, _tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "Башня",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Создатель", handle: "arena-profile-web"})
      |> Repo.insert!()

    world_character =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{name: "Мировой маг", status: :active})
      |> Repo.insert!()

    %{account: account, world_character: world_character}
  end

  test "creates an isolated Arena profile with three schools and selects it", %{
    conn: conn,
    account: account,
    world_character: world_character
  } do
    conn =
      post(account_session(conn, account, world_character), ~p"/arena/profiles", %{
        "arena_profile" => %{
          "name" => "Ткач Гроз",
          "schools" => ["fire", "water", "death"]
        }
      })

    assert redirected_to(conn) == ~p"/arena"
    assert get_session(conn, :game_mode) == "arena"

    profile = Arena.get_profile_for_account(account)
    assert profile.schools == [:fire, :water, :death]
    assert get_session(conn, :current_character_id) == profile.character_id
    assert CharacterProfiles.arena?(profile.character)
    assert world_character.id != profile.character_id

    assert %{capacity: 45, weight: 0, status: :active} =
             Grimoires.active_grimoire_for_character(profile.character_id)
  end

  test "rejects duplicate schools without creating a profile", %{
    conn: conn,
    account: account,
    world_character: world_character
  } do
    conn =
      post(account_session(conn, account, world_character), ~p"/arena/profiles", %{
        "arena_profile" => %{
          "name" => "Повтор",
          "schools" => ["fire", "fire", "water"]
        }
      })

    assert redirected_to(conn) == ~p"/arena/new"
    assert Arena.get_profile_for_account(account) == nil
    assert get_session(conn, :game_mode) == nil
  end

  defp account_session(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
