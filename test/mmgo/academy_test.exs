defmodule MMGO.AcademyTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Academy.{CompleteEnrollmentWorker, Course, Enrollment, Specialization, Term}
  alias MMGO.Alchemy
  alias MMGO.Bases
  alias MMGO.Clubs
  alias MMGO.Economy
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "student", "Student")

    club_founder =
      realm
      |> character_fixture("club-founder", "Club Founder")
      |> Character.changeset(%{status: :active})
      |> Repo.update!()

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 10_000)
    enroll_active_academy_core(club_founder, realm)
    {:ok, _funding} = Economy.grant_from_treasury(realm, club_founder, 1_000)

    %{realm: realm, character: character, club_founder: club_founder}
  end

  test "begin_basic_education/2 creates an active enrollment and schedules completion", %{
    character: character
  } do
    started_at = ~U[2026-03-27 12:00:00Z]

    assert {:ok, %{enrollment: enrollment, job: job}} =
             Academy.begin_basic_education(character, started_at: started_at)

    assert enrollment.program_type == :basic_education
    assert enrollment.status == :active

    assert DateTime.compare(
             enrollment.expected_completion_at,
             AcademyTestHelpers.expected_completion(started_at, 3640)
           ) == :eq

    oban_job = Repo.get!(Oban.Job, job.id)
    assert oban_job.worker == "MMGO.Academy.CompleteEnrollmentWorker"
  end

  test "start_academy_track/3 rejects academy enrollment before basic education is complete", %{
    character: character
  } do
    assert {:error, changeset} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert %{status: ["basic education must be completed first"]} = errors_on(changeset)
  end

  test "start_academy_track/3 validates distinct wizardry schools", %{character: character} do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    {:ok, _result} = Academy.complete_enrollment_by_id(enrollment.id, force: true)

    assert {:error, changeset} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :fire
             })

    assert %{status: ["wizardry schools must be distinct"]} = errors_on(changeset)
  end

  test "wizardry rejects opposite schools in enrollment and the specialization schema", %{
    realm: realm,
    character: character
  } do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    {:ok, _result} = Academy.complete_enrollment_by_id(enrollment.id, force: true)

    assert {:error, changeset} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :water
             })

    assert %{status: ["wizardry schools are opposed and cannot be combined"]} =
             errors_on(changeset)

    specialization_changeset =
      %Specialization{}
      |> Specialization.changeset(%{
        character_id: character.id,
        realm_id: realm.id,
        track: :wizardry,
        status: :active,
        started_at: DateTime.utc_now(),
        primary_school: :chaos,
        secondary_school: :order
      })

    assert %{
             secondary_school: [
               "is incompatible with the primary school's opposite on the elemental compass"
             ]
           } =
             errors_on(specialization_changeset)

    assert Spells.opposed_schools?(:earth, :air)
    assert Spells.opposed_schools?(:life, :death)
    refute Spells.opposed_schools?(:fire, :air)
  end

  test "completing academy core wizardry grants XP and creates an active specialization", %{
    character: character
  } do
    {:ok, %{enrollment: basic_enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    {:ok, %{character: basic_graduate}} =
      Academy.complete_enrollment_by_id(basic_enrollment.id, force: true)

    assert basic_graduate.status == :active

    {:ok, %{enrollment: academy_enrollment}} =
      Academy.start_academy_track(
        character,
        :wizardry,
        %{
          primary_school: :fire,
          secondary_school: :air
        },
        duration_game_days: 1
      )

    assert {:ok, %{character: graduated_character, specialization: specialization}} =
             Academy.complete_enrollment_by_id(academy_enrollment.id, force: true)

    assert graduated_character.xp == 350
    assert specialization.track == :wizardry
    assert specialization.primary_school == :fire
    assert specialization.secondary_school == :air
    assert Academy.school_permitted?(character.id, "fire")
    refute Academy.school_permitted?(character.id, "water")
  end

  test "academy core wizardry graduation creates three starter spells in an academy grimoire", %{
    character: character
  } do
    complete_basic_education(character)

    {:ok, %{enrollment: enrollment}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    record_academy_terms(enrollment, [92, 94, 90])

    assert {:ok, %{enrollment: completed_enrollment, character: graduate}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true)

    outcomes = Academy.starter_outcomes(completed_enrollment)
    assert outcomes["track"] == "wizardry"
    assert outcomes["quality"] == "refined"
    assert length(outcomes["rewards"]) == 3

    spells = Spells.list_spells_for_character(graduate.id)
    assert length(spells) == 3
    assert Enum.all?(spells, &("starter" in &1.tags))
    assert Enum.map(spells, & &1.school) |> Enum.sort() == [:air, :fire, :fire]

    grimoire =
      graduate.id
      |> Grimoires.list_grimoires_for_character()
      |> Enum.find(&(Map.get(&1.metadata, "source_enrollment_id") == enrollment.id))

    assert grimoire

    assert Enum.map(grimoire.entries, & &1.spell_id) |> Enum.sort() ==
             Enum.map(spells, & &1.id) |> Enum.sort()
  end

  test "basic education distinction grants an honors title and two real bonus spells", %{
    character: character
  } do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    record_academy_term(enrollment, 1, :completed, 95)

    assert {:ok,
            %{
              enrollment: completed_enrollment,
              character: graduate,
              starter_outcomes: starter_outcomes
            }} =
             Academy.complete_enrollment_by_id(enrollment.id,
               force: true,
               now: enrollment.started_at
             )

    assert completed_enrollment.metadata["outcome_tier"] == "distinction"
    assert completed_enrollment.metadata["academic_title"] == "Академские почести"
    assert starter_outcomes["track"] == "basic_education"
    assert starter_outcomes["quality"] == "honors"
    assert starter_outcomes["title"] == "Академские почести"
    assert length(starter_outcomes["rewards"]) == 2

    spells = Spells.list_spells_for_character(graduate.id)
    assert length(spells) == 2
    assert Enum.all?(spells, &("basic_education" in &1.tags))
    assert Enum.map(spells, & &1.school) |> Enum.sort() == [:air, :fire]

    grimoire =
      graduate.id
      |> Grimoires.list_grimoires_for_character()
      |> Enum.find(&(Map.get(&1.metadata, "source_enrollment_id") == enrollment.id))

    assert grimoire.name == "Academy Honors Grimoire"

    assert Enum.map(grimoire.entries, & &1.spell_id) |> Enum.sort() ==
             Enum.map(spells, & &1.id) |> Enum.sort()

    assert [title_enrollment] = Academy.list_academic_titles(character.id)
    assert title_enrollment.id == completed_enrollment.id
  end

  test "academy core alchemy graduation unlocks three durable recipes and starter materials", %{
    realm: realm,
    character: character
  } do
    complete_basic_education(character)

    {:ok, %{enrollment: enrollment}} = Academy.start_academy_track(character, :alchemy)
    record_academy_terms(enrollment, [78, 80, 76])

    assert {:ok, %{enrollment: completed_enrollment, character: graduate}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true)

    outcomes = Academy.starter_outcomes(completed_enrollment)
    assert outcomes["track"] == "alchemy"
    assert outcomes["quality"] == "standard"
    assert length(outcomes["rewards"]) == 3

    recipes =
      graduate
      |> Alchemy.list_recipes_for_character()
      |> Enum.filter(&(Map.get(&1.metadata, "academy_starter_track") == "alchemy"))

    assert Enum.map(recipes, & &1.code) |> Enum.sort() ==
             Enum.map(outcomes["rewards"], & &1["code"]) |> Enum.sort()

    reagent =
      graduate.id
      |> Inventory.list_inventory_for_character()
      |> Enum.find(&(Map.get(&1.item_template.metadata, "academy_starter_track") == "alchemy"))

    assert reagent.quantity == 5

    other = character_fixture(realm, "recipe-observer", "Recipe Observer")
    refute Alchemy.recipe_available_to_character?(other, hd(recipes))

    {:ok, laboratory} =
      Worlds.create_location(realm, %{
        slug: "academy-laboratory",
        name: "Academy Laboratory",
        kind: :city,
        x: 20,
        y: 20,
        safe_zone: true
      })

    graduate =
      graduate
      |> Character.travel_changeset(%{current_location_id: laboratory.id})
      |> Repo.update!()

    fund_base_acquisition!(realm, graduate)
    assert {:ok, _base} = Bases.purchase_city_base(graduate, laboratory)

    {:ok, workshop} =
      Alchemy.create_workshop(graduate, %{
        name: "Graduate Laboratory",
        location_id: laboratory.id,
        installed_tool_codes: []
      })

    recipe = hd(recipes)

    assert {:ok, %{brew_job: brew_job}} =
             Alchemy.brew(graduate, workshop, recipe, 1, started_at: ~U[2026-07-12 12:00:00Z])

    assert {:ok, %{item_result: item_result}} =
             Alchemy.complete_brew_job_by_id(brew_job.id, force: true)

    assert item_result.item_template_id == recipe.result_item_template.id
  end

  test "academy core mastery graduation grants three usable starter tools", %{
    character: character
  } do
    complete_basic_education(character)

    {:ok, %{enrollment: enrollment}} = Academy.start_academy_track(character, :mastery)
    record_academy_terms(enrollment, [66, 68, 64])

    assert {:ok, %{enrollment: completed_enrollment, character: graduate}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true)

    outcomes = Academy.starter_outcomes(completed_enrollment)
    assert outcomes["track"] == "mastery"
    assert outcomes["quality"] == "standard"
    assert length(outcomes["rewards"]) == 3

    starter_tools =
      graduate.id
      |> Inventory.list_inventory_for_character()
      |> Enum.filter(&(Map.get(&1.item_template.metadata, "academy_starter_track") == "mastery"))

    assert length(starter_tools) == 3
    assert Enum.all?(starter_tools, &(&1.item_template.actions != []))
    assert Enum.all?(starter_tools, &(&1.quantity == 1))
  end

  test "Academy Core retraining keeps the old specialization until a new one graduates", %{
    character: character
  } do
    complete_basic_education(character)

    {:ok, %{enrollment: first_enrollment}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    assert {:ok, %{specialization: first_specialization}} =
             Academy.complete_enrollment_by_id(first_enrollment.id, force: true)

    assert Academy.active_specialization(character.id).id == first_specialization.id

    assert {:error, changeset} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert %{status: ["wizardry retraining may overlap with at most one prior school"]} =
             errors_on(changeset)

    assert {:error, opposed_changeset} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :water
             })

    assert %{status: ["wizardry schools are opposed and cannot be combined"]} =
             errors_on(opposed_changeset)

    assert {:ok, %{enrollment: retraining_enrollment}} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :earth
             })

    assert retraining_enrollment.metadata["retraining_from_specialization_id"] ==
             first_specialization.id

    assert Academy.active_specialization(character.id).id == first_specialization.id

    assert {:ok, %{specialization: new_specialization}} =
             Academy.complete_enrollment_by_id(retraining_enrollment.id, force: true)

    retired_specialization = Repo.get!(Specialization, first_specialization.id)

    assert retired_specialization.status == :retired
    assert retired_specialization.ended_at
    assert retired_specialization.metadata["retired_by_enrollment_id"] == retraining_enrollment.id
    assert new_specialization.track == :wizardry
    assert new_specialization.primary_school == :fire
    assert new_specialization.secondary_school == :earth
    assert Academy.active_specialization(character.id).id == new_specialization.id
    assert Academy.school_permitted?(character.id, "earth")
    refute Academy.school_permitted?(character.id, "air")
  end

  test "Academy Core does not grant a specialization until the third-term capstone passes", %{
    character: character
  } do
    complete_basic_education(character)

    {:ok, %{enrollment: failed_core}} =
      Academy.start_academy_track(
        character,
        :wizardry,
        %{primary_school: :fire, secondary_school: :air},
        duration_game_days: 1
      )

    record_academy_term(failed_core, 1, :completed, 90)
    record_academy_term(failed_core, 2, :completed, 90)
    record_academy_term(failed_core, 3, :failed, nil)

    assert {:ok,
            %{
              enrollment: failed_enrollment,
              character: failed_character,
              specialization: nil,
              starter_outcomes: nil
            }} =
             Academy.complete_enrollment_by_id(failed_core.id,
               now: failed_core.expected_completion_at,
               force: true
             )

    assert failed_enrollment.status == :failed
    assert failed_enrollment.metadata["outcome_tier"] == "capstone_incomplete"
    refute failed_enrollment.metadata["capstone_passed"]
    assert failed_character.xp == 100
    assert is_nil(Academy.active_specialization(character.id))
    assert Spells.list_spells_for_character(character.id) == []

    {:ok, %{enrollment: retried_core}} =
      Academy.start_academy_track(
        character,
        :wizardry,
        %{primary_school: :fire, secondary_school: :air},
        duration_game_days: 1
      )

    record_academy_terms(retried_core, [70, 72, 74])

    assert {:ok, %{enrollment: passed_enrollment, specialization: specialization}} =
             Academy.complete_enrollment_by_id(retried_core.id,
               now: retried_core.expected_completion_at,
               force: true
             )

    assert passed_enrollment.status == :completed
    assert passed_enrollment.metadata["capstone_passed"]
    assert specialization.track == :wizardry
  end

  test "complete enrollment worker finalizes due enrollments", %{character: character} do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    assert :ok =
             CompleteEnrollmentWorker.perform(%Oban.Job{
               args: %{"enrollment_id" => enrollment.id}
             })

    updated_enrollment = Repo.get!(Enrollment, enrollment.id)
    assert updated_enrollment.status == :completed
  end

  test "start_extended_study/2 requires academy core completion", %{character: character} do
    {:ok, %{enrollment: basic_enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    {:ok, _result} = Academy.complete_enrollment_by_id(basic_enrollment.id, force: true)

    assert {:error, changeset} = Academy.start_extended_study(character)
    assert %{status: ["academy core study must be completed first"]} = errors_on(changeset)
  end

  test "course enrollment rejects a foreign term and a foreign-realm course", %{
    realm: realm,
    character: character
  } do
    other = character_fixture(realm, "other-student", "Other Student")
    term = academy_core_term(character)
    other_term = academy_core_term(other)
    local_course = course_fixture(realm, "local-course")

    assert {:error, changeset} =
             Academy.enroll_in_course(character.id, other_term.id, local_course.id)

    assert %{status: ["term does not belong to this character"]} = errors_on(changeset)

    {:ok, foreign_realm} =
      Worlds.create_realm(%{slug: "foreign", name: "Foreign Realm", is_default: false})

    foreign_course = course_fixture(foreign_realm, "foreign-course")

    assert {:error, changeset} =
             Academy.enroll_in_course(character.id, term.id, foreign_course.id)

    assert %{status: ["course and term must belong to the same realm"]} = errors_on(changeset)
  end

  test "seeding a realm course catalog is idempotent", %{realm: realm} do
    assert seeded = Academy.seed_courses_for_realm(realm.id)
    assert Enum.all?(seeded, &match?({:ok, _course}, &1))

    course_count = length(Academy.list_courses_for_realm(realm.id))
    assert course_count > 0

    assert repeated_seeded = Academy.seed_courses_for_realm(realm.id)
    assert Enum.all?(repeated_seeded, &match?({:ok, _course}, &1))
    assert length(Academy.list_courses_for_realm(realm.id)) == course_count
  end

  test "the catalog and enrollment only offer curriculum scheduled for the active term", %{
    realm: realm,
    character: character
  } do
    assert Enum.all?(Academy.seed_courses_for_realm(realm.id), &match?({:ok, _course}, &1))

    {:ok, %{enrollment: basic}} = Academy.begin_basic_education(character)
    {:ok, term} = Academy.begin_term(basic.id)

    first_year_courses = Academy.list_courses_for_term(basic, term.term_number)

    assert Enum.any?(first_year_courses, &(&1.title == "Elemental Literacy"))
    refute Enum.any?(first_year_courses, &(&1.title == "Economic Basics"))
    refute Enum.any?(first_year_courses, &(&1.title == "Incantation Construction I"))

    economic_basics =
      Academy.list_courses_for_realm(realm.id)
      |> Enum.find(&(&1.title == "Economic Basics"))

    assert {:error, changeset} =
             Academy.enroll_in_course(character.id, term.id, economic_basics.id)

    assert %{status: ["course is not offered in this term"]} = errors_on(changeset)

    core = %Enrollment{realm_id: realm.id, program_type: :academy_core, track: :wizardry}
    core_courses = Academy.list_courses_for_term(core, 1)

    assert Enum.any?(core_courses, &(&1.title == "Incantation Construction I"))
    refute Enum.any?(core_courses, &(&1.title == "Incantation Construction II"))
    refute Enum.any?(core_courses, &(&1.title == "Elemental Literacy"))
  end

  test "Academy Core seeds a three-term curriculum for every specialization track", %{
    realm: realm
  } do
    assert Enum.all?(Academy.seed_courses_for_realm(realm.id), &match?({:ok, _course}, &1))

    expected_courses = %{
      wizardry: %{
        1 => "Dual-School Fundamentals",
        2 => "Spellcraft Practicum",
        3 => "Arcane Mini-Thesis"
      },
      alchemy: %{
        1 => "Ingredients Taxonomy",
        2 => "Recipe Development Practicum",
        3 => "Alchemy Mini-Thesis"
      },
      mastery: %{
        1 => "Materials Science",
        2 => "Toolcraft Practicum",
        3 => "Mastery Mini-Thesis"
      }
    }

    for {track, courses_by_term} <- expected_courses,
        {term_number, title} <- courses_by_term do
      enrollment = %Enrollment{realm_id: realm.id, program_type: :academy_core, track: track}

      assert Enum.any?(
               Academy.list_courses_for_term(enrollment, term_number),
               &(&1.title == title)
             )
    end
  end

  test "terms use fixed yearly slots and record missed finals before graduation", %{
    character: character
  } do
    started_at = ~U[2026-07-01 12:00:00Z]

    assert {:ok, %{enrollment: enrollment}} =
             Academy.begin_basic_education(character, started_at: started_at)

    assert Academy.required_term_count(:basic_education) == 10
    assert DateTime.compare(Academy.term_schedule(enrollment, 1).starts_at, started_at) == :eq

    assert {:ok, first_term} = Academy.begin_term(enrollment.id, now: started_at)
    assert {:ok, _failed_term} = Academy.fail_term(first_term.id, now: started_at)

    assert {:error, changeset} =
             Academy.begin_term(enrollment.id, now: DateTime.add(started_at, 1, :second))

    assert %{status: ["the next term has not opened yet"]} = errors_on(changeset)

    second_schedule = Academy.term_schedule(enrollment, 2)
    assert {:ok, second_term} = Academy.begin_term(enrollment.id, now: second_schedule.starts_at)
    assert second_term.term_number == 2

    assert {:ok, %{enrollment: completed_enrollment}} =
             Academy.complete_enrollment_by_id(enrollment.id,
               now: enrollment.expected_completion_at,
               force: true
             )

    assert completed_enrollment.status == :failed
    assert completed_enrollment.metadata["outcome_tier"] == "expulsion"

    assert Academy.list_terms_for_enrollment(enrollment.id)
           |> Enum.count(&(&1.status == :failed)) == 10
  end

  test "an expelled Basic Education student must wait one game year before re-enrolling", %{
    character: character
  } do
    started_at = ~U[2026-07-01 12:00:00Z]

    assert {:ok, %{enrollment: enrollment}} =
             Academy.begin_basic_education(character, started_at: started_at)

    assert {:ok, %{enrollment: expelled_enrollment}} =
             Academy.complete_enrollment_by_id(enrollment.id,
               now: enrollment.expected_completion_at,
               force: true
             )

    assert expelled_enrollment.metadata["outcome_tier"] == "expulsion"

    reenrollment_at = MMGO.Travel.Clock.arrival_at(expelled_enrollment.completed_at, 364)

    assert {:error, changeset} =
             Academy.begin_basic_education(character,
               started_at: DateTime.add(reenrollment_at, -1, :second)
             )

    assert %{status: ["basic education re-enrollment is still on a one-year cooldown"]} =
             errors_on(changeset)

    assert {:ok, %{enrollment: replacement_enrollment}} =
             Academy.begin_basic_education(character, started_at: reenrollment_at)

    assert replacement_enrollment.status == :active
    assert replacement_enrollment.started_at == reenrollment_at
  end

  test "a term advances through lectures, midterm, final, and course grading", %{
    realm: realm,
    character: character
  } do
    term = academy_core_term(character)
    course = course_fixture(realm, "term-lifecycle")

    assert {:ok, course_enrollment} = Academy.enroll_in_course(character.id, term.id, course.id)

    assert %{phase: :enrollment, lectures_attended: 0, lectures_required: 3} =
             Academy.term_progress(term)

    assert {:ok, lecture_term} = Academy.open_lecture_phase(character.id, term.id)
    assert Academy.term_progress(lecture_term).phase == :lectures

    assert {:ok, first_lecture} = Academy.attend_lecture(character.id, term.id)
    assert Academy.term_progress(first_lecture).lectures_attended == 1

    assert {:ok, _second_lecture} = Academy.attend_lecture(character.id, term.id)
    assert {:ok, club_term} = Academy.attend_lecture(character.id, term.id)
    assert Academy.term_progress(club_term).phase == :club_window

    assert {:ok, midterm_term} = Academy.close_club_window(character.id, term.id)
    assert Academy.term_progress(midterm_term).phase == :midterm

    assert {:error, changeset} = Academy.submit_final(character.id, term.id, 90)
    assert %{status: ["final is not open for this term"]} = errors_on(changeset)

    assert {:ok, final_term} = Academy.submit_midterm(character.id, term.id, 80)
    assert Academy.term_progress(final_term).phase == :final

    assert {:ok, completed_term} = Academy.submit_final(character.id, term.id, 90)
    assert completed_term.status == :completed
    assert completed_term.exam_score == 86
    assert Academy.term_progress(completed_term).phase == :break

    assert Repo.get!(MMGO.Academy.CourseEnrollment, course_enrollment.id).status == :completed
    assert Repo.get!(MMGO.Academy.CourseEnrollment, course_enrollment.id).grade == 86
  end

  test "lecture prompts are server-scored and raise the final ceiling as they are completed", %{
    character: character
  } do
    term = academy_core_term(character)
    assert {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    assert {:ok, prompt} = Academy.lecture_prompt(character.id, term.id)
    assert prompt.number == 1
    refute Map.has_key?(hd(prompt.questions), :answer)

    assert {:ok,
            %{
              term: first_term,
              correct_answers: 2,
              question_count: 2,
              final_ceiling: 80
            }} =
             Academy.submit_lecture(character.id, term.id, %{"q1" => "a", "q2" => "a"})

    first_progress = Academy.term_progress(first_term)
    assert first_progress.lectures_attended == 1
    assert first_progress.lecture_final_ceiling == 80

    assert [%{"lecture_key" => "academy_foundations", "correct_answers" => 2}] =
             first_progress.lecture_results

    assert {:ok, second_prompt} = Academy.lecture_prompt(character.id, term.id)
    assert second_prompt.number == 2

    assert {:ok, %{final_ceiling: 90}} =
             Academy.submit_lecture(character.id, term.id, %{"q1" => "", "q2" => ""})

    assert {:ok, %{term: final_lecture_term, final_ceiling: 100}} =
             Academy.submit_lecture(character.id, term.id, %{"q1" => "a", "q2" => "a"})

    assert Academy.term_progress(final_lecture_term).phase == :club_window
    assert {:error, _reason} = Academy.lecture_prompt(character.id, term.id)
  end

  test "lectures are optional and a student may open the club window early", %{
    character: character
  } do
    term = academy_core_term(character)
    assert {:ok, lecture_term} = Academy.open_lecture_phase(character.id, term.id)
    assert Academy.term_progress(lecture_term).lecture_final_ceiling == 70

    assert {:ok, club_term} = Academy.close_lecture_phase(character.id, term.id)

    progress = Academy.term_progress(club_term)
    assert progress.phase == :club_window
    assert progress.lectures_attended == 0
    assert progress.lecture_final_ceiling == 70
    assert {:error, :academy_lecture_unavailable} = Academy.lecture_prompt(character.id, term.id)

    assert {:ok, _midterm_term} = Academy.close_club_window(character.id, term.id)
    assert {:ok, _final_term} = Academy.submit_midterm(character.id, term.id, 100)
    assert {:ok, completed_term} = Academy.submit_final(character.id, term.id, 100)
    assert completed_term.exam_score == 70
  end

  test "exam questions include a sanitized track-specific applied challenge", %{realm: realm} do
    wizard_enrollment = %Enrollment{
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry
    }

    alchemy_enrollment = %Enrollment{
      realm_id: realm.id,
      program_type: :academy_core,
      track: :alchemy
    }

    wizard_questions = Academy.exam_questions(wizard_enrollment)
    wizard_applied = Enum.find(wizard_questions, &(&1.key == "q6"))
    alchemy_applied = Academy.exam_questions(alchemy_enrollment) |> Enum.find(&(&1.key == "q6"))

    assert length(wizard_questions) == 6
    assert wizard_applied.label =~ "инкантации"
    assert alchemy_applied.label =~ "варкой"
    refute Map.has_key?(wizard_applied, :answer)

    assert Academy.score_exam(wizard_enrollment, %{
             "q1" => "b",
             "q2" => "a",
             "q3" => "c",
             "q4" => "b",
             "q5" => "d",
             "q6" => "a"
           }) == 100
  end

  test "office hours persist a mentor relationship and a course-grade bonus", %{
    realm: realm,
    character: character
  } do
    term = academy_core_term(character)
    course = course_fixture(realm, "office-hours")

    assert {:ok, course_enrollment} = Academy.enroll_in_course(character.id, term.id, course.id)
    assert {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    assert {:ok, %{course_enrollment: visited, instructor_key: instructor_key}} =
             Academy.attend_office_hours(character.id, term.id, course.id)

    assert visited.metadata["office_hours_attended"]
    assert visited.metadata["office_hours_grade_bonus"] == 5
    assert instructor_key == "course:#{course.id}"

    assert {:error, changeset} = Academy.attend_office_hours(character.id, term.id, course.id)
    assert %{status: ["office hours have already been attended"]} = errors_on(changeset)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    assert {:ok, _midterm_term} = Academy.close_club_window(character.id, term.id)
    assert {:ok, _final_term} = Academy.submit_midterm(character.id, term.id, 80)
    assert {:ok, _completed_term} = Academy.submit_final(character.id, term.id, 80)

    graded_course_enrollment = Repo.get!(MMGO.Academy.CourseEnrollment, course_enrollment.id)
    assert graded_course_enrollment.grade == 85
    assert graded_course_enrollment.metadata["office_hours_grade_applied"] == 5

    enrollment = Repo.get!(Enrollment, term.enrollment_id)

    assert enrollment.metadata["instructor_relationships"][instructor_key]["office_hours"] == 1
    assert enrollment.metadata["instructor_relationships"][instructor_key]["score"] == 5
  end

  test "basic education may skip a midterm with an 80-point final ceiling", %{
    character: character
  } do
    {:ok, %{enrollment: enrollment}} = Academy.begin_basic_education(character)
    {:ok, term} = Academy.begin_term(enrollment.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    assert Repo.get!(Character, character.id).xp == 15
    assert {:ok, _midterm_term} = Academy.close_club_window(character.id, term.id)
    assert {:ok, final_term} = Academy.skip_midterm(character.id, term.id)
    assert Academy.term_progress(final_term).phase == :final
    assert Academy.term_progress(final_term).midterm_skipped?

    assert {:ok, completed_term} = Academy.submit_final(character.id, term.id, 100)
    assert completed_term.exam_score == 80
  end

  test "the club window derives merit eligibility from a real club attendance record", %{
    character: character,
    club_founder: club_founder
  } do
    term = academy_core_term(character)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    club_term = Repo.get!(MMGO.Academy.Term, term.id)
    assert Academy.term_progress(club_term, character_id: character.id).phase == :club_window

    assert {:ok, %{club: club}} =
             Clubs.create_club(club_founder, %{club_type: :general_interest, name: "Merit Circle"})

    assert {:ok, %{invitation: invitation}} = Clubs.invite_member(club, club_founder, character)
    assert {:ok, _membership} = Clubs.accept_invitation(invitation, character)
    assert {:ok, event} = Clubs.create_event(club, %{kind: :general_meeting})
    assert {:ok, _attendance} = Clubs.attend_event(event, character)

    progress = Academy.term_progress(club_term, character_id: character.id)
    assert progress.club_events_attended == 1
    assert progress.merit_eligible?

    assert {:ok, closed_term} = Academy.close_club_window(character.id, term.id)
    closed_progress = Academy.term_progress(closed_term)
    assert closed_progress.phase == :midterm
    assert closed_progress.club_events_attended == 1
    assert closed_progress.merit_eligible?
  end

  test "graduation snapshots GPA, cohort rank, and a club-qualified merit grant", %{
    realm: realm,
    character: character,
    club_founder: club_founder
  } do
    peer = character_fixture(realm, "peer-student", "Peer Student")
    started_at = ~U[2026-07-11 09:00:00Z]

    assert {:ok, %{enrollment: peer_enrollment}} =
             Academy.begin_basic_education(peer, started_at: started_at)

    assert {:ok, %{enrollment: enrollment}} =
             Academy.begin_basic_education(character, started_at: started_at)

    complete_term_with_club(peer, peer_enrollment, club_founder, 70, "Peer Merit Circle")
    complete_term_with_club(character, enrollment, club_founder, 95, "Student Merit Circle")

    assert {:ok, %{enrollment: peer_completed_enrollment}} =
             Academy.complete_enrollment_by_id(peer_enrollment.id,
               force: true,
               now: started_at
             )

    refute peer_completed_enrollment.metadata["valedictorian"]

    assert {:ok, %{enrollment: completed_enrollment}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true, now: started_at)

    assert completed_enrollment.metadata["gpa"] == 95.0
    assert completed_enrollment.metadata["cohort_rank"] == 1
    assert completed_enrollment.metadata["cohort_size"] == 2
    assert completed_enrollment.metadata["merit_scholarship_eligible"]
    assert completed_enrollment.metadata["valedictorian"]

    assert completed_enrollment.metadata["valedictorian_title"] ==
             "Валедикториан когорты #{Academy.cohort_key(completed_enrollment)}"

    assert is_binary(completed_enrollment.metadata["valedictorian_hall_of_fame_until"])
    refute Repo.get!(Enrollment, peer_enrollment.id).metadata["valedictorian"]

    record = Academy.academic_record(completed_enrollment)
    assert record.gpa == 95.0
    assert record.cohort_rank == 1
    assert record.cohort_size == 2
    assert record.ranking_eligible?
    assert record.merit_scholarship_eligible?

    assert {:ok, %{enrollment: academy_core}} =
             Academy.start_academy_track(character, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert academy_core.funding_type == :grant
  end

  test "a valedictorian claims one real spell and permanently unlocks its chosen school", %{
    character: character
  } do
    now = ~U[2026-07-12 12:00:00Z]
    enrollment = valedictorian_enrollment_fixture(character, completed_at: now)

    assert Academy.pending_valedictorian_bonus(character.id).id == enrollment.id

    assert {:ok, %{character: updated_character, enrollment: updated_enrollment, spell: spell}} =
             Academy.claim_valedictorian_bonus_spell(character, "water", now: now)

    assert spell.school == :water
    assert "valedictorian" in spell.tags
    assert "valedictorian_bonus" in spell.narrative_tags
    assert updated_character.metadata["valedictorian_bonus_schools"] == ["water"]
    assert Academy.school_permitted?(character.id, "water")
    refute Academy.school_permitted?(character.id, "fire")
    assert is_nil(Academy.pending_valedictorian_bonus(character.id))

    assert updated_enrollment.metadata["valedictorian_bonus"] == %{
             "claimed_at" => DateTime.to_iso8601(now),
             "school" => "water",
             "spell_id" => spell.id,
             "status" => "claimed"
           }

    assert [persisted_spell] = Spells.list_spells_for_character(character.id)
    assert persisted_spell.id == spell.id

    assert {:error, changeset} =
             Academy.claim_valedictorian_bonus_spell(character, "fire", now: now)

    assert %{status: ["no unclaimed valedictorian bonus is available"]} = errors_on(changeset)
    assert [_only_one_spell] = Spells.list_spells_for_character(character.id)
  end

  test "the cohort winner receives the title even when another student completes last", %{
    realm: realm,
    character: character,
    club_founder: club_founder
  } do
    peer = character_fixture(realm, "top-student", "Top Student")
    started_at = ~U[2026-07-11 09:00:00Z]

    {:ok, %{enrollment: peer_enrollment}} =
      Academy.begin_basic_education(peer, started_at: started_at)

    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, started_at: started_at)

    complete_term_with_club(peer, peer_enrollment, club_founder, 98, "Top Merit Circle")
    complete_term_with_club(character, enrollment, club_founder, 72, "Later Merit Circle")

    assert {:ok, %{enrollment: first_completed}} =
             Academy.complete_enrollment_by_id(peer_enrollment.id,
               force: true,
               now: started_at
             )

    refute first_completed.metadata["valedictorian"]
    refute first_completed.metadata["honors"]
    refute first_completed.metadata["merit_scholarship_eligible"]

    assert {:ok, %{enrollment: last_completed}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true, now: started_at)

    refute last_completed.metadata["valedictorian"]

    finalized_winner = Repo.get!(Enrollment, peer_enrollment.id)
    assert finalized_winner.metadata["valedictorian"]
    assert finalized_winner.metadata["honors"]
    assert finalized_winner.metadata["merit_scholarship_eligible"]
    assert is_binary(finalized_winner.metadata["valedictorian_title"])
  end

  test "Academy Core advisor choice settles only after its cohort closes", %{
    realm: realm,
    character: character
  } do
    peer = character_fixture(realm, "core-top-student", "Core Top Student")
    started_at = ~U[2026-07-11 09:00:00Z]

    complete_basic_education(peer)
    complete_basic_education(character)

    assert {:ok, %{enrollment: peer_enrollment}} =
             Academy.start_academy_track(peer, :alchemy, %{},
               started_at: started_at,
               duration_game_days: 1
             )

    assert {:ok, %{enrollment: enrollment}} =
             Academy.start_academy_track(character, :alchemy, %{},
               started_at: started_at,
               duration_game_days: 1
             )

    record_academy_terms(peer_enrollment, [98, 98, 98])
    record_academy_terms(enrollment, [72, 72, 72])

    assert {:ok, %{enrollment: first_completed}} =
             Academy.complete_enrollment_by_id(peer_enrollment.id, force: true)

    refute first_completed.metadata["honors"]
    refute Academy.advisor_pick_eligible?(peer.id)

    assert {:ok, %{enrollment: _last_completed}} =
             Academy.complete_enrollment_by_id(enrollment.id, force: true)

    assert Repo.get!(Enrollment, peer_enrollment.id).metadata["honors"]
    assert Academy.advisor_pick_eligible?(peer.id)
    refute Academy.advisor_pick_eligible?(character.id)
  end

  test "the hall of fame keeps valedictorians pinned for one real year", %{
    realm: realm,
    character: character
  } do
    now = ~U[2026-07-12 12:00:00Z]

    current =
      valedictorian_enrollment_fixture(character, completed_at: DateTime.add(now, -60, :second))

    former = character_fixture(realm, "former-valedictorian", "Former Valedictorian")

    expired =
      valedictorian_enrollment_fixture(former,
        completed_at: DateTime.add(now, -(366 * 24 * 60 * 60), :second)
      )

    assert [pinned] = Academy.list_valedictorians_for_realm(realm.id, now: now)
    assert pinned.id == current.id
    assert pinned.character.id == character.id
    assert Academy.valedictorian_title(pinned) == "Валедикториан когорты academy_core:2026"

    refute Enum.any?(
             Academy.list_valedictorians_for_realm(realm.id, now: now),
             &(&1.id == expired.id)
           )
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :new, level: 1, xp: 0})
    |> Repo.insert!()
  end

  defp enroll_active_academy_core(character, realm) do
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

  defp valedictorian_enrollment_fixture(character, opts) do
    completed_at = Keyword.fetch!(opts, :completed_at)

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

  defp academy_core_term(character) do
    {:ok, %{enrollment: basic}} = Academy.begin_basic_education(character, duration_game_days: 1)
    {:ok, _completed_basic} = Academy.complete_enrollment_by_id(basic.id, force: true)

    {:ok, %{enrollment: core}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    {:ok, term} = Academy.begin_term(core.id)
    term
  end

  defp complete_basic_education(character) do
    {:ok, %{enrollment: enrollment}} =
      Academy.begin_basic_education(character, duration_game_days: 1)

    {:ok, %{enrollment: %Enrollment{status: :completed}}} =
      Academy.complete_enrollment_by_id(enrollment.id, force: true)
  end

  defp record_academy_terms(enrollment, scores) do
    scores
    |> Enum.with_index(1)
    |> Enum.each(fn {score, term_number} ->
      %Term{}
      |> Term.changeset(%{
        enrollment_id: enrollment.id,
        realm_id: enrollment.realm_id,
        term_number: term_number,
        status: :completed,
        started_at: enrollment.started_at,
        ended_at: enrollment.expected_completion_at,
        exam_score: score,
        metadata: %{"phase" => "break", "club_events_attended" => 1, "club_events_required" => 1}
      })
      |> Repo.insert!()
    end)
  end

  defp record_academy_term(enrollment, term_number, status, score) do
    %Term{}
    |> Term.changeset(%{
      enrollment_id: enrollment.id,
      realm_id: enrollment.realm_id,
      term_number: term_number,
      status: status,
      started_at: enrollment.started_at,
      ended_at: enrollment.expected_completion_at,
      exam_score: score,
      metadata: %{"phase" => "break", "club_events_attended" => 1, "club_events_required" => 1}
    })
    |> Repo.insert!()
  end

  defp complete_term_with_club(character, enrollment, club_founder, score, club_name) do
    now = enrollment.started_at
    {:ok, term} = Academy.begin_term(enrollment.id, now: now)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id, now: now)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id, now: now)
    end)

    {:ok, %{club: club}} =
      Clubs.create_club(club_founder, %{club_type: :general_interest, name: club_name})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, club_founder, character)
    assert {:ok, _membership} = Clubs.accept_invitation(invitation, character)
    {:ok, event} = Clubs.create_event(club, %{kind: :general_meeting})
    {:ok, _attendance} = Clubs.attend_event(event, character)
    {:ok, _midterm_term} = Academy.close_club_window(character.id, term.id, now: now)
    {:ok, _final_term} = Academy.submit_midterm(character.id, term.id, score, now: now)
    {:ok, _completed_term} = Academy.submit_final(character.id, term.id, score, now: now)
  end

  defp course_fixture(realm, code) do
    %Course{}
    |> Course.changeset(%{
      realm_id: realm.id,
      source: :seeded,
      title: "#{code} title",
      track: :wizardry,
      school: :fire,
      syllabus: %{},
      status: :active,
      metadata: %{}
    })
    |> Repo.insert!()
  end
end

defmodule AcademyTestHelpers do
  alias MMGO.Travel.Clock

  def expected_completion(started_at, duration_game_days) do
    Clock.arrival_at(started_at, duration_game_days)
  end
end
