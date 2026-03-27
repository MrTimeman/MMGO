defmodule MMGO.AcademyTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Academy.{CompleteEnrollmentWorker, Enrollment}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    character = character_fixture(realm, "student", "Student")

    %{realm: realm, character: character}
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

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :new, level: 1, xp: 0})
    |> Repo.insert!()
  end
end

defmodule AcademyTestHelpers do
  alias MMGO.Travel.Clock

  def expected_completion(started_at, duration_game_days) do
    Clock.arrival_at(started_at, duration_game_days)
  end
end
