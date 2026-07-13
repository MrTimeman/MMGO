defmodule MMGO.Academia do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Academy.{Course, Enrollment}
  alias MMGO.Clubs
  alias MMGO.Economy

  alias MMGO.Academia.{
    AdvisorRelationship,
    CompleteProjectWorker,
    Headship,
    Professor,
    ProfessorReputation,
    Project,
    Publication,
    ThesisDefenseWorker
  }

  alias MMGO.Notifications
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  @project_kinds [:spell, :potion, :tool, :thesis, :course]
  @publication_kinds [:spell, :potion, :tool, :thesis, :course]
  @thesis_opening_game_days 3
  @thesis_window_game_days 1
  @thesis_rework_game_days 84
  @advisor_speed_bonus_percent 20
  @academy_curriculum_metadata_key "academy_curriculum"
  @academy_curriculum_overrides_key "overrides"
  @academy_curriculum_override_version 1

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

  def emeritus_professor(character_id) when is_binary(character_id) do
    Repo.one(
      from professor in Professor,
        where: professor.character_id == ^character_id and professor.status == :retired,
        order_by: [desc: professor.retired_at, desc: professor.id],
        limit: 1
    )
  end

  def emeritus_professor(_character_id), do: nil

  @doc "Returns whether a Professor or Researcher Emeritus may issue admission letters."
  def professor_recommendation_authority?(character_id) when is_binary(character_id) do
    not is_nil(active_professor(character_id)) or not is_nil(emeritus_professor(character_id))
  end

  def professor_recommendation_authority?(_character_id), do: false

  def list_active_professors_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from professor in Professor,
        where: professor.realm_id == ^realm_id and professor.status == :active,
        order_by: [asc: professor.appointed_at, asc: professor.id],
        preload: [:character]
    )
  end

  def list_active_professors_for_realm(_realm_id), do: []

  @doc "Lists realm-local Basic Education graduates who need a professor's admission letter."
  def list_probation_graduates_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from enrollment in Enrollment,
        where:
          enrollment.realm_id == ^realm_id and enrollment.program_type == :basic_education and
            enrollment.status == :completed,
        order_by: [asc: enrollment.completed_at, asc: enrollment.id],
        preload: [:character]
    )
    |> Enum.filter(&probation_enrollment?/1)
    |> Enum.reject(&active_academy_core_admission_clearance?/1)
    |> Enum.map(&%{character: &1.character, enrollment: &1})
  end

  def list_probation_graduates_for_realm(_realm_id), do: []

  @doc "Lists active Academy Core grant students who have not received a charity stipend."
  def list_charity_stipend_candidates_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from enrollment in Enrollment,
        where:
          enrollment.realm_id == ^realm_id and enrollment.program_type == :academy_core and
            enrollment.status == :active and enrollment.funding_type == :grant,
        order_by: [asc: enrollment.started_at, asc: enrollment.id],
        preload: [:character]
    )
    |> Enum.filter(fn enrollment ->
      enrollment.character.status == :active and is_nil(Academy.charity_stipend(enrollment))
    end)
    |> Enum.map(&%{character: &1.character, enrollment: &1})
  end

  def list_charity_stipend_candidates_for_realm(_realm_id), do: []

  @doc "Issues one non-transferable Academy Core admission recommendation to a probation graduate."
  def issue_admission_recommendation(
        %Character{} = professor,
        %Character{} = candidate,
        opts \\ []
      ) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      professor = lock_character!(professor.id)
      candidate = lock_character!(candidate.id)

      basic_enrollment =
        Enrollment
        |> where(
          [enrollment],
          enrollment.character_id == ^candidate.id and
            enrollment.program_type == :basic_education and enrollment.status == :completed
        )
        |> order_by([enrollment], desc: enrollment.completed_at, desc: enrollment.inserted_at)
        |> limit(1)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        professor.id == candidate.id ->
          Repo.rollback(recommendation_changeset("a professor cannot recommend themselves"))

        not professor_recommendation_authority?(professor.id) ->
          Repo.rollback(
            recommendation_changeset(
              "only an active professor or Researcher Emeritus can issue a recommendation"
            )
          )

        professor.realm_id != candidate.realm_id ->
          Repo.rollback(
            recommendation_changeset("student and professor must be in the same realm")
          )

        is_nil(basic_enrollment) ->
          Repo.rollback(
            recommendation_changeset("student has no completed basic education record")
          )

        not probation_enrollment?(basic_enrollment) ->
          Repo.rollback(
            recommendation_changeset("student does not need a probation recommendation")
          )

        active_academy_core_admission_clearance?(basic_enrollment) ->
          Repo.rollback(recommendation_changeset("student already has an active recommendation"))

        true ->
          recommendation = %{
            "status" => "active",
            "purpose" => "academy_core_admission",
            "professor_character_id" => professor.id,
            "issued_at" => DateTime.to_iso8601(now),
            "non_transferable" => true
          }

          updated_enrollment =
            basic_enrollment
            |> Enrollment.changeset(%{
              metadata:
                Map.put(
                  basic_enrollment.metadata || %{},
                  "professor_recommendation",
                  recommendation
                )
            })
            |> Repo.update!()

          %{enrollment: updated_enrollment, recommendation: recommendation}
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns a presentation-safe Academy Head election state for one realm."
  def academy_head_state(realm_or_id, opts \\ []), do: Headship.state(realm_or_id, opts)

  @doc "Lets an active professor open the next due Academy Head election."
  def open_academy_head_election(professor, opts \\ [])

  def open_academy_head_election(%Character{} = professor, opts),
    do: Headship.open_election(professor, opts)

  def open_academy_head_election(_professor, _opts),
    do: {:error, professor_changeset("Academy Head election is unavailable")}

  @doc "Records one professor's vote in a realm-local Academy Head election."
  def cast_academy_head_vote(professor, candidate_character_id, opts \\ [])

  def cast_academy_head_vote(%Character{} = professor, candidate_character_id, opts)
      when is_binary(candidate_character_id),
      do: Headship.cast_vote(professor, candidate_character_id, opts)

  def cast_academy_head_vote(_professor, _candidate_character_id, _opts),
    do: {:error, professor_changeset("Academy Head vote is unavailable")}

  @doc "Settles an expired Academy Head election through an eligible professor."
  def settle_academy_head_election(professor, opts \\ [])

  def settle_academy_head_election(%Character{} = professor, opts),
    do: Headship.settle_election(professor, opts)

  def settle_academy_head_election(_professor, _opts),
    do: {:error, professor_changeset("Academy Head election settlement is unavailable")}

  @doc "Lets the current Academy Head directly admit one realm-local probation graduate."
  def issue_academy_head_admission(head, candidate, opts \\ [])

  def issue_academy_head_admission(
        %Character{} = head,
        %Character{} = candidate,
        opts
      ) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      _realm = lock_realm!(head.realm_id)
      head = lock_character!(head.id)
      candidate = lock_character!(candidate.id)

      basic_enrollment =
        Enrollment
        |> where(
          [enrollment],
          enrollment.character_id == ^candidate.id and
            enrollment.program_type == :basic_education and enrollment.status == :completed
        )
        |> order_by([enrollment], desc: enrollment.completed_at, desc: enrollment.inserted_at)
        |> limit(1)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        not Headship.current_head?(head, now: now) ->
          Repo.rollback(
            recommendation_changeset(
              "only the current Academy Head may admit probation graduates"
            )
          )

        head.id == candidate.id ->
          Repo.rollback(recommendation_changeset("Academy Head cannot admit themselves"))

        head.realm_id != candidate.realm_id ->
          Repo.rollback(
            recommendation_changeset("Academy Head and student must be in the same realm")
          )

        is_nil(basic_enrollment) ->
          Repo.rollback(
            recommendation_changeset("student has no completed basic education record")
          )

        not probation_enrollment?(basic_enrollment) ->
          Repo.rollback(recommendation_changeset("student does not need a probation admission"))

        active_academy_core_admission_clearance?(basic_enrollment) ->
          Repo.rollback(
            recommendation_changeset("student already has an active admission clearance")
          )

        true ->
          admission = %{
            "status" => "active",
            "purpose" => "academy_core_admission",
            "head_character_id" => head.id,
            "issued_at" => DateTime.to_iso8601(now),
            "non_transferable" => true
          }

          updated_enrollment =
            basic_enrollment
            |> Enrollment.changeset(%{
              metadata:
                Map.put(
                  basic_enrollment.metadata || %{},
                  "academy_head_admission",
                  admission
                )
            })
            |> Repo.update!()

          %{enrollment: updated_enrollment, admission: admission}
      end
    end)
    |> normalize_transaction_result()
  end

  def issue_academy_head_admission(_head, _candidate, _opts),
    do: {:error, recommendation_changeset("Academy Head admission is unavailable")}

  @doc "Pays one real charity stipend to an eligible Academy Core grant student."
  def award_academy_head_charity_stipend(head, candidate, amount, opts \\ [])

  def award_academy_head_charity_stipend(
        %Character{} = head,
        %Character{} = candidate,
        amount,
        opts
      )
      when is_integer(amount) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(head.realm_id)
      head = lock_character!(head.id)
      candidate = lock_character!(candidate.id)
      enrollment = lock_current_enrollment!(candidate.id)

      cond do
        amount <= 0 ->
          Repo.rollback(
            recommendation_changeset("charity stipend amount must be greater than zero")
          )

        not Headship.current_head?(head, now: now) ->
          Repo.rollback(
            recommendation_changeset(
              "only the current Academy Head may allocate charity stipends"
            )
          )

        head.id == candidate.id ->
          Repo.rollback(
            recommendation_changeset("Academy Head cannot award a stipend to themselves")
          )

        head.realm_id != candidate.realm_id ->
          Repo.rollback(
            recommendation_changeset("Academy Head and student must be in the same realm")
          )

        candidate.status != :active ->
          Repo.rollback(recommendation_changeset("charity stipend recipient must be active"))

        is_nil(enrollment) ->
          Repo.rollback(
            recommendation_changeset("student does not have an active Academy Core enrollment")
          )

        enrollment.program_type != :academy_core or enrollment.funding_type != :grant ->
          Repo.rollback(
            recommendation_changeset("charity stipend requires Academy Core grant funding")
          )

        not is_nil(Academy.charity_stipend(enrollment)) ->
          Repo.rollback(
            recommendation_changeset(
              "student has already received a charity stipend for this enrollment"
            )
          )

        true ->
          with {:ok, charity_account} <- Economy.ensure_charity_fund_account(realm),
               {:ok, recipient_account} <- Economy.ensure_character_account(candidate),
               {:ok, transfer} <-
                 Economy.transfer(charity_account, recipient_account, amount, %{
                   entry_type: "reward",
                   source: "academy_charity_stipend",
                   head_character_id: head.id,
                   recipient_character_id: candidate.id,
                   enrollment_id: enrollment.id
                 }) do
            ledger_entry = List.first(transfer.ledger_entries)

            receipt = %{
              "status" => "paid",
              "purpose" => "academy_core_stipend",
              "amount" => amount,
              "head_character_id" => head.id,
              "fund_account_id" => transfer.debit_account.id,
              "ledger_entry_id" => ledger_entry.id,
              "paid_at" => DateTime.to_iso8601(now),
              "non_transferable" => true
            }

            updated_enrollment =
              enrollment
              |> Enrollment.changeset(%{
                metadata: Map.put(enrollment.metadata || %{}, "charity_stipend", receipt)
              })
              |> Repo.update!()

            %{
              enrollment: updated_enrollment,
              stipend: receipt,
              transfer: transfer,
              charity_account: transfer.debit_account
            }
          else
            {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def award_academy_head_charity_stipend(_head, _candidate, _amount, _opts),
    do: {:error, recommendation_changeset("Academy Head charity stipend is unavailable")}

  @doc """
  Lets the current Academy Head reschedule one active seeded course within its
  program's legal term range. The schedule is a realm metadata overlay, so it
  never rewrites the seeded course identity or an existing enrollment.
  """
  def set_academy_head_curriculum_override(head, seeded_course, target_term, opts \\ [])

  def set_academy_head_curriculum_override(
        %Character{} = head,
        %Course{id: course_id},
        target_term,
        opts
      )
      when is_binary(course_id) and is_integer(target_term) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(head.realm_id)
      head = lock_character!(head.id)
      course = lock_course!(course_id)

      cond do
        not Headship.current_head?(head, now: now) ->
          Repo.rollback(
            curriculum_changeset("only the current Academy Head may override the curriculum")
          )

        head.realm_id != course.realm_id ->
          Repo.rollback(curriculum_changeset("Academy Head and course must be in the same realm"))

        course.source not in [:seeded, "seeded"] ->
          Repo.rollback(curriculum_changeset("only seeded courses may be rescheduled"))

        course.status != :active ->
          Repo.rollback(curriculum_changeset("only active courses may be rescheduled"))

        not Academy.curriculum_term_allowed?(course, target_term) ->
          Repo.rollback(
            curriculum_changeset("course cannot be scheduled for that curriculum term")
          )

        true ->
          override = curriculum_override(head, target_term, now)

          updated_realm =
            realm
            |> Realm.changeset(%{
              metadata:
                put_curriculum_override(
                  realm.metadata,
                  course.id,
                  override
                )
            })
            |> Repo.update!()

          %{realm: updated_realm, course: course, override: override}
      end
    end)
    |> normalize_transaction_result()
  end

  def set_academy_head_curriculum_override(_head, _seeded_course, _target_term, _opts),
    do: {:error, curriculum_changeset("Academy Head curriculum override is unavailable")}

  @doc "Restores an active seeded course to its original schedule."
  def clear_academy_head_curriculum_override(head, seeded_course, opts \\ [])

  def clear_academy_head_curriculum_override(
        %Character{} = head,
        %Course{id: course_id},
        opts
      )
      when is_binary(course_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      realm = lock_realm!(head.realm_id)
      head = lock_character!(head.id)
      course = lock_course!(course_id)

      cond do
        not Headship.current_head?(head, now: now) ->
          Repo.rollback(
            curriculum_changeset("only the current Academy Head may restore the curriculum")
          )

        head.realm_id != course.realm_id ->
          Repo.rollback(curriculum_changeset("Academy Head and course must be in the same realm"))

        course.source not in [:seeded, "seeded"] ->
          Repo.rollback(curriculum_changeset("only seeded courses have a base curriculum"))

        course.status != :active ->
          Repo.rollback(curriculum_changeset("only active courses may be restored"))

        not Map.has_key?(curriculum_overrides(realm.metadata), course.id) ->
          Repo.rollback(curriculum_changeset("course does not have a curriculum override"))

        true ->
          updated_realm =
            realm
            |> Realm.changeset(%{
              metadata: clear_curriculum_override(realm.metadata, course.id)
            })
            |> Repo.update!()

          %{realm: updated_realm, course: course}
      end
    end)
    |> normalize_transaction_result()
  end

  def clear_academy_head_curriculum_override(_head, _seeded_course, _opts),
    do: {:error, curriculum_changeset("Academy Head curriculum restore is unavailable")}

  @doc """
  Returns the persisted, public-facing thesis-defense record and its frozen
  commission. Callers still authorize the viewer separately; this function
  never grants a character permission to vote.
  """
  def thesis_defense(project_id) when is_binary(project_id) do
    case Repo.get(Project, project_id) do
      %Project{project_kind: :thesis} = project ->
        panel_ids = defense_panel_character_ids(project)

        panel_by_id =
          Character
          |> where([character], character.id in ^panel_ids)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        {:ok,
         %{
           project: project,
           candidate: Repo.get!(Character, project.character_id),
           panel: Enum.flat_map(panel_ids, &List.wrap(Map.get(panel_by_id, &1))),
           votes: defense_votes(project),
           opens_at: project.defense_scheduled_at,
           closes_at: defense_closes_at(project)
         }}

      _other ->
        {:error, :thesis_defense_not_found}
    end
  end

  def list_open_thesis_defenses_for_realm(realm_id) when is_binary(realm_id) do
    Repo.all(
      from project in Project,
        where:
          project.realm_id == ^realm_id and project.project_kind == :thesis and
            project.defense_state in [:pending_defense, :under_review],
        order_by: [asc: project.defense_scheduled_at, asc: project.inserted_at],
        preload: [:character]
    )
  end

  def list_open_thesis_defenses_for_realm(_realm_id), do: []

  def start_project(%Character{} = character, project_kind, title, opts \\ [])
      when is_binary(title) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    duration_game_days = Keyword.get(opts, :duration_game_days, default_duration(project_kind))
    metadata = Keyword.get(opts, :metadata, %{})
    project_kind = normalize_project_kind(project_kind)

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      validate_project_start!(character, project_kind)

      advisor = active_advisor_for_student(character.id)

      effective_duration_game_days =
        advisor_adjusted_duration(duration_game_days, advisor, character)

      completes_at = Clock.arrival_at(started_at, effective_duration_game_days)

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
          metadata:
            project_metadata(
              metadata,
              duration_game_days,
              effective_duration_game_days,
              advisor
            )
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
            completion_xp = project_xp(project)

            {:ok, %{character: updated_character}} =
              Progression.grant_xp(Repo, character, completion_xp, %{
                "source" => "academia_project_completion",
                "project_id" => project.id,
                "project_kind" => to_string(project.project_kind),
                "granted_at" => now
              })

            publication =
              if project.project_kind != :thesis, do: publish_project!(project, now), else: nil

            {defense_at, defense_metadata} =
              if project.project_kind == :thesis do
                defense_at = Clock.arrival_at(now, @thesis_opening_game_days)

                {defense_at, defense_metadata(project, defense_at, build_defense_panel(project))}
              else
                {nil, project.metadata || %{}}
              end

            research_rewards =
              if project.project_kind != :thesis do
                case Clubs.reward_research_contributors(project, completion_xp, now: now) do
                  {:ok, rewards} -> rewards
                  {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
                end
              else
                []
              end

            project_metadata =
              if research_rewards == [] do
                defense_metadata
              else
                Map.put(defense_metadata, "club_research_rewards", research_rewards)
              end

            updated_project =
              project
              |> Project.changeset(%{
                status: :completed,
                completed_at: now,
                publication_id: publication && publication.id,
                defense_scheduled_at: defense_at,
                defense_state:
                  if(project.project_kind == :thesis, do: :pending_defense, else: nil),
                metadata: project_metadata
              })
              |> Repo.update!()

            defense_worker =
              if updated_project.project_kind == :thesis do
                schedule_thesis_defense_worker!(updated_project)
              end

            _ = Notifications.notify_research_completed(updated_character, updated_project)

            %{
              project: updated_project,
              publication: publication,
              character: updated_character,
              defense_worker: defense_worker,
              research_rewards: research_rewards
            }
        end
      end)

    result
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

  @doc "Lets an active Professor retire into the Researcher Emeritus role."
  def retire_professor(character, opts \\ [])

  def retire_professor(%Character{} = character, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      _realm = lock_realm!(character.realm_id)
      character = lock_character!(character.id)
      professor = lock_active_professor(character.id)

      if is_nil(professor) do
        Repo.rollback(professor_changeset("character is not an active professor"))
      end

      updated_professor =
        professor
        |> Professor.changeset(%{status: :retired, retired_at: now})
        |> Repo.update!()

      ended_advisors = end_active_advisor_relationships!(character.id, now)

      headship =
        case Headship.vacate_for_retirement(character, now: now) do
          {:ok, headship} -> headship
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end

      %{professor: updated_professor, ended_advisors: ended_advisors, headship: headship}
    end)
    |> normalize_transaction_result()
  end

  def retire_professor(_character, _opts),
    do: {:error, professor_changeset("Researcher Emeritus retirement is unavailable")}

  def set_advisor(%Character{} = student, %Character{} = professor, opts \\ []) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())

    Repo.transaction(fn ->
      student = lock_character!(student.id)
      professor = lock_character!(professor.id)

      cond do
        student.id == professor.id ->
          Repo.rollback(advisor_changeset("a professor cannot advise themselves"))

        not academia_admitted?(student.id) ->
          Repo.rollback(
            advisor_changeset("student must enter academia before choosing an advisor")
          )

        not advisor_pick_eligible?(student.id) ->
          Repo.rollback(
            advisor_changeset("only top Academy Core graduates may request a specific advisor")
          )

        is_nil(active_professor(professor.id)) ->
          Repo.rollback(advisor_changeset("target character is not an active professor"))

        not is_nil(active_advisor_for_student(student.id)) ->
          Repo.rollback(advisor_changeset("student already has an active advisor"))

        student.realm_id != professor.realm_id ->
          Repo.rollback(advisor_changeset("student and professor must be in the same realm"))

        true ->
          create_advisor_relationship!(student, professor.id, now, %{
            "assignment" => "honors_request",
            "requested_at" => DateTime.to_iso8601(now)
          })
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Matches an admitted student to the least-loaded active professor in their realm."
  def match_advisor(%Character{} = student, opts \\ []) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())

    Repo.transaction(fn ->
      student = lock_character!(student.id)

      cond do
        not academia_admitted?(student.id) ->
          Repo.rollback(
            advisor_changeset("student must enter academia before receiving an advisor")
          )

        not is_nil(active_advisor_for_student(student.id)) ->
          Repo.rollback(advisor_changeset("student already has an active advisor"))

        true ->
          case matched_professor_for(student) do
            nil ->
              Repo.rollback(advisor_changeset("no active professor is available in this realm"))

            %Professor{} = professor ->
              create_advisor_relationship!(student, professor.character_id, now, %{
                "assignment" => "availability_match",
                "matched_at" => DateTime.to_iso8601(now)
              })
          end
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns whether a character has entered or completed the Academia program."
  def academia_admitted?(character_id) when is_binary(character_id) do
    Repo.exists?(
      from enrollment in Enrollment,
        where:
          enrollment.character_id == ^character_id and enrollment.program_type == :academia and
            enrollment.status in [:active, :completed]
    )
  end

  def academia_admitted?(_character_id), do: false

  @doc "Returns whether the character can request a specific professor under the cohort rule."
  def advisor_pick_eligible?(character_id) when is_binary(character_id),
    do: Academy.advisor_pick_eligible?(character_id)

  def advisor_pick_eligible?(_character_id), do: false

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

  defp end_active_advisor_relationships!(professor_character_id, now) do
    AdvisorRelationship
    |> where(
      [relationship],
      relationship.professor_character_id == ^professor_character_id and
        relationship.status == :active
    )
    |> order_by([relationship], asc: relationship.id)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.map(fn relationship ->
      relationship
      |> AdvisorRelationship.changeset(%{
        status: :ended,
        ended_at: now,
        metadata: Map.put(relationship.metadata || %{}, "ended_reason", "professor_retired")
      })
      |> Repo.update!()
    end)
  end

  defp create_advisor_relationship!(%Character{} = student, professor_character_id, now, metadata) do
    %AdvisorRelationship{}
    |> AdvisorRelationship.changeset(%{
      professor_character_id: professor_character_id,
      student_character_id: student.id,
      realm_id: student.realm_id,
      status: :active,
      started_at: now,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  defp matched_professor_for(%Character{} = student) do
    advisor_counts =
      Repo.all(
        from relationship in AdvisorRelationship,
          where: relationship.realm_id == ^student.realm_id and relationship.status == :active,
          group_by: relationship.professor_character_id,
          select: {relationship.professor_character_id, count(relationship.id)}
      )
      |> Map.new()

    student.realm_id
    |> list_active_professors_for_realm()
    |> Enum.reject(&(&1.character_id == student.id))
    |> Enum.min_by(
      fn professor ->
        {
          Map.get(advisor_counts, professor.character_id, 0),
          DateTime.to_unix(professor.appointed_at, :microsecond),
          professor.id
        }
      end,
      fn -> nil end
    )
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
    defense_game_days = Keyword.get(opts, :defense_game_days, @thesis_opening_game_days)

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
          defense_at = Clock.arrival_at(now, defense_game_days)
          defense_metadata = defense_metadata(project, defense_at, build_defense_panel(project))

          updated_project =
            project
            |> Project.changeset(%{
              defense_scheduled_at: defense_at,
              defense_state: :pending_defense,
              metadata: defense_metadata
            })
            |> Repo.update!()

          job = schedule_thesis_defense_worker!(updated_project)

          %{project: updated_project, job: job}
      end
    end)
    |> normalize_transaction_result()
  end

  def run_thesis_defense(project_id, opts \\ []) when is_binary(project_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    result =
      Repo.transaction(fn ->
        project =
          Project
          |> where([p], p.id == ^project_id)
          |> lock("FOR UPDATE")
          |> Repo.one!()

        cond do
          project.defense_state not in [:pending_defense, :under_review] ->
            Repo.rollback(project_changeset("project is not pending defense"))

          true ->
            project = refresh_defense_panel!(project)
            closes_at = defense_closes_at(project)

            if DateTime.compare(now, closes_at) == :lt do
              Repo.rollback({:defense_not_closed, closes_at})
            end

            project = cast_npc_panel_votes!(project, now)

            case defense_resolution_status(project) do
              :awaiting_panel ->
                %{project: extend_defense_window!(project, now), resolution: :awaiting_panel}

              :awaiting_votes ->
                %{project: extend_defense_window!(project, now), resolution: :awaiting_votes}

              {:ready, votes} ->
                resolve_thesis_defense!(project, votes, now)
            end
        end
      end)

    case result do
      {:ok, %{project: project}} -> {:ok, project}
      other -> normalize_transaction_result(other)
    end
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

      project = refresh_defense_panel!(project)
      professor = active_professor(professor_character_id)

      cond do
        project.defense_state not in [:pending_defense, :under_review] ->
          Repo.rollback(project_changeset("defense is not open for voting"))

        not defense_vote_window_open?(project, now) ->
          Repo.rollback(project_changeset("defense is not open for voting at this time"))

        not valid_defense_panel?(project) ->
          Repo.rollback(
            project_changeset("defense requires a commission of three active professors")
          )

        professor_character_id == project.character_id ->
          Repo.rollback(
            project_changeset("the thesis candidate cannot vote on their own defense")
          )

        is_nil(professor) or professor.realm_id != project.realm_id ->
          Repo.rollback(project_changeset("only professors from this realm can vote on defenses"))

        professor_character_id not in defense_panel_character_ids(project) ->
          Repo.rollback(project_changeset("professor is not assigned to this defense panel"))

        Map.has_key?(
          defense_votes(project),
          professor_character_id
        ) ->
          Repo.rollback(project_changeset("professor has already voted on this defense"))

        true ->
          existing_votes = defense_votes(project)

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
    track = Keyword.get(opts, :track)
    school = Keyword.get(opts, :school)
    syllabus = Keyword.get(opts, :syllabus, %{})

    Repo.transaction(fn ->
      character = lock_character!(character.id)

      if is_nil(active_professor(character.id)) do
        Repo.rollback(publication_changeset("character must be a professor to publish courses"))
      end

      publication =
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

      %Course{}
      |> Course.changeset(%{
        realm_id: character.realm_id,
        publication_id: publication.id,
        source: :published,
        title: title,
        track: track,
        school: school,
        syllabus: stringify_keys(syllabus),
        status: :active,
        metadata: stringify_keys(metadata)
      })
      |> Repo.insert!()

      publication
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
    max(
      project.metadata["base_duration_game_days"] || project.metadata["duration_game_days"] || 1,
      1
    ) * 10
  end

  defp advisor_adjusted_duration(
         duration_game_days,
         %AdvisorRelationship{} = advisor,
         %Character{} = character
       )
       when advisor.realm_id == character.realm_id do
    case active_professor(advisor.professor_character_id) do
      %Professor{realm_id: realm_id, status: :active} when realm_id == character.realm_id ->
        div(
          duration_game_days * 100 + (100 + @advisor_speed_bonus_percent) - 1,
          100 + @advisor_speed_bonus_percent
        )
        |> max(1)

      _other ->
        duration_game_days
    end
  end

  defp advisor_adjusted_duration(duration_game_days, _advisor, _character), do: duration_game_days

  defp project_metadata(metadata, base_duration_game_days, effective_duration_game_days, advisor) do
    metadata =
      metadata
      |> stringify_keys()
      |> Map.put("duration_game_days", effective_duration_game_days)
      |> Map.put("base_duration_game_days", base_duration_game_days)

    case advisor do
      %AdvisorRelationship{} ->
        metadata
        |> Map.put("advisor_character_id", advisor.professor_character_id)
        |> Map.put("advisor_speed_bonus_percent", @advisor_speed_bonus_percent)

      _other ->
        metadata
    end
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

  defp lock_realm!(realm_id) do
    Realm
    |> where([realm], realm.id == ^realm_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_course!(course_id) do
    Course
    |> where([course], course.id == ^course_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_project!(project_id) do
    Project
    |> where([project], project.id == ^project_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_active_professor(character_id) do
    Professor
    |> where([professor], professor.character_id == ^character_id and professor.status == :active)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp lock_current_enrollment!(character_id) do
    Enrollment
    |> where(
      [enrollment],
      enrollment.character_id == ^character_id and enrollment.status == :active
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp curriculum_override(%Character{} = head, target_term, now) do
    %{
      "version" => @academy_curriculum_override_version,
      "years" => [target_term],
      "head_character_id" => head.id,
      "set_at" => DateTime.to_iso8601(now)
    }
  end

  defp put_curriculum_override(metadata, course_id, override) do
    metadata = normalized_metadata(metadata)
    curriculum = curriculum_metadata(metadata)

    curriculum =
      curriculum
      |> Map.put("version", @academy_curriculum_override_version)
      |> Map.put("overrides", Map.put(curriculum_overrides(metadata), course_id, override))

    Map.put(metadata, @academy_curriculum_metadata_key, curriculum)
  end

  defp clear_curriculum_override(metadata, course_id) do
    metadata = normalized_metadata(metadata)
    curriculum = curriculum_metadata(metadata)

    curriculum =
      curriculum
      |> Map.put("version", @academy_curriculum_override_version)
      |> Map.put("overrides", Map.delete(curriculum_overrides(metadata), course_id))

    Map.put(metadata, @academy_curriculum_metadata_key, curriculum)
  end

  defp curriculum_metadata(metadata) when is_map(metadata) do
    case Map.get(metadata, @academy_curriculum_metadata_key) do
      curriculum when is_map(curriculum) -> curriculum
      _other -> %{}
    end
  end

  defp curriculum_metadata(_metadata), do: %{}

  defp curriculum_overrides(metadata) do
    case curriculum_metadata(metadata) do
      curriculum when is_map(curriculum) ->
        case Map.get(curriculum, @academy_curriculum_overrides_key) do
          overrides when is_map(overrides) -> overrides
          _other -> %{}
        end
    end
  end

  defp normalized_metadata(metadata) when is_map(metadata), do: metadata
  defp normalized_metadata(_metadata), do: %{}

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

  defp recommendation_changeset(message) do
    %Enrollment{}
    |> Changeset.change()
    |> Changeset.add_error(:metadata, message)
  end

  defp curriculum_changeset(message) do
    %Course{}
    |> Changeset.change()
    |> Changeset.add_error(:syllabus, message)
  end

  defp probation_enrollment?(%Enrollment{} = enrollment) do
    Map.get(enrollment.metadata || %{}, "outcome_tier") == "probation"
  end

  defp active_admission_recommendation?(%Enrollment{} = enrollment) do
    case Map.get(enrollment.metadata || %{}, "professor_recommendation") do
      %{
        "status" => "active",
        "purpose" => "academy_core_admission",
        "professor_character_id" => professor_character_id
      }
      when is_binary(professor_character_id) ->
        true

      _other ->
        false
    end
  end

  defp active_academy_head_admission?(%Enrollment{} = enrollment) do
    case Map.get(enrollment.metadata || %{}, "academy_head_admission") do
      %{
        "status" => "active",
        "purpose" => "academy_core_admission",
        "head_character_id" => head_character_id
      }
      when is_binary(head_character_id) ->
        true

      _other ->
        false
    end
  end

  defp active_academy_core_admission_clearance?(%Enrollment{} = enrollment) do
    active_admission_recommendation?(enrollment) or active_academy_head_admission?(enrollment)
  end

  defp tally_defense_votes(votes) do
    counts =
      votes
      |> Map.values()
      |> Enum.frequencies_by(&Map.get(&1, "vote"))

    accepts = Map.get(counts, "accept", 0)
    revisions = Map.get(counts, "accept_with_revisions", 0)
    rejects = Map.get(counts, "reject", 0)
    total = accepts + revisions + rejects

    cond do
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

  defp defense_metadata(%Project{} = project, opens_at, panel_ids) do
    (project.metadata || %{})
    |> Map.put("defense_panel_character_ids", panel_ids)
    |> Map.put("defense_votes", %{})
    |> Map.put(
      "defense_closes_at",
      opens_at
      |> Clock.arrival_at(@thesis_window_game_days)
      |> DateTime.to_iso8601()
    )
  end

  defp defense_votes(%Project{metadata: metadata}) do
    case Map.get(metadata || %{}, "defense_votes", %{}) do
      votes when is_map(votes) -> votes
      _other -> %{}
    end
  end

  defp defense_closes_at(%Project{} = project) do
    case Map.get(project.metadata || %{}, "defense_closes_at") do
      closes_at when is_binary(closes_at) ->
        case DateTime.from_iso8601(closes_at) do
          {:ok, parsed, _offset} -> parsed
          _other -> default_defense_closes_at(project)
        end

      _other ->
        default_defense_closes_at(project)
    end
  end

  defp default_defense_closes_at(%Project{defense_scheduled_at: %DateTime{} = opens_at}) do
    Clock.arrival_at(opens_at, @thesis_window_game_days)
  end

  defp default_defense_closes_at(_project), do: DateTime.utc_now()

  defp defense_vote_window_open?(%Project{} = project, %DateTime{} = now) do
    case project.defense_scheduled_at do
      %DateTime{} = opens_at ->
        DateTime.compare(now, opens_at) != :lt and
          DateTime.compare(now, defense_closes_at(project)) != :gt

      _other ->
        false
    end
  end

  defp refresh_defense_panel!(%Project{} = project) do
    if valid_defense_panel?(project) do
      project
    else
      refreshed_panel = build_defense_panel(project)

      if refreshed_panel == defense_panel_character_ids(project) do
        project
      else
        project
        |> Project.changeset(%{
          metadata:
            Map.put(project.metadata || %{}, "defense_panel_character_ids", refreshed_panel)
        })
        |> Repo.update!()
      end
    end
  end

  defp valid_defense_panel?(%Project{} = project) do
    panel_ids = defense_panel_character_ids(project)

    length(panel_ids) == 3 and
      length(Enum.uniq(panel_ids)) == 3 and
      project.character_id not in panel_ids and
      active_panel_member_count(project, panel_ids) == 3
  end

  defp active_panel_member_count(%Project{} = project, panel_ids) do
    Repo.aggregate(
      from(professor in Professor,
        where:
          professor.realm_id == ^project.realm_id and professor.status == :active and
            professor.character_id in ^panel_ids
      ),
      :count
    )
  end

  defp cast_npc_panel_votes!(%Project{} = project, %DateTime{} = now) do
    if valid_defense_panel?(project) do
      panel_ids = defense_panel_character_ids(project)
      existing_votes = defense_votes(project)

      updated_votes =
        panel_ids
        |> npc_panel_member_ids(project.realm_id)
        |> Enum.reduce(existing_votes, fn professor_id, votes ->
          Map.put_new(votes, professor_id, %{
            "vote" => "accept_with_revisions",
            "voted_at" => DateTime.to_iso8601(now),
            "source" => "academy_faculty"
          })
        end)

      if updated_votes == existing_votes do
        project
      else
        project
        |> Project.changeset(%{
          defense_state: :under_review,
          metadata: Map.put(project.metadata || %{}, "defense_votes", updated_votes)
        })
        |> Repo.update!()
      end
    else
      project
    end
  end

  defp npc_panel_member_ids(panel_ids, realm_id) do
    Professor
    |> where(
      [professor],
      professor.realm_id == ^realm_id and professor.status == :active and
        professor.character_id in ^panel_ids
    )
    |> Repo.all()
    |> Enum.filter(&npc_professor?/1)
    |> Enum.map(& &1.character_id)
  end

  defp defense_resolution_status(%Project{} = project) do
    panel_ids = defense_panel_character_ids(project)
    votes = defense_votes(project)

    cond do
      not valid_defense_panel?(project) ->
        :awaiting_panel

      Map.keys(votes) |> Enum.sort() != Enum.sort(panel_ids) ->
        :awaiting_votes

      Enum.all?(Map.values(votes), &valid_defense_vote?/1) ->
        {:ready, votes}

      true ->
        :awaiting_votes
    end
  end

  defp valid_defense_vote?(%{"vote" => vote})
       when vote in ["accept", "accept_with_revisions", "reject"],
       do: true

  defp valid_defense_vote?(_vote), do: false

  defp extend_defense_window!(%Project{} = project, %DateTime{} = now) do
    closes_at = Clock.arrival_at(now, @thesis_window_game_days)

    updated_project =
      project
      |> Project.changeset(%{
        metadata:
          Map.put(project.metadata || %{}, "defense_closes_at", DateTime.to_iso8601(closes_at))
      })
      |> Repo.update!()

    _job = schedule_thesis_defense_worker!(updated_project)
    updated_project
  end

  defp resolve_thesis_defense!(%Project{} = project, votes, %DateTime{} = now) do
    outcome = tally_defense_votes(votes)
    reject_count = Map.get(project.metadata || %{}, "defense_reject_count", 0)
    new_reject_count = if(outcome == :reject, do: reject_count + 1, else: reject_count)

    cond do
      outcome == :reject and new_reject_count < 2 ->
        reschedule_rejected_thesis!(project, votes, new_reject_count, now)

      true ->
        resolve_terminal_thesis!(project, votes, outcome, new_reject_count, now)
    end
  end

  defp reschedule_rejected_thesis!(%Project{} = project, votes, reject_count, now) do
    opens_at = Clock.arrival_at(now, @thesis_rework_game_days)

    metadata =
      (project.metadata || %{})
      |> append_defense_attempt(:reject, votes, now)
      |> Map.put("defense_outcome", "reject")
      |> Map.put("defense_reject_count", reject_count)
      |> Map.delete("defense_completed_at")

    metadata =
      defense_metadata(%{project | metadata: metadata}, opens_at, build_defense_panel(project))

    updated_project =
      project
      |> Project.changeset(%{
        defense_state: :pending_defense,
        defense_scheduled_at: opens_at,
        metadata: metadata
      })
      |> Repo.update!()

    job = schedule_thesis_defense_worker!(updated_project)
    %{project: updated_project, job: job, resolution: :rework}
  end

  defp resolve_terminal_thesis!(%Project{} = project, votes, outcome, reject_count, now) do
    state =
      case outcome do
        :accept -> :accepted
        :accept_with_revisions -> :accepted_with_revisions
        :reject -> :rejected
      end

    metadata =
      (project.metadata || %{})
      |> append_defense_attempt(outcome, votes, now)
      |> Map.put("defense_outcome", to_string(outcome))
      |> Map.put("defense_reject_count", reject_count)
      |> Map.put("defense_completed_at", DateTime.to_iso8601(now))

    publication =
      if state in [:accepted, :accepted_with_revisions] do
        case project.publication_id do
          nil -> publish_project!(%{project | metadata: metadata}, now)
          publication_id -> Repo.get!(Publication, publication_id)
        end
      end

    updated_project =
      project
      |> Project.changeset(%{
        defense_state: state,
        publication_id: publication && publication.id,
        metadata: metadata
      })
      |> Repo.update!()

    case state do
      accepted when accepted in [:accepted, :accepted_with_revisions] ->
        maybe_adjust_advisor_reputation(
          project.character_id,
          project.realm_id,
          +5,
          "thesis_accepted"
        )

      :rejected ->
        maybe_adjust_advisor_reputation(
          project.character_id,
          project.realm_id,
          -5,
          "thesis_rejected"
        )
    end

    %{project: updated_project, publication: publication, resolution: :terminal}
  end

  defp append_defense_attempt(metadata, outcome, votes, now) do
    history =
      case Map.get(metadata, "defense_attempt_history", []) do
        attempts when is_list(attempts) -> attempts
        _other -> []
      end

    Map.put(
      metadata,
      "defense_attempt_history",
      history ++
        [
          %{
            "outcome" => to_string(outcome),
            "resolved_at" => DateTime.to_iso8601(now),
            "votes" => votes
          }
        ]
    )
  end

  defp schedule_thesis_defense_worker!(%Project{} = project) do
    %{"project_id" => project.id}
    |> ThesisDefenseWorker.new(
      schedule_in: max(DateTime.diff(defense_closes_at(project), DateTime.utc_now(), :second), 0)
    )
    |> Oban.insert!()
  end

  defp build_defense_panel(%Project{} = project) do
    advisor_id =
      Repo.one(
        from relationship in AdvisorRelationship,
          where:
            relationship.student_character_id == ^project.character_id and
              relationship.realm_id == ^project.realm_id and relationship.status == :active,
          select: relationship.professor_character_id
      )

    professors =
      Repo.all(
        from professor in Professor,
          where:
            professor.realm_id == ^project.realm_id and professor.status == :active and
              professor.character_id != ^project.character_id
      )

    professor_ids =
      professors
      |> Enum.sort_by(fn professor ->
        {npc_professor?(professor), professor.appointed_at, professor.id}
      end)
      |> Enum.map(& &1.character_id)

    advisor_id = if(advisor_id in professor_ids, do: advisor_id, else: nil)

    [advisor_id | professor_ids]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp npc_professor?(%Professor{} = professor) do
    Map.get(professor.metadata || %{}, "npc_faculty", false) == true
  end

  defp defense_panel_character_ids(%Project{metadata: metadata}) do
    case Map.get(metadata || %{}, "defense_panel_character_ids", []) do
      character_ids when is_list(character_ids) -> Enum.filter(character_ids, &is_binary/1)
      _other -> []
    end
  end
end
