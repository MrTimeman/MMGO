defmodule MMGO.Academia do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character

  alias MMGO.Academia.{
    AdvisorRelationship,
    CompleteProjectWorker,
    Professor,
    ProfessorReputation,
    Project,
    Publication,
    ThesisDefenseWorker
  }

  alias MMGO.Notifications
  alias MMGO.Inventory
  alias MMGO.Progression
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

    result =
      Repo.transaction(fn ->
        project = lock_project!(project_id)
        character = lock_character!(project.character_id)

        cond do
          project.status != :active ->
            Repo.rollback(project_changeset("project is not active"))

          not force? and DateTime.compare(now, project.completes_at) == :lt ->
            Repo.rollback(project_changeset("project is not due yet"))

          true ->
            {:ok, %{character: updated_character}} =
              Progression.grant_xp(Repo, character, project_xp(project), %{
                "source" => "academia_project_completion",
                "project_id" => project.id,
                "project_kind" => to_string(project.project_kind),
                "granted_at" => now
              })

            publication =
              if project.project_kind != :thesis, do: publish_project!(project, now), else: nil

            defense_at =
              if project.project_kind == :thesis do
                MMGO.Travel.Clock.arrival_at(now, 3)
              end

            updated_project =
              project
              |> Project.changeset(%{
                status: :completed,
                completed_at: now,
                publication_id: publication && publication.id,
                defense_scheduled_at: defense_at,
                defense_state:
                  if(project.project_kind == :thesis, do: :pending_defense, else: nil)
              })
              |> Repo.update!()

            _ = Notifications.notify_research_completed(updated_character, updated_project)

            %{project: updated_project, publication: publication, character: updated_character}
        end
      end)

    case result do
      {:ok,
       %{project: %Project{project_kind: :thesis, defense_scheduled_at: defense_at} = project}} ->
        %{"project_id" => project.id}
        |> ThesisDefenseWorker.new(
          schedule_in: max(DateTime.diff(defense_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

        result

      other ->
        other
    end
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

  def set_advisor(%Character{} = student, %Character{} = professor, opts \\ []) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())

    Repo.transaction(fn ->
      student = lock_character!(student.id)
      professor = lock_character!(professor.id)

      cond do
        is_nil(active_professor(professor.id)) ->
          Repo.rollback(advisor_changeset("target character is not an active professor"))

        not is_nil(active_advisor_for_student(student.id)) ->
          Repo.rollback(advisor_changeset("student already has an active advisor"))

        student.realm_id != professor.realm_id ->
          Repo.rollback(advisor_changeset("student and professor must be in the same realm"))

        true ->
          %AdvisorRelationship{}
          |> AdvisorRelationship.changeset(%{
            professor_character_id: professor.id,
            student_character_id: student.id,
            realm_id: student.realm_id,
            status: :active,
            started_at: now,
            metadata: %{}
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
  end

  def active_advisor_for_student(student_character_id) when is_binary(student_character_id) do
    Repo.get_by(AdvisorRelationship,
      student_character_id: student_character_id,
      status: :active
    )
  end

  def list_advisees(professor_character_id) when is_binary(professor_character_id) do
    Repo.all(
      from rel in AdvisorRelationship,
        where: rel.professor_character_id == ^professor_character_id and rel.status == :active,
        preload: [:student_character]
    )
  end

  def write_recommendation_letter(%Character{} = professor, %Character{} = student, opts \\ []) do
    reason = Keyword.get(opts, :reason, "academic advancement")
    now = Keyword.get(opts, :issued_at, DateTime.utc_now())

    Repo.transaction(fn ->
      professor = lock_character!(professor.id)
      student = lock_character!(student.id)
      relationship = active_advisor_for_student(student.id)

      cond do
        is_nil(active_professor(professor.id)) ->
          Repo.rollback(advisor_changeset("author must be an active professor"))

        is_nil(relationship) or relationship.professor_character_id != professor.id ->
          Repo.rollback(advisor_changeset("student must be advised by this professor"))

        professor.realm_id != student.realm_id ->
          Repo.rollback(advisor_changeset("student and professor must be in the same realm"))

        true ->
          template = recommendation_letter_template!()

          {:ok, inventory_item} =
            Inventory.grant_item(student, template, %{
              quantity: 1,
              metadata: %{
                "professor_character_id" => professor.id,
                "student_character_id" => student.id,
                "reason" => reason,
                "issued_at" => DateTime.to_iso8601(now),
                "non_transferable" => true
              }
            })

          relationship
          |> AdvisorRelationship.changeset(%{
            metadata: Map.update(relationship.metadata || %{}, "letters_issued", 1, &(&1 + 1))
          })
          |> Repo.update!()

          inventory_item
      end
    end)
    |> normalize_transaction_result()
  end

  def get_reputation(professor_character_id, realm_id)
      when is_binary(professor_character_id) and is_binary(realm_id) do
    Repo.get_by(ProfessorReputation,
      professor_character_id: professor_character_id,
      realm_id: realm_id
    )
  end

  def adjust_reputation(professor_character_id, realm_id, delta, reason \\ nil)
      when is_binary(professor_character_id) and is_integer(delta) do
    Repo.transaction(fn ->
      reputation =
        case get_reputation(professor_character_id, realm_id) do
          nil ->
            %ProfessorReputation{}
            |> ProfessorReputation.changeset(%{
              professor_character_id: professor_character_id,
              realm_id: realm_id,
              score: 0,
              metadata: %{}
            })
            |> Repo.insert!()

          existing ->
            existing
        end

      metadata =
        if reason,
          do: Map.put(reputation.metadata || %{}, "last_reason", reason),
          else: reputation.metadata

      reputation
      |> ProfessorReputation.changeset(%{
        score: max(reputation.score + delta, 0),
        metadata: metadata
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def schedule_thesis_defense(project_id, opts \\ []) when is_binary(project_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    defense_game_days = Keyword.get(opts, :defense_game_days, 3)

    Repo.transaction(fn ->
      project =
        Project
        |> where([p], p.id == ^project_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      cond do
        project.project_kind != :thesis ->
          Repo.rollback(project_changeset("only thesis projects require a defense"))

        project.status != :completed ->
          Repo.rollback(project_changeset("project must be completed to schedule defense"))

        not is_nil(project.defense_scheduled_at) ->
          Repo.rollback(project_changeset("defense is already scheduled"))

        true ->
          defense_at = MMGO.Travel.Clock.arrival_at(now, defense_game_days)

          updated_project =
            project
            |> Project.changeset(%{
              defense_scheduled_at: defense_at,
              defense_state: :pending_defense
            })
            |> Repo.update!()

          job =
            %{"project_id" => project_id}
            |> ThesisDefenseWorker.new(
              schedule_in: max(DateTime.diff(defense_at, DateTime.utc_now(), :second), 0)
            )
            |> Oban.insert!()

          %{project: updated_project, job: job}
      end
    end)
    |> normalize_transaction_result()
  end

  def run_thesis_defense(project_id, opts \\ []) when is_binary(project_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      project =
        Project
        |> where([p], p.id == ^project_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      cond do
        project.defense_state != :pending_defense ->
          Repo.rollback(project_changeset("project is not pending defense"))

        true ->
          votes = Map.get(project.metadata || %{}, "defense_votes", %{})
          outcome = tally_defense_votes(votes)

          reject_count =
            Map.get(project.metadata || %{}, "defense_reject_count", 0)

          {new_state, new_reject_count} =
            case outcome do
              :accept -> {:accepted, reject_count}
              :accept_with_revisions -> {:accepted_with_revisions, reject_count}
              :reject when reject_count + 1 >= 2 -> {:rejected, reject_count + 1}
              :reject -> {:pending_defense, reject_count + 1}
            end

          updated_project =
            project
            |> Project.changeset(%{
              defense_state: new_state,
              metadata:
                Map.merge(project.metadata || %{}, %{
                  "defense_outcome" => to_string(outcome),
                  "defense_completed_at" => DateTime.to_iso8601(now),
                  "defense_reject_count" => new_reject_count
                })
            })
            |> Repo.update!()

          if new_state == :accepted or new_state == :accepted_with_revisions do
            maybe_adjust_advisor_reputation(
              project.character_id,
              project.realm_id,
              +5,
              "thesis_accepted"
            )
          end

          if new_state == :rejected do
            maybe_adjust_advisor_reputation(
              project.character_id,
              project.realm_id,
              -5,
              "thesis_rejected"
            )
          end

          updated_project
      end
    end)
    |> normalize_transaction_result()
  end

  def submit_defense_vote(project_id, professor_character_id, vote, opts \\ [])
      when vote in [:accept, :accept_with_revisions, :reject] do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      project =
        Project
        |> where([p], p.id == ^project_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      cond do
        project.defense_state != :pending_defense ->
          Repo.rollback(project_changeset("defense is not open for voting"))

        is_nil(active_professor(professor_character_id)) ->
          Repo.rollback(project_changeset("only professors can vote on defenses"))

        true ->
          existing_votes = Map.get(project.metadata || %{}, "defense_votes", %{})

          updated_votes =
            Map.put(existing_votes, professor_character_id, %{
              "vote" => to_string(vote),
              "voted_at" => DateTime.to_iso8601(now)
            })

          project
          |> Project.changeset(%{
            defense_state: :under_review,
            metadata: Map.put(project.metadata || %{}, "defense_votes", updated_votes)
          })
          |> Repo.update!()
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
      from project in Project,
        where:
          project.character_id == ^character_id and project.project_kind == :thesis and
            project.defense_state in [:accepted, :accepted_with_revisions]
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

  defp advisor_changeset(message) do
    %AdvisorRelationship{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp recommendation_letter_template! do
    case Enum.find(Inventory.list_item_templates(), &(&1.code == "recommendation_letter")) do
      nil ->
        {:ok, template} =
          Inventory.create_item_template(%{
            code: "recommendation_letter",
            name: "Recommendation Letter",
            item_type: :tool,
            description:
              "A sealed academic recommendation intended for restricted academic gates.",
            stackable: true,
            weight: 1,
            max_durability: 0,
            nutrition_units: 0,
            tags: ["academic", "non_transferable"],
            actions: [
              %{
                key: "present",
                action_kind: :repair,
                targeting: :self,
                quantity_cost: 1,
                effects: [
                  %{
                    applies_to: :caster,
                    state: "empowered",
                    intensity: 1,
                    variance: 0,
                    duration: 1
                  }
                ]
              }
            ]
          })

        template

      template ->
        template
    end
  end

  defp tally_defense_votes(votes) when map_size(votes) == 0, do: :accept

  defp tally_defense_votes(votes) do
    counts =
      votes
      |> Map.values()
      |> Enum.frequencies_by(& &1["vote"])

    accepts = Map.get(counts, "accept", 0)
    revisions = Map.get(counts, "accept_with_revisions", 0)
    rejects = Map.get(counts, "reject", 0)
    total = accepts + revisions + rejects

    cond do
      total == 0 -> :accept
      rejects > total / 2 -> :reject
      revisions > accepts -> :accept_with_revisions
      true -> :accept
    end
  end

  defp maybe_adjust_advisor_reputation(student_character_id, realm_id, delta, reason) do
    case Repo.get_by(AdvisorRelationship,
           student_character_id: student_character_id,
           status: :active
         ) do
      nil ->
        :ok

      relationship ->
        adjust_reputation(relationship.professor_character_id, realm_id, delta, reason)
    end
  end
end
