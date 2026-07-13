defmodule MMGOWeb.ClubEventLiveTest do
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

    member = character_fixture(realm, city, "event-member", "Event Member")
    spectator = character_fixture(realm, city, "event-spectator", "Event Spectator")

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    enroll(member, realm)
    enroll(spectator, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, member, 100)

    {:ok, %{club: club}} =
      Clubs.create_club(member, %{name: "Protocol Circle", club_type: :general_interest})

    {:ok, event} = Clubs.create_event(club, %{kind: :general_meeting})

    %{member: member, spectator: spectator, club: club, event: event}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn, event: event} do
    assert {:error, {:live_redirect, %{to: "/play"}}} =
             live(conn, ~p"/academy/club-events/#{event.id}")
  end

  test "a scoped club member sees and claims the persisted attendance reward", %{
    conn: conn,
    member: member,
    event: event
  } do
    starting_xp = member.xp

    {:ok, view, _html} = live(session_conn(conn, member), ~p"/academy/club-events/#{event.id}")

    assert has_element?(view, "#club-event-screen")
    assert has_element?(view, "#club-event-attend")

    view |> element("#club-event-attend") |> render_click()

    assert has_element?(view, "#club-event-attended")
    assert has_element?(view, "#club-event-xp")
    assert Repo.get!(Character, member.id).xp == starting_xp + 5
  end

  test "a realm-local spectator can inspect an event but cannot forge attendance", %{
    conn: conn,
    spectator: spectator,
    event: event
  } do
    {:ok, view, _html} =
      live(session_conn(conn, spectator), ~p"/academy/club-events/#{event.id}")

    assert has_element?(view, "#club-event-membership-required")
    refute has_element?(view, "#club-event-attend")
  end

  test "a research session displays its durable shared-note consequence", %{
    conn: conn,
    member: member
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(member, %{name: "Research Protocol", club_type: :research})

    {:ok, event} = Clubs.create_event(club, %{kind: :research_session})

    {:ok, view, _html} =
      live(session_conn(conn, member), ~p"/academy/club-events/#{event.id}")

    view |> element("#club-event-attend") |> render_click()

    assert has_element?(view, "#club-event-research-note")
  end

  test "an expedition briefing displays its durable route-note consequence", %{
    conn: conn,
    member: member
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(member, %{name: "Route Protocol", club_type: :expedition_planning})

    {:ok, event} = Clubs.create_event(club, %{kind: :expedition_briefing})

    {:ok, view, _html} =
      live(session_conn(conn, member), ~p"/academy/club-events/#{event.id}")

    view |> element("#club-event-attend") |> render_click()

    assert has_element?(view, "#club-event-expedition-plan")
  end

  test "a later general-meeting attendee sees the social tie it created", %{
    conn: conn,
    member: member,
    spectator: spectator,
    club: club,
    event: event
  } do
    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, member, spectator)
    assert {:ok, _accepted} = Clubs.accept_invitation(invitation, spectator)
    assert {:ok, _attendance} = Clubs.attend_event(event, member)

    {:ok, view, _html} =
      live(session_conn(conn, spectator), ~p"/academy/club-events/#{event.id}")

    view |> element("#club-event-attend") |> render_click()

    assert has_element?(view, "#club-event-social-ties")
  end

  test "duelling attendees exchange consent-based invitations before a no-wager combat starts", %{
    conn: conn,
    member: member,
    spectator: spectator
  } do
    {:ok, %{club: club}} =
      Clubs.create_club(member, %{name: "Dawn Duelists", club_type: :dueling})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, member, spectator)
    assert {:ok, _accepted} = Clubs.accept_invitation(invitation, spectator)
    {:ok, event} = Clubs.create_event(club, %{kind: :duel_tournament})
    assert {:ok, _attendance} = Clubs.attend_event(event, member)
    assert {:ok, _attendance} = Clubs.attend_event(event, spectator)

    {:ok, challenger_view, _html} =
      live(session_conn(conn, member), ~p"/academy/club-events/#{event.id}")

    assert has_element?(challenger_view, "#club-event-challenge-duel-#{spectator.id}")

    challenger_view
    |> element("#club-event-challenge-duel-#{spectator.id}")
    |> render_click()

    {:ok, opponent_view, _html} =
      live(session_conn(conn, spectator), ~p"/academy/club-events/#{event.id}")

    [challenge] = Clubs.list_duel_challenges(Clubs.get_event!(event.id))
    assert has_element?(opponent_view, "#club-event-accept-duel-#{challenge["id"]}")

    assert {:error, {:live_redirect, %{to: combat_path}}} =
             opponent_view
             |> element("#club-event-accept-duel-#{challenge["id"]}")
             |> render_click()

    assert String.starts_with?(combat_path, "/combat/")
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
