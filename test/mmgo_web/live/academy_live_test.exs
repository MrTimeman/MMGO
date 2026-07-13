defmodule MMGOWeb.AcademyLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Academy.{Course, CourseEnrollment, Enrollment, Term}
  alias MMGO.Repo
  alias MMGO.Spells
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

    %{realm: realm, city: city}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/academy")
  end

  test "starts an owned basic education record and an actual term", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "academy-basic", "Academy Basic", :active)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy")

    assert has_element?(view, "#academy-program-form")

    view
    |> form("#academy-program-form", %{
      "academy_program" => %{
        "program_type" => "basic_education",
        "track" => "wizardry",
        "primary_school" => "fire",
        "secondary_school" => "air"
      }
    })
    |> render_submit()

    enrollment = Academy.current_enrollment(character.id)
    assert enrollment.program_type == :basic_education
    assert has_element?(view, "#academy-enrollment")

    view |> element("#academy-begin-term") |> render_click()
    assert Academy.current_term(enrollment.id)
    assert has_element?(view, "#academy-term-list")
    assert has_element?(view, "#academy-term-count")
    assert has_element?(view, "#academy-current-term-window")
    assert has_element?(view, "#academy-cohort-leaderboard")
  end

  test "enrolls the scoped student's current term in a realm-valid course", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "academy-core", "Academy Core", :new)
    complete_basic_education(character)

    {:ok, course} =
      %Course{}
      |> Course.changeset(%{
        realm_id: realm.id,
        source: :seeded,
        title: "Fire Theory",
        track: :wizardry,
        school: :fire,
        syllabus: %{"summary" => "A real scoped course."},
        status: :active,
        metadata: %{}
      })
      |> Repo.insert()

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy/courses")

    view
    |> form("#academy-program-form", %{
      "academy_program" => %{
        "program_type" => "academy_core",
        "track" => "wizardry",
        "primary_school" => "fire",
        "secondary_school" => "air"
      }
    })
    |> render_submit()

    view |> element("#academy-begin-term") |> render_click()
    assert has_element?(view, "#academy-course-#{course.id}")

    view |> element("#academy-enroll-course-#{course.id}") |> render_click()

    assert Repo.get_by!(CourseEnrollment, character_id: character.id, course_id: course.id).status ==
             :enrolled

    assert has_element?(view, "#academy-course-#{course.id}")

    view |> element("#academy-open-lectures") |> render_click()
    assert has_element?(view, "#academy-office-hours-#{course.id}")

    view |> element("#academy-office-hours-#{course.id}") |> render_click()
    assert has_element?(view, "#academy-office-hours-attended-#{course.id}")
  end

  test "advances the scoped term through course selection, lectures, club window, and the midterm",
       %{
         conn: conn,
         realm: realm,
         city: city
       } do
    character = character_fixture(realm, city, "academy-lectures", "Academy Lectures", :new)
    complete_basic_education(character)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy")

    view
    |> form("#academy-program-form", %{
      "academy_program" => %{
        "program_type" => "academy_core",
        "track" => "wizardry",
        "primary_school" => "fire",
        "secondary_school" => "air"
      }
    })
    |> render_submit()

    view |> element("#academy-begin-term") |> render_click()
    assert has_element?(view, "#academy-open-lectures")

    view |> element("#academy-open-lectures") |> render_click()
    assert has_element?(view, "#academy-attend-lecture")
    assert has_element?(view, "#academy-close-lectures")

    view |> element("#academy-attend-lecture") |> render_click()
    term = Academy.current_term(Academy.current_enrollment(character.id).id)
    assert_redirect(view, ~p"/academy/lecture/#{term.id}")

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    {:ok, view, _html} = live(session_conn(build_conn(), character), ~p"/academy")

    assert has_element?(view, "#academy-club-window")
    assert has_element?(view, "#academy-club-window-attendance")
    refute has_element?(view, "#academy-open-exam")

    view |> element("#academy-close-club-window") |> render_click()
    assert has_element?(view, "#academy-open-exam", "Открыть мидтерм")
  end

  test "shows the real starter rewards after academy core graduation", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "academy-graduate", "Academy Graduate", :active)
    complete_basic_education(character)

    {:ok, %{enrollment: academy_core}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    assert {:ok, %{enrollment: completed_enrollment}} =
             Academy.complete_enrollment_by_id(academy_core.id, force: true)

    assert Academy.starter_outcomes(completed_enrollment)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy")

    assert has_element?(view, "#academy-starter-outcomes")
    assert has_element?(view, "#academy-starter-reward-list")
    assert has_element?(view, "#academy-open-starter-rewards")
    assert has_element?(view, "#academy-program-form option[value='academy_core']")

    view
    |> form("#academy-program-form", %{
      "academy_program" => %{
        "program_type" => "academy_core",
        "track" => "wizardry",
        "primary_school" => "fire",
        "secondary_school" => "earth"
      }
    })
    |> render_submit()

    assert has_element?(view, "#academy-retraining-enrollment")
  end

  test "lets a valedictorian claim one chosen spell from the Academy hall", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character = character_fixture(realm, city, "academy-laureate", "Academy Laureate", :active)
    enrollment = valedictorian_enrollment_fixture(character)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy")

    assert has_element?(view, "#academy-valedictorian-titles")
    assert has_element?(view, "#academy-valedictorian-title-#{enrollment.id}")
    assert has_element?(view, "#academy-valedictorian-bonus")
    assert has_element?(view, "#academy-valedictorian-bonus-form")

    view
    |> form("#academy-valedictorian-bonus-form", %{
      "valedictorian_bonus" => %{"school" => "water"}
    })
    |> render_submit()

    refute has_element?(view, "#academy-valedictorian-bonus")
    assert Academy.school_permitted?(character.id, "water")
    assert Enum.any?(Spells.list_spells_for_character(character.id), &(&1.school == :water))
  end

  test "shows Basic Education distinction rewards and title in the Academy hall", %{
    conn: conn,
    realm: realm,
    city: city
  } do
    character =
      character_fixture(realm, city, "academy-distinction", "Academy Distinction", :active)

    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    %Term{}
    |> Term.changeset(%{
      enrollment_id: enrollment.id,
      realm_id: realm.id,
      term_number: 1,
      status: :completed,
      started_at: enrollment.started_at,
      ended_at: enrollment.expected_completion_at,
      exam_score: 95,
      metadata: %{"phase" => "break", "club_events_attended" => 1, "club_events_required" => 1}
    })
    |> Repo.insert!()

    assert {:ok, %{enrollment: completed_enrollment}} =
             Academy.complete_enrollment_by_id(enrollment.id,
               force: true,
               now: enrollment.started_at
             )

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/academy")

    assert has_element?(view, "#academy-starter-outcomes")
    assert has_element?(view, "#academy-starter-title")
    assert has_element?(view, "#academy-academic-titles")
    assert has_element?(view, "#academy-academic-title-#{completed_enrollment.id}")
  end

  defp complete_basic_education(character) do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    assert {:ok, %{enrollment: %Enrollment{status: :completed}}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true)
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

  defp valedictorian_enrollment_fixture(character) do
    completed_at = ~U[2026-07-12 12:00:00Z]

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: character.realm_id,
      program_type: :academy_core,
      track: :alchemy,
      status: :completed,
      started_at: DateTime.add(completed_at, -3600, :second),
      expected_completion_at: completed_at,
      completed_at: completed_at,
      metadata: %{
        "cohort_key" => "academy_core:2026",
        "honors" => true,
        "outcome_tier" => "distinction",
        "valedictorian" => true
      }
    })
    |> Repo.insert!()
  end
end
