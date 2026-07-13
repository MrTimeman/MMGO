defmodule MMGOWeb.ThesisDefenseLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academia
  alias MMGO.Academia.{Professor, Project}
  alias MMGO.Academy.Enrollment
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

    candidate = character_fixture(realm, city, "thesis-candidate", "Thesis Candidate")
    spectator = character_fixture(realm, city, "thesis-spectator", "Thesis Spectator")
    complete_academia(candidate, realm)

    panelists =
      for number <- 1..3 do
        professor =
          character_fixture(
            realm,
            city,
            "thesis-panel-#{number}",
            "Thesis Panel #{number}"
          )

        %Professor{}
        |> Professor.changeset(%{
          character_id: professor.id,
          realm_id: realm.id,
          status: :active,
          appointed_at: DateTime.utc_now(),
          metadata: %{}
        })
        |> Repo.insert!()

        professor
      end

    {:ok, %{project: thesis}} =
      Academia.start_project(candidate, :thesis, "A Real Thesis", duration_game_days: 1)

    {:ok, %{project: completed_thesis}} =
      Academia.complete_project_by_id(thesis.id, force: true)

    project = open_thesis_window(completed_thesis)

    %{candidate: candidate, spectator: spectator, panelists: panelists, project: project}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn, project: project} do
    assert {:error, {:live_redirect, %{to: "/play"}}} =
             live(conn, ~p"/academy/thesis/#{project.id}")
  end

  test "shows the real public protocol but only gives a panelist their own vote controls", %{
    conn: conn,
    candidate: candidate,
    spectator: spectator,
    panelists: [panelist | _rest],
    project: project
  } do
    {:ok, spectator_view, _html} =
      live(session_conn(conn, spectator), ~p"/academy/thesis/#{project.id}")

    assert has_element?(spectator_view, "#thesis-defense-screen")
    assert has_element?(spectator_view, "#thesis-project-id")
    refute has_element?(spectator_view, "#thesis-vote-controls")

    {:ok, candidate_view, _html} =
      live(session_conn(conn, candidate), ~p"/academy/thesis/#{project.id}")

    refute has_element?(candidate_view, "#thesis-vote-controls")

    {:ok, panel_view, _html} =
      live(session_conn(conn, panelist), ~p"/academy/thesis/#{project.id}")

    assert has_element?(panel_view, "#thesis-panel-#{panelist.id}")
    assert has_element?(panel_view, "#thesis-vote-accept")

    panel_view |> element("#thesis-vote-accept") |> render_click()

    assert {:ok, defense} = Academia.thesis_defense(project.id)
    assert defense.votes[panelist.id]["vote"] == "accept"
    refute has_element?(panel_view, "#thesis-vote-controls")
  end

  defp open_thesis_window(project) do
    now = DateTime.utc_now()

    project
    |> Project.changeset(%{
      defense_scheduled_at: DateTime.add(now, -60, :second),
      metadata:
        Map.put(
          project.metadata || %{},
          "defense_closes_at",
          now |> DateTime.add(3_600, :second) |> DateTime.to_iso8601()
        )
    })
    |> Repo.update!()
  end

  defp complete_academia(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academia,
      status: :completed,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
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
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
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
