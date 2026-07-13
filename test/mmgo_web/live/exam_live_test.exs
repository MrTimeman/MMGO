defmodule MMGOWeb.ExamLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
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

    student = character_fixture(realm, city, "exam-student", "Exam Student", :new)
    term = academy_term_ready_for_midterm(student)

    %{realm: realm, city: city, student: student, term: term}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn, term: term} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/academy/exam/#{term.id}")
  end

  test "submits a server-scored midterm and final for the scoped term", %{
    conn: conn,
    student: student,
    term: term
  } do
    {:ok, midterm_view, _html} =
      live(session_conn(conn, student), ~p"/academy/exam/#{term.id}")

    assert has_element?(midterm_view, "#academy-exam-screen", "Мидтерм")
    assert has_element?(midterm_view, "#academy-exam-lecture-ceiling", "100")
    assert has_element?(midterm_view, "#academy-exam-form", "инкантации")

    midterm_view
    |> form("#academy-exam-form", %{"exam" => correct_answers()})
    |> render_submit()

    assert has_element?(midterm_view, "#academy-exam-result")
    assert Academy.term_progress(Repo.get!(MMGO.Academy.Term, term.id)).phase == :final

    {:ok, final_view, _html} =
      live(session_conn(build_conn(), student), ~p"/academy/exam/#{term.id}")

    assert has_element?(final_view, "#academy-exam-screen", "Финал")

    final_view
    |> form("#academy-exam-form", %{"exam" => correct_answers()})
    |> render_submit()

    completed_term = Repo.get!(MMGO.Academy.Term, term.id)
    assert completed_term.status == :completed
    assert completed_term.exam_score == 100
    assert has_element?(final_view, "#academy-exam-result")
  end

  test "reconnecting to an exam resumes its persisted server deadline", %{
    conn: conn,
    student: student,
    term: term
  } do
    {:ok, first_view, _html} =
      live(session_conn(conn, student), ~p"/academy/exam/#{term.id}")

    assert has_element?(first_view, "#academy-exam-timer")
    first_attempt = Repo.get!(MMGO.Academy.Term, term.id).metadata["exam_attempt"]

    {:ok, second_view, _html} =
      live(session_conn(build_conn(), student), ~p"/academy/exam/#{term.id}")

    assert has_element?(second_view, "#academy-exam-timer")

    resumed_attempt = Repo.get!(MMGO.Academy.Term, term.id).metadata["exam_attempt"]
    assert resumed_attempt["id"] == first_attempt["id"]
    assert resumed_attempt["deadline_at"] == first_attempt["deadline_at"]
  end

  test "a basic-education student can skip the optional midterm", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    student = character_fixture(realm, city, "basic-exam-student", "Basic Exam Student", :active)
    term = basic_term_ready_for_midterm(student)

    {:ok, view, _html} = live(session_conn(conn, student), ~p"/academy/exam/#{term.id}")

    assert has_element?(view, "#academy-skip-midterm")
    view |> element("#academy-skip-midterm") |> render_click()
    assert_redirect(view, ~p"/academy/exam/#{term.id}")

    {:ok, final_view, _html} =
      live(session_conn(build_conn(), student), ~p"/academy/exam/#{term.id}")

    assert has_element?(final_view, "#academy-exam-screen", "Финал")
  end

  defp academy_term_ready_for_midterm(character) do
    {:ok, %{enrollment: basic}} = Academy.begin_basic_education(character, duration_game_days: 1)
    {:ok, _basic_complete} = Academy.complete_enrollment_by_id(basic.id, force: true)

    {:ok, %{enrollment: core}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    {:ok, term} = Academy.begin_term(core.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    {:ok, midterm_term} = Academy.close_club_window(character.id, term.id)
    midterm_term
  end

  defp basic_term_ready_for_midterm(character) do
    {:ok, %{enrollment: enrollment}} = Academy.begin_basic_education(character)
    {:ok, term} = Academy.begin_term(enrollment.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    {:ok, midterm_term} = Academy.close_club_window(character.id, term.id)
    midterm_term
  end

  defp correct_answers do
    %{"q1" => "b", "q2" => "a", "q3" => "c", "q4" => "b", "q5" => "d", "q6" => "a"}
  end

  defp character_fixture(realm, location, handle, name, status) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: status, level: 1, xp: 0})
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
