defmodule MMGOWeb.AcademiaLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academia
  alias MMGO.Academia.Professor
  alias MMGO.Academy
  alias MMGO.Academy.Enrollment
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

    researcher = character_fixture(realm, city, "academia-researcher", "Academia Researcher")
    complete_academia(researcher, realm)

    %{realm: realm, city: city, researcher: researcher}
  end

  test "redirects a visitor without a verified game scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/academy/research")
  end

  test "starts a real scoped research project", %{conn: conn, researcher: researcher} do
    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(view, "#academia-research-form")
    refute has_element?(view, "#academia-course-form")

    view
    |> form("#academia-research-form", %{
      "research" => %{"project_kind" => "spell", "title" => "Real Spell Research"}
    })
    |> render_submit()

    assert %{title: "Real Spell Research", project_kind: :spell} =
             Academia.active_project(researcher.id)

    assert has_element?(view, "#academia-active-project", "Real Spell Research")
  end

  test "a real professor publishes a course that enters the Academy catalog", %{
    conn: conn,
    realm: realm,
    researcher: researcher
  } do
    %Professor{}
    |> Professor.changeset(%{
      character_id: researcher.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")
    assert has_element?(view, "#academia-course-form")

    view
    |> form("#academia-course-form", %{
      "course" => %{
        "title" => "Professor's Fire Theory",
        "summary" => "A real course publication.",
        "track" => "wizardry",
        "school" => "fire"
      }
    })
    |> render_submit()

    assert Academy.list_courses_for_realm(realm.id)
           |> Enum.any?(&(&1.title == "Professor's Fire Theory" and &1.source == :published))

    assert has_element?(view, "#academia-publications")
  end

  test "an active professor can retire into the emeritus screen", %{
    conn: conn,
    realm: realm,
    researcher: researcher
  } do
    %Professor{}
    |> Professor.changeset(%{
      character_id: researcher.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(view, "#academia-retire-professor")

    view |> element("#academia-retire-professor") |> render_click()

    assert has_element?(view, "#academia-emeritus")
    assert has_element?(view, "#academia-recommendations")
    refute has_element?(view, "#academia-course-publication")
    refute has_element?(view, "#academia-retire-professor")
  end

  test "active professors elect an Academy Head through the scoped research screen", %{
    conn: conn,
    realm: realm,
    city: city,
    researcher: researcher
  } do
    mentor = character_fixture(realm, city, "headship-mentor", "Headship Mentor")

    for professor <- [researcher, mentor] do
      %Professor{}
      |> Professor.changeset(%{
        character_id: professor.id,
        realm_id: realm.id,
        status: :active,
        appointed_at: DateTime.utc_now(),
        metadata: %{}
      })
      |> Repo.insert!()
    end

    {:ok, researcher_view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(researcher_view, "#academia-headship")
    assert has_element?(researcher_view, "#academia-open-head-election")

    researcher_view |> element("#academia-open-head-election") |> render_click()

    assert has_element?(researcher_view, "#academia-head-election")
    assert has_element?(researcher_view, "#academia-vote-head-#{researcher.id}")

    researcher_view
    |> element("#academia-vote-head-#{researcher.id}")
    |> render_click()

    {:ok, mentor_view, _html} =
      live(session_conn(build_conn(), mentor), ~p"/academy/research")

    mentor_view
    |> element("#academia-vote-head-#{researcher.id}")
    |> render_click()

    assert has_element?(mentor_view, "#academia-head", researcher.name)

    probationer = character_fixture(realm, city, "headship-probationer", "Headship Probationer")

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: probationer.id,
      realm_id: realm.id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :none,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{"outcome_tier" => "probation"}
    })
    |> Repo.insert!()

    {:ok, head_view, _html} =
      live(session_conn(build_conn(), researcher), ~p"/academy/research")

    assert has_element?(head_view, "#academia-head-probation-admissions")
    assert has_element?(head_view, "#academia-head-admit-#{probationer.id}")

    head_view
    |> element("#academia-head-admit-#{probationer.id}")
    |> render_click()

    admission_enrollment =
      Repo.get_by!(Enrollment,
        character_id: probationer.id,
        program_type: :basic_education,
        status: :completed
      )

    admission = Map.fetch!(admission_enrollment.metadata, "academy_head_admission")

    assert admission["head_character_id"] == researcher.id
  end

  test "the elected Head awards a charity stipend through the scoped research screen", %{
    conn: conn,
    realm: realm,
    city: city,
    researcher: researcher
  } do
    mentor = character_fixture(realm, city, "stipend-mentor", "Stipend Mentor")
    student = character_fixture(realm, city, "grant-student", "Grant Student")

    for professor <- [researcher, mentor] do
      %Professor{}
      |> Professor.changeset(%{
        character_id: professor.id,
        realm_id: realm.id,
        status: :active,
        appointed_at: DateTime.utc_now(),
        metadata: %{}
      })
      |> Repo.insert!()
    end

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: student.id,
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry,
      status: :active,
      funding_type: :grant,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.add(DateTime.utc_now(), 10_000, :second),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, treasury} = Economy.ensure_treasury_account(realm, 100)
    {:ok, charity} = Economy.ensure_charity_fund_account(realm)
    assert {:ok, _funding} = Economy.transfer(treasury, charity, 40)

    {:ok, head_view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")
    head_view |> element("#academia-open-head-election") |> render_click()
    head_view |> element("#academia-vote-head-#{researcher.id}") |> render_click()

    {:ok, mentor_view, _html} =
      live(session_conn(build_conn(), mentor), ~p"/academy/research")

    mentor_view |> element("#academia-vote-head-#{researcher.id}") |> render_click()
    head_view |> element("#academia-refresh") |> render_click()

    assert has_element?(head_view, "#academia-head-charity-stipends")
    assert has_element?(head_view, "#academia-charity-stipend-form")

    head_view
    |> form("#academia-charity-stipend-form", %{
      "charity_stipend" => %{"candidate_id" => student.id, "amount" => "25"}
    })
    |> render_submit()

    updated_enrollment =
      Repo.get_by!(Enrollment,
        character_id: student.id,
        program_type: :academy_core,
        status: :active
      )

    assert %{"amount" => 25, "head_character_id" => head_character_id} =
             Academy.charity_stipend(updated_enrollment)

    assert head_character_id == researcher.id
    assert Economy.get_account!(charity.id).current_balance == 15
    assert has_element?(head_view, "#academia-charity-stipends-empty")
  end

  test "the elected Head reschedules and restores a seeded course through the research screen", %{
    conn: conn,
    realm: realm,
    city: city,
    researcher: researcher
  } do
    mentor = character_fixture(realm, city, "curriculum-mentor", "Curriculum Mentor")

    for professor <- [researcher, mentor] do
      %Professor{}
      |> Professor.changeset(%{
        character_id: professor.id,
        realm_id: realm.id,
        status: :active,
        appointed_at: DateTime.utc_now(),
        metadata: %{}
      })
      |> Repo.insert!()
    end

    assert Enum.all?(Academy.seed_courses_for_realm(realm.id), &match?({:ok, _course}, &1))

    economic_basics =
      Academy.list_courses_for_realm(realm.id)
      |> Enum.find(&(&1.title == "Основы экономики"))

    economic_basics =
      economic_basics
      |> Ecto.Changeset.change(title: "Economic Basics")
      |> Repo.update!()

    {:ok, head_view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")
    head_view |> element("#academia-open-head-election") |> render_click()
    head_view |> element("#academia-vote-head-#{researcher.id}") |> render_click()

    {:ok, mentor_view, _html} =
      live(session_conn(build_conn(), mentor), ~p"/academy/research")

    mentor_view |> element("#academia-vote-head-#{researcher.id}") |> render_click()
    head_view |> element("#academia-refresh") |> render_click()

    assert has_element?(head_view, "#academia-head-curriculum")
    assert has_element?(head_view, "#academia-head-curriculum-form")
    assert has_element?(head_view, "#academia-head-curriculum-courses", "Основы экономики")
    refute has_element?(head_view, "#academia-head-curriculum-courses", "Economic Basics")
    assert has_element?(head_view, "#academia-head-curriculum-form option", "Основы экономики")

    head_view
    |> form("#academia-head-curriculum-form", %{
      "curriculum" => %{"course_id" => economic_basics.id, "term_number" => "1"}
    })
    |> render_submit()

    assert has_element?(head_view, "#academia-curriculum-override-#{economic_basics.id}")

    basic = %Enrollment{realm_id: realm.id, program_type: :basic_education}

    assert Enum.any?(Academy.list_courses_for_term(basic, 1), &(&1.id == economic_basics.id))
    refute Enum.any?(Academy.list_courses_for_term(basic, 3), &(&1.id == economic_basics.id))

    head_view
    |> element("#academia-reset-curriculum-#{economic_basics.id}")
    |> render_click()

    refute has_element?(head_view, "#academia-curriculum-override-#{economic_basics.id}")
    refute Enum.any?(Academy.list_courses_for_term(basic, 1), &(&1.id == economic_basics.id))
    assert Enum.any?(Academy.list_courses_for_term(basic, 3), &(&1.id == economic_basics.id))
  end

  test "chooses an actual same-realm professor as the scoped research advisor", %{
    conn: conn,
    realm: realm,
    researcher: researcher
  } do
    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "mentor-city",
        name: "Mentor City",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    mentor = character_fixture(realm, city, "academia-mentor", "Academia Mentor")

    %Professor{}
    |> Professor.changeset(%{
      character_id: mentor.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    complete_honors_academy_core(researcher, realm)

    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(view, "#academia-choose-advisor-#{mentor.id}")

    view |> element("#academia-choose-advisor-#{mentor.id}") |> render_click()

    assert %{professor_character_id: professor_character_id} =
             Academia.active_advisor_for_student(researcher.id)

    assert professor_character_id == mentor.id
    assert has_element?(view, "#academia-current-advisor", mentor.name)
    assert has_element?(view, "#academia-advisor-bonus")
  end

  test "matches a standard Academia student to an available professor", %{
    conn: conn,
    realm: realm,
    city: city,
    researcher: researcher
  } do
    mentor = character_fixture(realm, city, "academia-matched-mentor", "Matched Mentor")

    %Professor{}
    |> Professor.changeset(%{
      character_id: mentor.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(view, "#academia-advisor-match")
    assert has_element?(view, "#academia-match-advisor")
    refute has_element?(view, "#academia-choose-advisor-#{mentor.id}")

    view |> element("#academia-match-advisor") |> render_click()

    assert %{professor_character_id: professor_character_id, metadata: metadata} =
             Academia.active_advisor_for_student(researcher.id)

    assert professor_character_id == mentor.id
    assert metadata["assignment"] == "availability_match"
    assert has_element?(view, "#academia-current-advisor", mentor.name)
  end

  test "an active professor can issue a sealed probation-admission recommendation", %{
    conn: conn,
    realm: realm,
    city: city,
    researcher: researcher
  } do
    %Professor{}
    |> Professor.changeset(%{
      character_id: researcher.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()

    candidate = character_fixture(realm, city, "probation-candidate", "Probation Candidate")

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: candidate.id,
      realm_id: realm.id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :none,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{"outcome_tier" => "probation"}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(session_conn(conn, researcher), ~p"/academy/research")

    assert has_element?(view, "#academia-recommendations")
    assert has_element?(view, "#academia-write-recommendation-#{candidate.id}")

    view
    |> element("#academia-write-recommendation-#{candidate.id}")
    |> render_click()

    enrollment =
      Repo.get_by!(Enrollment,
        character_id: candidate.id,
        program_type: :basic_education,
        status: :completed
      )

    assert enrollment.metadata["professor_recommendation"]["professor_character_id"] ==
             researcher.id

    refute has_element?(view, "#academia-write-recommendation-#{candidate.id}")
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

  defp complete_honors_academy_core(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry,
      status: :completed,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{"honors" => true, "cohort_rank" => 1, "cohort_size" => 10}
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
