defmodule MMGOWeb.GameModeControllerTest do
  use MMGOWeb.ConnCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Accounts
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "mode-controller", name: "Рубеж", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Город",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Путник", handle: "mode-controller"})
      |> Repo.insert!()

    character =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{name: "Путник", status: :new})
      |> Repo.insert!()

    %{account: account, character: character, city: city}
  end

  test "selecting the world activates its character and records the session mode", %{
    conn: conn,
    account: account,
    character: character,
    city: city
  } do
    conn = post(account_session(conn, account, character), ~p"/mode/world")

    assert redirected_to(conn) == ~p"/map"
    assert get_session(conn, :game_mode) == "world"
    assert get_session(conn, :current_character_id) == character.id
    assert Repo.reload!(character).status == :active
    assert Repo.reload!(character).current_location_id == city.id
    assert Accounts.get_default_world_character_for_account(account.id).id == character.id
  end

  test "world mode selects the persisted default rather than the browser's old character", %{
    conn: conn,
    account: account,
    character: character
  } do
    {:ok, second_realm} =
      Worlds.create_realm(%{slug: "mode-controller-second", name: "Второй рубеж"})

    {:ok, _second_treasury} = Economy.ensure_treasury_account(second_realm, 100_000)

    {:ok, _second_city} =
      Worlds.create_location(second_realm, %{
        slug: "capital-city",
        name: "Второй город",
        kind: :city,
        x: 30,
        y: 30,
        safe_zone: true
      })

    second =
      %Character{account_id: account.id, realm_id: second_realm.id}
      |> Character.changeset(%{name: "Избранный", status: :new})
      |> Repo.insert!()

    assert {:ok, _second} = Accounts.set_default_world_character(account.id, second.id)

    conn = post(account_session(conn, account, character), ~p"/mode/world")

    assert redirected_to(conn) == ~p"/characters"
    assert get_session(conn, :current_character_id) == second.id
  end

  test "selecting Arena without a profile sends the player to its forge", %{
    conn: conn,
    account: account,
    character: character
  } do
    conn = post(account_session(conn, account, character), ~p"/mode/arena")

    assert redirected_to(conn) == ~p"/arena/new"
    assert get_session(conn, :game_mode) == nil
  end

  defp account_session(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
