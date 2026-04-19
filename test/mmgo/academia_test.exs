defmodule MMGO.AcademiaTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academia
  alias MMGO.Academia.{CompleteProjectWorker, Professor, Project, Publication}
  alias MMGO.Repo
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

    %{realm: realm, scholar: scholar, outsider: outsider}
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

  test "appoint_professor/1 requires a completed thesis publication", %{scholar: scholar} do
    assert {:error, changeset} = Academia.appoint_professor(scholar)

    assert %{status: ["character must complete a thesis before becoming professor"]} =
             errors_on(changeset)

    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Tower Thesis", duration_game_days: 1)

    {:ok, _result} = Academia.complete_project_by_id(thesis_project.id, force: true)
    {:ok, _defense} = Academia.run_thesis_defense(thesis_project.id)

    assert {:ok, %Professor{} = professor} = Academia.appoint_professor(scholar)
    assert professor.status == :active
  end

  test "publish_course/3 requires professor status", %{scholar: scholar, outsider: outsider} do
    {:ok, %{project: thesis_project}} =
      Academia.start_project(scholar, :thesis, "Tower Thesis", duration_game_days: 1)

    {:ok, _result} = Academia.complete_project_by_id(thesis_project.id, force: true)
    {:ok, _defense} = Academia.run_thesis_defense(thesis_project.id)
    {:ok, _professor} = Academia.appoint_professor(scholar)

    assert {:ok, %Publication{} = publication} = Academia.publish_course(scholar, "Battle Theory")
    assert publication.publication_kind == :course

    assert {:error, changeset} = Academia.publish_course(outsider, "Nope")

    assert %{publication_kind: ["character must be a professor to publish courses"]} =
             errors_on(changeset)
  end

  test "worker completes due research projects", %{scholar: scholar} do
    {:ok, %{project: project}} =
      Academia.start_project(scholar, :potion, "Potion Study", duration_game_days: 1)

    assert :ok = CompleteProjectWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
    assert Repo.get!(Project, project.id).status == :completed
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
end
