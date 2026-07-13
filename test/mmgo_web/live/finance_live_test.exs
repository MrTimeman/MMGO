defmodule MMGOWeb.FinanceLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.NPCShops
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    character = character_fixture(realm, city)
    {:ok, _funds} = Economy.grant_from_treasury(realm, character, 100)

    %{realm: realm, character: character}
  end

  test "shows a scoped ledger and settles charity and tuition through real accounts", %{
    conn: conn,
    realm: realm,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/finance")
    assert has_element?(view, "#finance-balance")

    view
    |> form("#finance-donation-form", %{"donation" => %{"amount" => "25"}})
    |> render_submit()

    {:ok, charity} = NPCShops.ensure_charity_fund_account(realm)
    assert Economy.get_account!(charity.id).current_balance == 25

    view
    |> form("#finance-tuition-form", %{"tuition" => %{"amount" => "10"}})
    |> render_submit()

    {:ok, account} = Economy.ensure_character_account(character)
    assert Economy.get_account!(account.id).current_balance == 65
    assert has_element?(view, "#finance-ledger li")
  end

  defp character_fixture(realm, location) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: "Finance Live", handle: "finance-live"})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: "Finance Live", status: :active, level: 5, xp: 0})
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
