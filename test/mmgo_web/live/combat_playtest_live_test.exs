defmodule MMGOWeb.CombatPlaytestLiveTest do
  use MMGOWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Economy
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Worlds

  setup %{conn: conn} do
    previous = Application.get_env(:mmgo, MMGO.CombatPlaytest)
    Application.put_env(:mmgo, MMGO.CombatPlaytest, unrestricted?: true)

    on_exit(fn ->
      if previous do
        Application.put_env(:mmgo, MMGO.CombatPlaytest, previous)
      else
        Application.delete_env(:mmgo, MMGO.CombatPlaytest)
      end
    end)

    {:ok, realm} =
      Worlds.create_realm(%{slug: "playtest-live", name: "Playtest Live", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 0)

    {:ok, first_city} =
      Worlds.create_location(realm, %{
        slug: "playtest-live-first",
        name: "First City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    {:ok, second_city} =
      Worlds.create_location(realm, %{
        slug: "playtest-live-second",
        name: "Second City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    challenger = character_fixture(realm, first_city, "live-caster", "Live Caster")
    opponent = character_fixture(realm, second_city, "live-rival", "Live Rival")

    %{conn: conn, challenger: challenger, opponent: opponent}
  end

  test "the duel lobby exposes a realm-wide zero-stake training challenge", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, view, _html} = live(session_conn(conn, challenger), ~p"/pvp")

    refute has_element?(view, "#duel-safe-zone")
    assert has_element?(view, "#beta-open-spellbook")
    assert has_element?(view, "#beta-open-duels")
    assert has_element?(view, "#duel-challenge-form")
    assert has_element?(view, "#duel-challenge-form option[value=\"#{opponent.id}\"]")
    assert has_element?(view, "#duel-challenge-form input[type=hidden][value=\"0\"]")

    view
    |> form("#duel-challenge-form", %{
      "duel_challenge" => %{"opponent_id" => opponent.id, "stake" => "0"}
    })
    |> render_submit()

    [duel] = PVP.pending_duels_for_character(challenger.id)
    assert duel.opponent_character_id == opponent.id
    assert duel.stake_amount == 0
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 1})
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
