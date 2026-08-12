defmodule MMGOWeb.ArenaCharacterLiveTest do
  use MMGOWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "arena-forge", name: "Кузня Арены", is_default: true})

    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Заклинатель", handle: "arena-caster"})
      |> Repo.insert!()

    character =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{name: "Мировой профиль", status: :active})
      |> Repo.insert!()

    %{account: account, character: character}
  end

  test "offers all schools and enables creation only for three distinct choices", %{
    conn: conn,
    account: account,
    character: character
  } do
    {:ok, view, _html} = live(account_session(conn, account, character), ~p"/arena/new")

    assert has_element?(view, "#arena-character-form[action='/arena/profiles']")
    assert has_element?(view, "#arena-character-name")

    for school <- ~w(fire water earth air life death chaos order) do
      assert has_element?(view, "#arena-school-#{school} input[value='#{school}']")
    end

    assert has_element?(view, "#create-arena-character[disabled]")

    view
    |> form("#arena-character-form", %{
      "arena_profile" => %{
        "name" => "Триада",
        "schools" => ["fire", "water", "death"]
      }
    })
    |> render_change()

    assert has_element?(view, "#arena-school-fire.arena-school--selected")
    assert has_element?(view, "#arena-school-water.arena-school--selected")
    assert has_element?(view, "#arena-school-death.arena-school--selected")
    refute has_element?(view, "#create-arena-character[disabled]")
  end

  defp account_session(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end
end
