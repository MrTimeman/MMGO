defmodule MMGOWeb.ClubsLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy.Enrollment
  alias MMGO.Clubs
  alias MMGO.Economy
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

    founder = character_fixture(realm, city, "club-founder", "Club Founder")
    invitee = character_fixture(realm, city, "club-invitee", "Club Invitee")

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    enroll(founder, realm)
    enroll(invitee, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, founder, 100)

    %{realm: realm, founder: founder, invitee: invitee}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/academy/clubs")
  end

  test "creates a real club, invites a realm-local member, and schedules an event", %{
    conn: conn,
    founder: founder,
    invitee: invitee
  } do
    {:ok, index_view, _html} = live(session_conn(conn, founder), ~p"/academy/clubs")
    assert has_element?(index_view, "#club-create-form")

    index_view
    |> form("#club-create-form", %{
      "club_create" => %{"name" => "Real Delvers", "club_type" => "expedition_planning"}
    })
    |> render_submit()

    [club] = Clubs.list_clubs_for_character(founder.id)
    assert has_element?(index_view, "#club-card-#{club.id}")

    {:ok, manage_view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}/manage")

    assert has_element?(manage_view, "#club-invite-form")

    manage_view
    |> form("#club-invite-form", %{"club_invite" => %{"handle" => "club-invitee"}})
    |> render_submit()

    [invitation] = Clubs.pending_invitations_for_character(invitee.id)

    {:ok, invitee_view, _html} = live(session_conn(conn, invitee), ~p"/academy/clubs")

    assert {:error, {:live_redirect, %{to: club_path}}} =
             invitee_view |> element("#club-accept-#{invitation.id}") |> render_click()

    assert club_path == "/academy/clubs/#{club.id}"
    assert Clubs.list_clubs_for_character(invitee.id) |> Enum.any?(&(&1.id == club.id))

    manage_view
    |> form("#club-event-form", %{"club_event" => %{"kind" => "expedition_briefing"}})
    |> render_submit()

    [event] = Clubs.list_events_for_club(club.id)
    assert event.kind == :expedition_briefing
  end

  test "an ordinary member is redirected away from leader controls", %{
    conn: conn,
    founder: founder,
    invitee: invitee
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{name: "Leaders Only", club_type: :general_interest})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    {:ok, _accepted} = Clubs.accept_invitation(invitation, invitee)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(session_conn(conn, invitee), ~p"/academy/clubs/#{club.id}/manage")

    assert to == "/academy/clubs/#{club.id}"
  end

  test "club governance appoints an officer and elects a new president through the UI", %{
    conn: conn,
    founder: founder,
    invitee: invitee
  } do
    assert {:ok, %{club: club}} =
             Clubs.create_club(founder, %{name: "Civic Circle", club_type: :general_interest})

    assert {:ok, %{invitation: invitation}} = Clubs.invite_member(club, founder, invitee)
    assert {:ok, _membership} = Clubs.accept_invitation(invitation, invitee)

    {:ok, founder_view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}")

    assert has_element?(founder_view, "#club-governance")
    assert has_element?(founder_view, "#club-president")
    assert has_element?(founder_view, "#club-nominate-#{invitee.id}")

    {:ok, president_manage_view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}/manage")

    president_manage_view
    |> element("#club-appoint-officer-#{invitee.id}")
    |> render_click()

    assert Repo.get_by!(MMGO.Clubs.Membership, club_id: club.id, character_id: invitee.id).role ==
             :officer

    {:ok, officer_manage_view, _html} =
      live(session_conn(conn, invitee), ~p"/academy/clubs/#{club.id}/manage")

    assert has_element?(officer_manage_view, "#club-invite-form")
    assert has_element?(officer_manage_view, "#club-event-form")
    refute has_element?(officer_manage_view, "#club-officer-controls")

    founder_view
    |> element("#club-nominate-#{invitee.id}")
    |> render_click()

    assert has_element?(founder_view, "#club-open-election")

    founder_view
    |> element("#club-election-approve")
    |> render_click()

    {:ok, voting_view, _html} =
      live(session_conn(conn, invitee), ~p"/academy/clubs/#{club.id}")

    voting_view
    |> element("#club-election-approve")
    |> render_click()

    elected_club = Clubs.get_club!(club.id)
    elected_president = Enum.find(elected_club.memberships, &(&1.role == :leader))
    assert elected_president.character_id == invitee.id
  end

  test "shows the durable seasonal ladder for a duelling club", %{
    conn: conn,
    founder: founder
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{name: "Dawn Duelists", club_type: :dueling})

    {:ok, view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}")

    assert has_element?(view, "#club-duel-ladder")
    assert has_element?(view, "#club-duel-ladder-entry-#{founder.id}")
  end

  test "shows unredeemed shared-notes credit for a research club member", %{
    conn: conn,
    founder: founder
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{name: "Shared Notes", club_type: :research})

    {:ok, view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}")

    assert has_element?(view, "#club-research-contribution")
    assert has_element?(view, "#club-research-note-credits")
  end

  test "shows briefing credits for an expedition-planning club member", %{
    conn: conn,
    founder: founder
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{name: "Route Scouts", club_type: :expedition_planning})

    {:ok, view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}")

    assert has_element?(view, "#club-expedition-plan")
    assert has_element?(view, "#club-expedition-plan-credits")
  end

  test "shows a general-interest member's durable social connection count", %{
    conn: conn,
    founder: founder
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(founder, %{name: "Lore Circle", club_type: :general_interest})

    {:ok, view, _html} =
      live(session_conn(conn, founder), ~p"/academy/clubs/#{club.id}")

    assert has_element?(view, "#club-social-connections")
    assert has_element?(view, "#club-social-companions")
  end

  defp enroll(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry,
      status: :active,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
      metadata: %{}
    })
    |> Repo.insert!()
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
