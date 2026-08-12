defmodule MMGOWeb.GameModeLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "mode-gate", name: "Перекрёсток", is_default: true})

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Ветеран", handle: "mode-veteran"})
      |> Repo.insert!()

    character =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{name: "Мирный маг", status: :active})
      |> Repo.insert!()

    %{account: account, character: character}
  end

  test "renders a first-class choice between the world and Arena", %{
    conn: conn,
    account: account,
    character: character
  } do
    {:ok, view, _html} = live(account_session(conn, account, character), ~p"/mode")

    assert has_element?(view, "#game-mode-screen")
    assert has_element?(view, "#game-mode-world-card")
    assert has_element?(view, "#game-mode-arena-card")
    assert has_element?(view, "#select-world-mode-form[action='/mode/world']")
    assert has_element?(view, "#create-arena-profile[href='/arena/new']")
    refute has_element?(view, "#select-arena-mode-form")
  end

  test "requires an authenticated account before choosing a mode", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/mode")
  end

  defp account_session(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
