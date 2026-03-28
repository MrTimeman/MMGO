defmodule MMGO.Academia do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academia.{CompleteProjectWorker, Professor, Project, Publication}
  alias MMGO.Notifications
  alias MMGO.Repo
  alias MMGO.Travel.Clock

  @project_kinds [:spell, :potion, :tool, :thesis, :course]
  @publication_kinds [:spell, :potion, :tool, :thesis, :course]

  def list_projects_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from project in Project,
        where: project.character_id == ^character_id,
        order_by: [desc: project.inserted_at]
    )
  end

  def active_project(character_id) when is_binary(character_id) do
    Repo.get_by(Project, character_id: character_id, status: :active)
  end

  def list_publications(realm_id \\ nil) do
    query =
      case realm_id do
        nil -> Publication
        realm_id -> from publication in Publication, where: publication.realm_id == ^realm_id
      end

    Repo.all(from publication in query, order_by: [asc: publication.inserted_at])
  end

  def active_professor(character_id) when is_binary(character_id) do
    Repo.get_by(Professor, character_id: character_id, status: :active)
  end

  def start_project(%Character{} = character, project_kind, title, opts \\ [])
      when is_binary(title) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    duration_game_days = Keyword.get(opts, :duration_game_days, default_duration(project_kind))
    metadata = Keyword.get(opts, :metadata, %{})
    project_kind = normalize_project_kind(project_kind)

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      validate_project_start!(character, project_kind)

      completes_at = Clock.arrival_at(started_at, duration_game_days)

      project =
        %Project{}
        |> Project.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          project_kind: project_kind,
          title: title,
          status: :active,
          started_at: started_at,
          completes_at: completes_at,
          metadata: Map.put(stringify_keys(metadata), "duration_game_days", duration_game_days)
        })
        |> Repo.insert!()

      job =
        %{"project_id" => project.id}
        |> CompleteProjectWorker.new(
          schedule_in: max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{project: project, worker_job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_project_by_id(project_id, opts \\ []) when is_binary(project_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      project = lock_project!(project_id)
      character = lock_character!(project.character_id)

      cond do
        project.status != :active ->
          Repo.rollback(project_changeset("project is not active"))

        not force? and DateTime.compare(now, project.completes_at) == :lt ->
          Repo.rollback(project_changeset("project is not due yet"))

        true ->
          updated_character =
            character
            |> Character.changeset(%{xp: character.xp + project_xp(project)})
            |> Repo.update!()

          publication = publish_project!(project, now)

          updated_project =
            project
            |> Project.changeset(%{
              status: :completed,
              completed_at: now,
              publication_id: publication && publication.id
            })
            |> Repo.update!()

          _ = Notifications.notify_research_completed(updated_character, updated_project)

          %{project: updated_project, publication: publication, character: updated_character}
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_projects(now \\ DateTime.utc_now()) do
    Project
    |> where([project], project.status == :active and project.completes_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn project -> complete_project_by_id(project.id, now: now, force: true) end)
  end

  def appoint_professor(%Character{} = character) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)

      cond do
        active_professor(character.id) ->
          Repo.rollback(professor_changeset("character is already a professor"))

        not completed_thesis?(character.id) ->
          Repo.rollback(
            professor_changeset("character must complete a thesis before becoming professor")
          )

        true ->
          %Professor{}
          |> Professor.changeset(%{
            character_id: character.id,
            realm_id: character.realm_id,
            status: :active,
            appointed_at: DateTime.utc_now(),
            metadata: %{}
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
  end

  def publish_course(%Character{} = character, title, opts \\ []) when is_binary(title) do
    metadata = Keyword.get(opts, :metadata, %{})

    Repo.transaction(fn ->
      character = lock_character!(character.id)

      if is_nil(active_professor(character.id)) do
        Repo.rollback(publication_changeset("character must be a professor to publish courses"))
      end

      %Publication{}
      |> Publication.changeset(%{
        author_character_id: character.id,
        realm_id: character.realm_id,
        publication_kind: :course,
        title: title,
        code: publication_code(character.id, title, :course),
        published_at: DateTime.utc_now(),
        metadata: stringify_keys(metadata)
      })
      |> Repo.insert!()
    end)
    |> normalize_transaction_result()
  end

  defp validate_project_start!(%Character{} = character, project_kind) do
    cond do
      is_nil(project_kind) ->
        Repo.rollback(project_changeset("project kind is invalid"))

      active_project(character.id) ->
        Repo.rollback(project_changeset("character already has an active research project"))

      not completed_academia?(character.id) ->
        Repo.rollback(
          project_changeset("character must complete academia before starting research")
        )

      project_kind == :course and is_nil(active_professor(character.id)) ->
        Repo.rollback(project_changeset("only professors can research courses"))

      true ->
        :ok
    end
  end

  defp publish_project!(%Project{} = project, now) do
    %Publication{}
    |> Publication.changeset(%{
      author_character_id: project.character_id,
      realm_id: project.realm_id,
      publication_kind: normalize_publication_kind(project.project_kind),
      title: project.title,
      code: publication_code(project.character_id, project.title, project.project_kind),
      published_at: now,
      metadata: project.metadata || %{}
    })
    |> Repo.insert!()
  end

  defp completed_academia?(character_id) do
    Repo.exists?(
      from enrollment in MMGO.Academy.Enrollment,
        where:
          enrollment.character_id == ^character_id and enrollment.program_type == :academia and
            enrollment.status == :completed
    )
  end

  defp completed_thesis?(character_id) do
    Repo.exists?(
      from publication in Publication,
        where:
          publication.author_character_id == ^character_id and
            publication.publication_kind == :thesis
    )
  end

  defp project_xp(%Project{} = project) do
    max(project.metadata["duration_game_days"] || 1, 1) * 10
  end

  defp publication_code(character_id, title, kind) do
    slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-") |> String.trim("-")
    "#{kind}-#{character_id}-#{slug}"
  end

  defp normalize_project_kind(value) when value in @project_kinds, do: value
  defp normalize_project_kind("spell"), do: :spell
  defp normalize_project_kind("potion"), do: :potion
  defp normalize_project_kind("tool"), do: :tool
  defp normalize_project_kind("thesis"), do: :thesis
  defp normalize_project_kind("course"), do: :course
  defp normalize_project_kind(_value), do: nil

  defp normalize_publication_kind(kind) when kind in @publication_kinds, do: kind
  defp normalize_publication_kind(_kind), do: :spell

  defp default_duration(:spell), do: 14
  defp default_duration(:potion), do: 10
  defp default_duration(:tool), do: 12
  defp default_duration(:thesis), do: 112
  defp default_duration(:course), do: 21
  defp default_duration(_kind), do: 14

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_project!(project_id) do
    Project
    |> where([project], project.id == ^project_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp project_changeset(message) do
    %Project{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp professor_changeset(message) do
    %Professor{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp publication_changeset(message) do
    %Publication{}
    |> Changeset.change()
    |> Changeset.add_error(:publication_kind, message)
  end
end
