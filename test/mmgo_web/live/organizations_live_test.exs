defmodule MMGOWeb.OrganizationsLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, _city} =
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

    {:ok, %{challenger: challenger, opponent: opponent}} = Play.setup_demo_session()

    %{realm: realm, challenger: challenger, opponent: opponent, the_tower: the_tower}
  end

  defp session_conn(conn, character_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:demo_character_id, character_id)
  end

  test "unauthenticated visitors are redirected to /play/continue", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play/continue"}}} = live(conn, ~p"/orgs")
  end

  test "a character at the Tower (not a city) is redirected to the map with an in-world flash", %{
    conn: conn,
    challenger: challenger,
    the_tower: the_tower
  } do
    challenger
    |> Character.travel_changeset(%{current_location_id: the_tower.id})
    |> Repo.update!()

    conn = session_conn(conn, challenger.id)

    assert {:error, {:live_redirect, %{to: "/map", flash: flash}}} = live(conn, ~p"/orgs")
    assert flash["error"] =~ "You need to be in a city"
  end

  test "a character in a city (the demo starting location) mounts normally", %{
    conn: conn,
    challenger: challenger
  } do
    conn = session_conn(conn, challenger.id)

    {:ok, _view, html} = live(conn, ~p"/orgs")

    assert html =~ "Organizations"
  end

  test "index renders after a demo session with the create form", %{
    conn: conn,
    challenger: challenger
  } do
    conn = session_conn(conn, challenger.id)

    {:ok, view, html} = live(conn, ~p"/orgs")

    assert html =~ "Organizations"
    assert has_element?(view, "#org-create-form")
    assert has_element?(view, "#org-invitations")
  end

  test "founding an organization shows it in the list", %{conn: conn, challenger: challenger} do
    conn = session_conn(conn, challenger.id)
    {:ok, view, _html} = live(conn, ~p"/orgs")

    view
    |> form("#org-create-form form", %{
      "organization" => %{"name" => "Order of the Ember", "kind" => "guild"}
    })
    |> render_submit()

    assert has_element?(view, "#org-list", "Order of the Ember")
    assert has_element?(view, "#org-list", "guild")
  end

  test "detail page shows members and roles", %{conn: conn, challenger: challenger} do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    conn = session_conn(conn, challenger.id)
    {:ok, view, html} = live(conn, ~p"/orgs/#{organization.id}")

    assert html =~ "Silver Hand"
    assert has_element?(view, "#org-members", challenger.name)
    assert has_element?(view, "#org-roles", "Guildmaster")
  end

  test "non-members are redirected away from a detail page", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    conn = session_conn(conn, opponent.id)

    assert {:error, {:live_redirect, %{to: "/orgs"}}} = live(conn, ~p"/orgs/#{organization.id}")
  end

  test "invite flow: founder invites another character, invitee sees and accepts it", %{
    conn: conn,
    challenger: challenger,
    opponent: opponent
  } do
    {:ok, %{organization: organization}} =
      Organizations.create_organization(challenger, :guild, "Silver Hand")

    opponent_account = Accounts.get_account!(opponent.account_id)

    founder_conn = session_conn(conn, challenger.id)
    {:ok, founder_view, _html} = live(founder_conn, ~p"/orgs/#{organization.id}")

    founder_view
    |> form("#org-invite-form form", %{
      "invite" => %{
        "handle" => opponent_account.handle,
        "role_id" => hd(organization.roles).id
      }
    })
    |> render_submit()

    invitee_conn = session_conn(build_conn(), opponent.id)
    {:ok, invitee_view, html} = live(invitee_conn, ~p"/orgs")

    assert html =~ "Silver Hand"
    assert has_element?(invitee_view, "#org-invitations", "Silver Hand")

    invitation =
      Organizations.pending_invitations_for_character(opponent.id) |> List.first()

    invitee_view
    |> element(
      "button[phx-click='accept_invitation'][phx-value-invitation_id='#{invitation.id}']"
    )
    |> render_click()

    assert has_element?(invitee_view, "#org-list", "Silver Hand")

    reloaded = Organizations.get_organization!(organization.id)

    assert Enum.any?(
             reloaded.memberships,
             &(&1.character_id == opponent.id and &1.status == :active)
           )
  end
end
