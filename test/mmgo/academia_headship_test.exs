defmodule MMGO.Academia.HeadshipTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academia
  alias MMGO.Academia.{Headship, Professor}
  alias MMGO.Academy
  alias MMGO.Academy.{Course, Enrollment}
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "headship", name: "Headship Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "headship-city",
        name: "Headship City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    professor_one = character_fixture(realm, city, "prof-one", "Professor One")
    professor_two = character_fixture(realm, city, "prof-two", "Professor Two")
    professor_three = character_fixture(realm, city, "prof-three", "Professor Three")
    npc_professor = character_fixture(realm, city, "npc-prof", "NPC Professor")
    outsider = character_fixture(realm, city, "outsider", "Outsider")

    professor_fixture(professor_one, realm)
    professor_fixture(professor_two, realm)
    professor_fixture(professor_three, realm)
    professor_fixture(npc_professor, realm, %{"npc_faculty" => true})

    %{
      realm: realm,
      city: city,
      professor_one: professor_one,
      professor_two: professor_two,
      professor_three: professor_three,
      npc_professor: npc_professor,
      outsider: outsider
    }
  end

  test "only active player professors enter the Academy Head roster", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three,
    npc_professor: npc_professor,
    outsider: outsider
  } do
    assert {:ok, state} = Headship.state(realm.id, now: ~U[2026-07-12 12:00:00Z])

    assert MapSet.new(Enum.map(state.eligible_professors, & &1.character_id)) ==
             MapSet.new([professor_one.id, professor_two.id, professor_three.id])

    refute Enum.any?(state.eligible_professors, &(&1.character_id == npc_professor.id))
    refute Enum.any?(state.eligible_professors, &(&1.character_id == outsider.id))
  end

  test "a snapshotted professor plurality elects a Head and a duplicate vote is rejected", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three
  } do
    now = ~U[2026-07-12 12:00:00Z]

    assert {:ok, %{election: election}} = Headship.open_election(professor_one, now: now)
    assert election.voter_count == 3
    assert length(election.candidates) == 3

    assert {:ok, %{resolution: :pending}} =
             Headship.cast_vote(professor_one, professor_two.id, now: now)

    assert {:error, changeset} = Headship.cast_vote(professor_one, professor_two.id, now: now)
    assert %{metadata: ["professor has already voted for Academy Head"]} = errors_on(changeset)

    assert {:ok, %{resolution: :pending}} =
             Headship.cast_vote(professor_two, professor_two.id, now: now)

    assert {:ok, %{resolution: :elected, head_character_id: head_character_id}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    assert head_character_id == professor_two.id

    assert {:ok, %{head: head, term_active?: true, open_election: nil}} =
             Headship.state(realm.id, now: now)

    assert head.character_id == professor_two.id
    assert Headship.current_head?(professor_two, now: now)
    refute Headship.current_head?(professor_one, now: now)
  end

  test "the vote snapshot rejects a professor appointed after the election begins", %{
    realm: realm,
    city: city,
    professor_one: professor_one,
    professor_two: professor_two
  } do
    now = ~U[2026-07-12 12:00:00Z]
    assert {:ok, _election} = Headship.open_election(professor_one, now: now)

    late_professor = character_fixture(realm, city, "late-prof", "Late Professor")
    professor_fixture(late_professor, realm)

    assert {:error, changeset} = Headship.cast_vote(late_professor, professor_two.id, now: now)

    assert %{metadata: ["voter was not in the Academy Head election snapshot"]} =
             errors_on(changeset)
  end

  test "a tied expired election retains the incumbent instead of inventing a winner", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three
  } do
    initial_now = ~U[2026-07-12 12:00:00Z]

    assert {:ok, _election} = Headship.open_election(professor_one, now: initial_now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: initial_now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: initial_now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: initial_now)

    after_term = DateTime.add(initial_now, 10 * 86_400 + 1, :second)

    assert {:ok, _election} = Headship.open_election(professor_one, now: after_term)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: after_term)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_two.id, now: after_term)

    assert {:ok, %{resolution: :tied, head_character_id: nil}} =
             Headship.cast_vote(professor_three, professor_three.id, now: after_term)

    assert {:ok, %{head: head, term_active?: false, last_result: "tied"}} =
             Headship.state(realm.id, now: after_term)

    assert head.character_id == professor_one.id
  end

  test "an eligible professor can settle a no-turnout election only after its deadline", %{
    realm: realm,
    professor_one: professor_one
  } do
    now = ~U[2026-07-12 12:00:00Z]
    assert {:ok, _election} = Headship.open_election(professor_one, now: now)

    assert {:error, changeset} = Headship.settle_election(professor_one, now: now)
    assert %{metadata: ["Academy Head election is still open for voting"]} = errors_on(changeset)

    after_close = DateTime.add(now, 24 * 3_600, :second)

    assert {:ok, %{resolution: :no_turnout, head_character_id: nil}} =
             Headship.settle_election(professor_one, now: after_close)

    assert {:ok, %{head: nil, last_result: "no_turnout"}} =
             Headship.state(realm.id, now: after_close)
  end

  test "the elected Head can grant a durable probation admission that unlocks Academy Core", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three,
    outsider: outsider
  } do
    now = ~U[2026-07-12 12:00:00Z]

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: outsider.id,
      realm_id: realm.id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :none,
      started_at: now,
      expected_completion_at: now,
      completed_at: now,
      metadata: %{"outcome_tier" => "probation"}
    })
    |> Repo.insert!()

    assert {:ok, _election} = Headship.open_election(professor_one, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    assert {:ok, %{admission: admission}} =
             Academia.issue_academy_head_admission(professor_one, outsider, now: now)

    assert admission["head_character_id"] == professor_one.id

    assert {:ok, %{enrollment: enrollment}} =
             Academy.start_academy_track(outsider, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert enrollment.program_type == :academy_core
  end

  test "retiring an elected Head immediately vacates the office for the remaining professors", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three
  } do
    now = ~U[2026-07-12 12:00:00Z]

    assert {:ok, _election} = Headship.open_election(professor_one, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    assert {:ok, %{professor: %{status: :retired}, headship: %{vacated?: true}}} =
             Academia.retire_professor(professor_one, now: now)

    assert {:ok, %{head: nil, term_active?: false, can_open_election?: true}} =
             Headship.state(realm.id, now: now, actor_id: professor_two.id)
  end

  test "the elected Head pays one real charity stipend to an active grant student", %{
    realm: realm,
    professor_one: professor_one,
    professor_two: professor_two,
    professor_three: professor_three,
    outsider: outsider
  } do
    now = ~U[2026-07-12 12:00:00Z]

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: outsider.id,
      realm_id: realm.id,
      program_type: :academy_core,
      track: :wizardry,
      status: :active,
      funding_type: :grant,
      started_at: now,
      expected_completion_at: DateTime.add(now, 10_000, :second),
      metadata: %{}
    })
    |> Repo.insert!()

    {:ok, treasury} = Economy.ensure_treasury_account(realm, 100)
    {:ok, charity} = Economy.ensure_charity_fund_account(realm)
    assert {:ok, _funding} = Economy.transfer(treasury, charity, 40)

    assert {:ok, _election} = Headship.open_election(professor_one, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    assert [%{character: %{id: candidate_id}}] =
             Academia.list_charity_stipend_candidates_for_realm(realm.id)

    assert candidate_id == outsider.id

    assert {:ok, %{enrollment: updated_enrollment, stipend: stipend}} =
             Academia.award_academy_head_charity_stipend(professor_one, outsider, 25, now: now)

    assert stipend["amount"] == 25
    assert stipend["head_character_id"] == professor_one.id
    assert Academy.charity_stipend(updated_enrollment) == stipend
    assert Economy.get_account!(charity.id).current_balance == 15

    {:ok, outsider_account} = Economy.ensure_character_account(outsider)
    assert Economy.get_account!(outsider_account.id).current_balance == 25

    assert {:error, changeset} =
             Academia.award_academy_head_charity_stipend(professor_one, outsider, 5, now: now)

    assert %{metadata: ["student has already received a charity stipend for this enrollment"]} =
             errors_on(changeset)

    assert Economy.get_account!(charity.id).current_balance == 15
    assert Economy.get_account!(outsider_account.id).current_balance == 25
  end

  test "the elected Head reschedules seeded curriculum in both the catalog and direct enrollment",
       %{
         realm: realm,
         professor_one: professor_one,
         professor_two: professor_two,
         professor_three: professor_three,
         outsider: outsider
       } do
    now = ~U[2026-07-12 12:00:00Z]

    assert Enum.all?(Academy.seed_courses_for_realm(realm.id), &match?({:ok, _course}, &1))

    economic_basics =
      Academy.list_courses_for_realm(realm.id)
      |> Enum.find(&(&1.title == "Economic Basics"))

    elemental_literacy =
      Academy.list_courses_for_realm(realm.id)
      |> Enum.find(&(&1.title == "Elemental Literacy"))

    assert {:ok, _election} = Headship.open_election(professor_one, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    assert {:ok, %{override: override}} =
             Academia.set_academy_head_curriculum_override(
               professor_one,
               economic_basics,
               1,
               now: now
             )

    assert override["years"] == [1]
    assert override["head_character_id"] == professor_one.id
    assert Repo.get!(Course, economic_basics.id).syllabus["years"] == [3, 4]

    basic = %Enrollment{realm_id: realm.id, program_type: :basic_education}

    assert Enum.any?(Academy.list_courses_for_term(basic, 1), &(&1.id == economic_basics.id))
    refute Enum.any?(Academy.list_courses_for_term(basic, 3), &(&1.id == economic_basics.id))

    assert {:ok, %{enrollment: enrollment}} =
             Academy.begin_basic_education(outsider, started_at: now)

    assert {:ok, term} = Academy.begin_term(enrollment.id, now: now)

    assert {:ok, _course_enrollment} =
             Academy.enroll_in_course(outsider.id, term.id, economic_basics.id)

    assert {:ok, _override} =
             Academia.set_academy_head_curriculum_override(
               professor_one,
               elemental_literacy,
               2,
               now: now
             )

    refute Enum.any?(Academy.list_courses_for_term(basic, 1), &(&1.id == elemental_literacy.id))

    assert {:error, changeset} =
             Academy.enroll_in_course(outsider.id, term.id, elemental_literacy.id)

    assert %{status: ["course is not offered in this term"]} = errors_on(changeset)

    assert {:ok, %{realm: updated_realm}} =
             Academia.clear_academy_head_curriculum_override(
               professor_one,
               economic_basics,
               now: now
             )

    assert get_in(updated_realm.metadata, ["academy_curriculum", "overrides", economic_basics.id]) ==
             nil

    refute Enum.any?(Academy.list_courses_for_term(basic, 1), &(&1.id == economic_basics.id))
    assert Enum.any?(Academy.list_courses_for_term(basic, 3), &(&1.id == economic_basics.id))
  end

  test "curriculum overrides reject non-Heads, foreign and published courses, and invalid terms",
       %{
         realm: realm,
         professor_one: professor_one,
         professor_two: professor_two,
         professor_three: professor_three,
         outsider: outsider
       } do
    now = ~U[2026-07-12 12:00:00Z]

    assert Enum.all?(Academy.seed_courses_for_realm(realm.id), &match?({:ok, _course}, &1))

    economic_basics =
      Academy.list_courses_for_realm(realm.id)
      |> Enum.find(&(&1.title == "Economic Basics"))

    assert {:error, changeset} =
             Academia.set_academy_head_curriculum_override(outsider, economic_basics, 1, now: now)

    assert %{syllabus: ["only the current Academy Head may override the curriculum"]} =
             errors_on(changeset)

    assert {:ok, _election} = Headship.open_election(professor_one, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_one, professor_one.id, now: now)
    assert {:ok, _} = Headship.cast_vote(professor_two, professor_one.id, now: now)

    assert {:ok, %{resolution: :elected}} =
             Headship.cast_vote(professor_three, professor_three.id, now: now)

    {:ok, published_course} =
      %Course{}
      |> Course.changeset(%{
        realm_id: realm.id,
        source: :published,
        title: "Published Curriculum",
        syllabus: %{"years" => [1]},
        status: :active,
        metadata: %{}
      })
      |> Repo.insert()

    {:ok, foreign_realm} =
      Worlds.create_realm(%{
        slug: "headship-foreign-curriculum",
        name: "Foreign Curriculum Realm",
        is_default: false
      })

    {:ok, foreign_course} =
      %Course{}
      |> Course.changeset(%{
        realm_id: foreign_realm.id,
        source: :seeded,
        title: "Foreign Seeded Curriculum",
        syllabus: %{"years" => [1]},
        status: :active,
        metadata: %{}
      })
      |> Repo.insert()

    assert {:error, published_changeset} =
             Academia.set_academy_head_curriculum_override(
               professor_one,
               published_course,
               1,
               now: now
             )

    assert %{syllabus: ["only seeded courses may be rescheduled"]} =
             errors_on(published_changeset)

    assert {:error, foreign_changeset} =
             Academia.set_academy_head_curriculum_override(
               professor_one,
               foreign_course,
               1,
               now: now
             )

    assert %{syllabus: ["Academy Head and course must be in the same realm"]} =
             errors_on(foreign_changeset)

    assert {:error, term_changeset} =
             Academia.set_academy_head_curriculum_override(
               professor_one,
               economic_basics,
               11,
               now: now
             )

    assert %{syllabus: ["course cannot be scheduled for that curriculum term"]} =
             errors_on(term_changeset)
  end

  defp professor_fixture(character, realm, metadata \\ %{}) do
    %Professor{}
    |> Professor.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      status: :active,
      appointed_at: DateTime.utc_now(),
      metadata: metadata
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
end
