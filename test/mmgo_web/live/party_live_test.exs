defmodule MMGOWeb.PartyLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    leader = character_fixture(realm, city, "party-leader", "Party Leader")
    member = character_fixture(realm, city, "party-member", "Party Member")

    %{leader: leader, member: member}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/party")
  end

  test "creates, invites, accepts, coordinates readiness, and starts a real expedition", %{
    conn: conn,
    leader: leader,
    member: member
  } do
    {:ok, member_view, _html} = live(session_conn(conn, member), ~p"/party")
    assert has_element?(member_view, "#party-create-form")

    {:ok, leader_view, _html} = live(session_conn(conn, leader), ~p"/party")
    assert has_element?(leader_view, "#party-create-form")

    leader_view
    |> form("#party-create-form", %{"party_create" => %{"name" => "Night Delvers"}})
    |> render_submit()

    assert has_element?(leader_view, "#party-active")

    leader_view
    |> form("#party-invite-form", %{"party_invite" => %{"character_id" => member.id}})
    |> render_submit()

    [invitation] = Parties.pending_invitations_for_character(member.id)
    assert has_element?(member_view, "#party-invitation-#{invitation.id}")

    member_view
    |> element("#party-accept-#{invitation.id}")
    |> render_click()

    assert has_element?(member_view, "#party-active")
    assert has_element?(leader_view, "#party-member-#{member.id}")
    party = Parties.active_party_for_character(member.id)

    leader_view |> element("#party-mark-unready") |> render_click()
    leader_view |> element("#party-start-expedition") |> render_click()
    assert has_element?(leader_view, "#party-error")

    leader_view |> element("#party-mark-ready") |> render_click()

    assert {:error, {:live_redirect, %{to: "/dungeon"}}} =
             leader_view |> element("#party-start-expedition") |> render_click()

    assert Parties.active_expedition_for_party(party.id)
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 5, xp: 0})
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
