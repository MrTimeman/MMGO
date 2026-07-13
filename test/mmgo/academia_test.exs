defmodule MMGO.AcademiaTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Academy.Enrollment
  alias MMGO.Academia

  alias MMGO.Academia.{
    AdvisorRelationship,
    CompleteProjectWorker,
    Professor,
    Project,
    Publication
  }

  alias MMGO.Clubs
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "city",
        name: "City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    scholar = character_fixture(realm, city, "scholar", "Scholar")
    outsider = character_fixture(realm, city, "outsider", "Outsider")

    complete_academia_enrollment(scholar, realm)

    %{realm: realm, city: city, scholar: scholar, outsider: outsider}
  end

  test "start_project/4 creates an active research project and schedules completion", %{
    scholar: scholar
  } do
    assert {:ok, %{project: project, worker_job: worker_job}} =
             Academia.start_project(scholar, :spell, "Fire Theory", duration_game_days: 1)

    assert project.status == :active
    assert project.project_kind == :spell
    assert worker_job.args == %{"project_id" => project.id}
  end

  test "an active advisor shortens a research project without reducing its base reward", %{
    realm: realm,
    city: city,
    scholar: scholar
  } do
    advisor = character_fixture(realm, city, "advisor", "Advisor")
    professor_fixture(advisor, realm)
    complete_honors_academy_core_enrollment(scholar, realm)
    assert {:ok, _relationship} = Academia.set_advisor(scholar, advisor)

    started_at = ~U[2026-07-11 12:00:00Z]

    assert {:ok, %{project: project}} =
             Academia.start_project(scholar, :tool, "Advisor-Guided Tool",
               started_at: started_at,
               duration_game_days: 12
             )

    assert DateTime.compare(project.completes_at, Clock.arrival_at(started_at, 10)) == :eq
    assert project.metadata["base_duration_game_days"] == 12
    assert project.metadata["duration_game_days"] == 10
    assert project.metadata["advisor_character_id"] == advisor.id
    assert project.metadata["advisor_speed_bonus_percent"] == 20

    assert {:ok, %{character: updated_character}} =
             Academia.complete_project_by_id(project.id, force: true)

    assert updated_character.xp == 120
  end

  test "ordinary Academia entrants receive a server-selected availability match", %{
    realm: realm,
    city: city,
    scholar: scholar
  } do
    requested = character_fixture(realm, city, "requested-advisor", "Requested Advisor")
    professor_fixture(requested, realm)

    refute Academia.advisor_pick_eligible?(scholar.id)

    assert {:error, changeset} = Academia.set_advisor(scholar, requested)

    assert %{status: ["only top Academy Core graduates may request a specific advisor"]} =
             errors_on(changeset)

    assert {:ok, relationship} = Academia.match_advisor(scholar)
    assert relationship.professor_character_id == requested.id
    assert relationship.metadata["assignment"] == "availability_match"
    assert relationship.metadata["matched_at"]
  end

  test "advisor matching is available as soon as an Academia enrollment opens", %{
    realm: realm,
    city: city
  } do
    entrant = character_fixture(realm, city, "academia-entrant", "Academia Entrant")
    advisor = character_fixture(realm, city, "entry-advisor", "Entry Advisor")
    professor_fixture(advisor, realm)
    begin_academia_enrollment(entrant, realm)

    assert Academia.academia_admitted?(entrant.id)
    assert {:ok, relationship} = Academia.match_advisor(entrant)
    assert relationship.professor_character_id == advisor.id
  end

  test "complete_project_by_id/2 publishes results and awards XP", %{scholar: scholar} do
    {:ok, %{project: project}} =
      Academia.start_project(scholar, :tool, "Hammer Design", duration_game_days: 1)

    assert {:ok,
            %{project: completed_project, publication: publication, character: updated_character}} =
             Academia.complete_project_by_id(project.id, force: true)

    assert completed_project.status == :completed
    assert publication.publication_kind == :tool
    assert updated_character.xp == 10
  end

  test "a completed research project redeems shared research-club notes", %{
    realm: realm,
    city: city,
    scholar: scholar
  } do
    complete_basic_enrollment(scholar, realm)
    professor_fixture(scholar, realm)

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 1_000)
    {:ok, _funding} = Economy.grant_from_treasury(realm, scholar, Clubs.club_founding_fee())

    contributor = character_fixture(realm, city, "club-contributor", "Club Contributor")
    complete_basic_enrollment(contributor, realm)

    {:ok, %{club: club}} =
      Clubs.create_club(scholar, %{club_type: :research, name: "Shared Research"})

    {:ok, %{invitation: invitation}} = Clubs.invite_member(club, scholar, contributor)
    {:ok, _membership} = Clubs.accept_invitation(invitation, contributor)
    {:ok, event} = Clubs.create_event(club, %{kind: :research_session})

    assert {:ok, _attendance} = Clubs.attend_event(event, scholar)
    assert {:ok, _attendance} = Clubs.attend_event(event, contributor)
    contributor_xp_after_attendance = Repo.get!(Character, contributor.id).xp

    {:ok, %{project: project}} =
      Academia.start_project(scholar, :tool, "Club-Supported Tool", duration_game_days: 1)

    assert {:ok, %{project: completed_project, research_rewards: [reward]}} =
             Academia.complete_project_by_id(project.id, force: true)

    assert reward["character_id"] == contributor.id
    assert reward["xp_awarded"] == 1
    assert completed_project.metadata["club_research_rewards"] == [reward]
    assert Repo.get!(Character, contributor.id).xp == contributor_xp_after_attendance + 1
  end

  test "appoint_professor/1 requires a completed thesis publication", %{scholar: scholar} do
    assert {:error, changeset} = Academia.appoint_professor(scholar)

    assert %{status: ["character must complete a thesis before becoming professor"]} =
             errors_on(changeset)

    panelists = defense_panel_fixture(scholar.realm_id, scholar.current_location_id, "appoint")

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Tower Thesis", duration_game_days: 1)

    {:ok, %{project: completed_project}} =
      Academia.complete_project_by_id(thesis_project.id, force: true)

    assert {:ok, accepted_project} = resolve_thesis(completed_project, panelists, :accept)
    assert accepted_project.publication_id

    assert {:ok, %Professor{} = professor} = Academia.appoint_professor(scholar)
    assert professor.status == :active
  end

  test "publish_course/3 requires professor status", %{
    realm: realm,
    scholar: scholar,
    outsider: outsider
  } do
    panelists = defense_panel_fixture(scholar.realm_id, scholar.current_location_id, "course")

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Tower Thesis", duration_game_days: 1)

    {:ok, %{project: completed_project}} =
      Academia.complete_project_by_id(thesis_project.id, force: true)

    assert {:ok, _defense} = resolve_thesis(completed_project, panelists, :accept)
    {:ok, _professor} = Academia.appoint_professor(scholar)

    assert {:ok, %Publication{} = publication} =
             Academia.publish_course(scholar, "Battle Theory",
               track: :wizardry,
               school: :fire,
               syllabus: %{"summary" => "A professor-authored course."}
             )

    assert publication.publication_kind == :course

    assert %{source: :published, publication_id: publication_id, track: :wizardry, school: :fire} =
             Academy.list_courses_for_realm(realm.id)
             |> Enum.find(&(&1.publication_id == publication.id))

    assert publication_id == publication.id

    assert {:error, changeset} = Academia.publish_course(outsider, "Nope")

    assert %{publication_kind: ["character must be a professor to publish courses"]} =
             errors_on(changeset)
  end

  test "a professor recommendation is required and sufficient for probation Academy Core admission",
       %{realm: realm, city: city, scholar: scholar} do
    professor_fixture(scholar, realm)
    probationer = character_fixture(realm, city, "probationer", "Probationer")

    %MMGO.Academy.Enrollment{}
    |> MMGO.Academy.Enrollment.changeset(%{
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

    assert {:error, changeset} =
             Academy.start_academy_track(probationer, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert %{status: ["probation graduates require an active professor recommendation"]} =
             errors_on(changeset)

    assert [%{character: %{id: probationer_id}}] =
             Academia.list_probation_graduates_for_realm(realm.id)

    assert probationer_id == probationer.id

    assert {:ok, %{enrollment: recommended_enrollment, recommendation: recommendation}} =
             Academia.issue_admission_recommendation(scholar, probationer)

    assert recommendation["professor_character_id"] == scholar.id
    assert recommendation["non_transferable"]

    assert recommended_enrollment.metadata["professor_recommendation"]["purpose"] ==
             "academy_core_admission"

    assert {:ok, %{enrollment: academy_core}} =
             Academy.start_academy_track(probationer, :wizardry, %{
               primary_school: :fire,
               secondary_school: :air
             })

    assert academy_core.program_type == :academy_core
    assert Academia.list_probation_graduates_for_realm(realm.id) == []
  end

  test "a retired professor becomes emeritus, ends advising, and retains research and letter authority",
       %{realm: realm, city: city, scholar: scholar} do
    professor_fixture(scholar, realm)

    advisee = character_fixture(realm, city, "emeritus-advisee", "Emeritus Advisee")
    complete_academia_enrollment(advisee, realm)
    complete_honors_academy_core_enrollment(advisee, realm)

    assert {:ok, relationship} = Academia.set_advisor(advisee, scholar)

    probationer = character_fixture(realm, city, "emeritus-probation", "Emeritus Probation")

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

    now = ~U[2026-07-12 12:00:00Z]

    assert {:ok, %{professor: emeritus, ended_advisors: [ended_relationship]}} =
             Academia.retire_professor(scholar, now: now)

    assert emeritus.status == :retired
    assert DateTime.compare(emeritus.retired_at, now) == :eq
    assert is_nil(Academia.active_professor(scholar.id))
    assert Academia.emeritus_professor(scholar.id).id == emeritus.id
    assert Academia.professor_recommendation_authority?(scholar.id)
    assert Academia.list_active_professors_for_realm(realm.id) == []
    assert Academia.list_advisees(scholar.id) == []
    assert is_nil(Academia.active_advisor_for_student(advisee.id))

    assert ended_relationship.id == relationship.id
    assert Repo.get!(AdvisorRelationship, relationship.id).status == :ended

    assert Repo.get!(AdvisorRelationship, relationship.id).metadata["ended_reason"] ==
             "professor_retired"

    assert {:ok, %{recommendation: recommendation}} =
             Academia.issue_admission_recommendation(scholar, probationer, now: now)

    assert recommendation["professor_character_id"] == scholar.id

    assert {:ok, %{project: project}} =
             Academia.start_project(scholar, :spell, "Emeritus Field Notes",
               duration_game_days: 1
             )

    assert {:ok, %{publication: publication}} =
             Academia.complete_project_by_id(project.id, force: true)

    assert publication.publication_kind == :spell

    assert {:error, changeset} = Academia.publish_course(scholar, "Emeritus Seminar")

    assert %{publication_kind: ["character must be a professor to publish courses"]} =
             errors_on(changeset)
  end

  test "worker completes due research projects", %{scholar: scholar} do
    {:ok, %{project: project}} =
      Academia.start_project(scholar, :potion, "Potion Study", duration_game_days: 1)

    assert :ok = CompleteProjectWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
    assert Repo.get!(Project, project.id).status == :completed
  end

  test "panel votes remain open through review and resolve only once", %{
    realm: realm,
    city: city,
    scholar: scholar
  } do
    panelists =
      for {handle, name} <- [
            {"prof-one", "Professor One"},
            {"prof-two", "Professor Two"},
            {"prof-three", "Professor Three"}
          ] do
        character = character_fixture(realm, city, handle, name)
        professor_fixture(character, realm)
        character
      end

    non_panel = character_fixture(realm, city, "prof-four", "Professor Four")
    professor_fixture(non_panel, realm)

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Panel Thesis", duration_game_days: 1)

    assert {:ok, %{project: completed_project}} =
             Academia.complete_project_by_id(thesis_project.id, force: true)

    panel_ids = completed_project.metadata["defense_panel_character_ids"]
    assert Enum.sort(panel_ids) == Enum.sort(Enum.map(panelists, & &1.id))

    opens_at = completed_project.defense_scheduled_at
    closes_at = defense_closes_at(completed_project)

    assert {:error, changeset} =
             Academia.submit_defense_vote(completed_project.id, non_panel.id, :accept,
               now: opens_at
             )

    assert %{status: ["professor is not assigned to this defense panel"]} = errors_on(changeset)

    [first, second, third] = panelists

    assert {:ok, voted_project} =
             Academia.submit_defense_vote(completed_project.id, first.id, :accept, now: opens_at)

    assert voted_project.defense_state == :under_review

    assert {:error, changeset} =
             Academia.submit_defense_vote(completed_project.id, first.id, :accept, now: opens_at)

    assert %{status: ["professor has already voted on this defense"]} = errors_on(changeset)

    assert {:ok, _project} =
             Academia.submit_defense_vote(
               completed_project.id,
               second.id,
               :accept_with_revisions,
               now: opens_at
             )

    assert {:ok, _project} =
             Academia.submit_defense_vote(
               completed_project.id,
               third.id,
               :accept_with_revisions,
               now: opens_at
             )

    assert {:ok, resolved_project} =
             Academia.run_thesis_defense(completed_project.id, now: closes_at)

    assert resolved_project.defense_state == :accepted_with_revisions
    assert resolved_project.publication_id

    assert {:error, changeset} = Academia.run_thesis_defense(completed_project.id, now: closes_at)
    assert %{status: ["project is not pending defense"]} = errors_on(changeset)
  end

  test "an incomplete commission cannot resolve a thesis or grant professor eligibility", %{
    scholar: scholar
  } do
    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Unstaffed Thesis", duration_game_days: 1)

    assert {:ok, %{project: completed_project}} =
             Academia.complete_project_by_id(thesis_project.id, force: true)

    assert {:ok, pending_project} =
             Academia.run_thesis_defense(
               completed_project.id,
               now: defense_closes_at(completed_project)
             )

    assert pending_project.defense_state == :pending_defense
    assert is_nil(pending_project.publication_id)
    assert {:error, changeset} = Academia.appoint_professor(scholar)

    assert %{status: ["character must complete a thesis before becoming professor"]} =
             errors_on(changeset)
  end

  test "server-owned faculty can close a fully staffed defense without granting an empty-panel bypass",
       %{realm: realm, city: city, scholar: scholar} do
    for number <- 1..3 do
      character =
        character_fixture(
          realm,
          city,
          "npc-panel-#{number}",
          "NPC Professor #{number}"
        )

      professor_fixture(character, realm, %{"npc_faculty" => true})
    end

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Faculty Reviewed Thesis", duration_game_days: 1)

    assert {:ok, %{project: completed_project}} =
             Academia.complete_project_by_id(thesis_project.id, force: true)

    assert {:ok, resolved_project} =
             Academia.run_thesis_defense(
               completed_project.id,
               now: defense_closes_at(completed_project)
             )

    assert resolved_project.defense_state == :accepted_with_revisions
    assert resolved_project.publication_id
  end

  test "first rejection clears votes, schedules seasonal rework, and second rejection is terminal",
       %{
         realm: realm,
         city: city,
         scholar: scholar
       } do
    panelists = defense_panel_fixture(realm.id, city.id, "rework")

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Rework Thesis", duration_game_days: 1)

    assert {:ok, %{project: completed_project}} =
             Academia.complete_project_by_id(thesis_project.id, force: true)

    assert {:ok, rework_project} = resolve_thesis(completed_project, panelists, :reject)
    assert rework_project.defense_state == :pending_defense
    assert rework_project.metadata["defense_votes"] == %{}
    assert rework_project.metadata["defense_reject_count"] == 1

    expected_rework_open = Clock.arrival_at(defense_closes_at(completed_project), 84)
    assert rework_project.defense_scheduled_at == expected_rework_open
    assert is_nil(rework_project.publication_id)

    assert {:ok, rejected_project} = resolve_thesis(rework_project, panelists, :reject)
    assert rejected_project.defense_state == :rejected
    assert rejected_project.metadata["defense_reject_count"] == 2
    assert is_nil(rejected_project.publication_id)
  end

  test "a professor cannot advise themselves or vote on their own thesis", %{
    realm: realm,
    city: city,
    scholar: scholar
  } do
    professor_fixture(scholar, realm)

    assert {:error, changeset} = Academia.set_advisor(scholar, scholar)
    assert %{status: ["a professor cannot advise themselves"]} = errors_on(changeset)

    panelists = defense_panel_fixture(realm.id, city.id, "self-vote")

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Self Vote Thesis", duration_game_days: 1)

    assert {:ok, %{project: completed_project}} =
             Academia.complete_project_by_id(thesis_project.id, force: true)

    assert scholar.id not in completed_project.metadata["defense_panel_character_ids"]

    assert {:error, changeset} =
             Academia.submit_defense_vote(
               completed_project.id,
               scholar.id,
               :accept,
               now: completed_project.defense_scheduled_at
             )

    assert %{status: ["the thesis candidate cannot vote on their own defense"]} =
             errors_on(changeset)

    assert {:ok, _accepted_project} = resolve_thesis(completed_project, panelists, :accept)
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

  defp defense_panel_fixture(realm_id, location_id, prefix) do
    realm = MMGO.Worlds.get_realm!(realm_id)
    location = MMGO.Worlds.get_location!(location_id)

    for number <- 1..3 do
      character =
        character_fixture(
          realm,
          location,
          "#{prefix}-prof-#{number}",
          "#{prefix} Professor #{number}"
        )

      professor_fixture(character, realm)
      character
    end
  end

  defp resolve_thesis(project, panelists, vote) do
    opens_at = project.defense_scheduled_at

    Enum.each(panelists, fn panelist ->
      assert {:ok, _project} =
               Academia.submit_defense_vote(project.id, panelist.id, vote, now: opens_at)
    end)

    Academia.run_thesis_defense(project.id, now: defense_closes_at(project))
  end

  defp defense_closes_at(project) do
    {:ok, closes_at, _offset} = DateTime.from_iso8601(project.metadata["defense_closes_at"])
    closes_at
  end

  defp complete_academia_enrollment(character, realm) do
    %MMGO.Academy.Enrollment{}
    |> MMGO.Academy.Enrollment.changeset(%{
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

  defp begin_academia_enrollment(character, realm) do
    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :academia,
      status: :active,
      funding_type: :self_funded,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp complete_honors_academy_core_enrollment(character, realm) do
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

  defp complete_basic_enrollment(character, realm) do
    %MMGO.Academy.Enrollment{}
    |> MMGO.Academy.Enrollment.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :none,
      started_at: DateTime.utc_now(),
      expected_completion_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      metadata: %{}
    })
    |> Repo.insert!()
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
end
