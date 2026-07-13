defmodule MMGOWeb.LectureLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "lecture-realm", name: "Lecture Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "lecture-city",
        name: "Lecture City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    student = character_fixture(realm, city)
    term = academy_term_ready_for_lecture(student)

    %{student: student, term: term}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn, term: term} do
    assert {:error, {:live_redirect, %{to: "/play"}}} =
             live(conn, ~p"/academy/lecture/#{term.id}")
  end

  test "submits a real lecture comprehension check for the scoped term", %{
    conn: conn,
    student: student,
    term: term
  } do
    {:ok, view, _html} = live(session_conn(conn, student), ~p"/academy/lecture/#{term.id}")

    assert has_element?(view, "#academy-lecture-screen")
    assert has_element?(view, "#academy-lecture-progress", "Лекция 1 из 3")
    assert has_element?(view, "#academy-lecture-form")

    view
    |> form("#academy-lecture-form", %{"lecture" => %{"q1" => "a", "q2" => "a"}})
    |> render_submit()

    assert has_element?(view, "#academy-lecture-result", "2 / 2")

    progress = Academy.term_progress(Repo.get!(MMGO.Academy.Term, term.id))
    assert progress.lectures_attended == 1
    assert progress.lecture_final_ceiling == 80
  end

  defp academy_term_ready_for_lecture(character) do
    {:ok, %{enrollment: basic}} = Academy.begin_basic_education(character, duration_game_days: 1)
    {:ok, _basic_complete} = Academy.complete_enrollment_by_id(basic.id, force: true)

    {:ok, %{enrollment: core}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    {:ok, term} = Academy.begin_term(core.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)
    term
  end

  defp character_fixture(realm, location) do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Lecture Student",
        handle: "lecture-student"
      })
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: "Lecture Student", status: :new, level: 1, xp: 0})
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
