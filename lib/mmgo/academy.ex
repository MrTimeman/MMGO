defmodule MMGO.Academy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character

  alias MMGO.Academy.{
    CompleteEnrollmentWorker,
    Course,
    CourseEnrollment,
    ExamDeadlineWorker,
    Enrollment,
    Specialization,
    StarterOutcomes,
    Term
  }

  alias MMGO.Clubs.{Event, EventAttendance}
  alias MMGO.Academia.Publication
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  @tracks [:wizardry, :alchemy, :mastery]
  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]
  @lectures_per_term 3
  @club_events_for_merit 1
  @lecture_xp 5
  @lecture_base_final_ceiling 70
  @basic_final_without_midterm_cap 80
  @exam_duration_seconds 5 * 60
  @exam_attempt_metadata_key "exam_attempt"
  @academy_core_capstone_term_number 3
  @academy_core_passing_score 50
  @basic_reenrollment_cooldown_game_days 364
  @valedictorian_hall_of_fame_duration_seconds 365 * 24 * 60 * 60
  @valedictorian_bonus_schools_key "valedictorian_bonus_schools"
  @academy_curriculum_metadata_key "academy_curriculum"
  @academy_curriculum_overrides_key "overrides"
  @program_term_counts %{
    basic_education: 10,
    academy_core: 3,
    extended_study: 2,
    academia: 4
  }

  @lecture_material [
    %{
      key: "academy_foundations",
      title: "Лекция: основания Академии",
      body:
        "Куратор разбирает, как термин связывает занятия, клубы и экзаменационную ведомость. В конце он просит сверить главное правило расписания.",
      questions: [
        %{
          key: "q1",
          label: "Что завершает каждый академический термин?",
          options: [
            {"Выберите ответ", ""},
            {"Финальный экзамен", "a"},
            {"Торговый день", "b"},
            {"Дуэль", "c"}
          ],
          answer: "a"
        },
        %{
          key: "q2",
          label: "Где фиксируется результат обучения?",
          options: [
            {"Выберите ответ", ""},
            {"В ведомости термина", "a"},
            {"В кошельке", "b"},
            {"На карте", "c"}
          ],
          answer: "a"
        }
      ]
    },
    %{
      key: "academy_literacy",
      title: "Лекция: грамотность стихий",
      body:
        "На доске профессор показывает, почему формула, школа и цель должны согласовываться, даже когда магия ещё не стала вашей специализацией.",
      questions: [
        %{
          key: "q1",
          label: "Что выбирает будущий чародей при поступлении на Academy Core?",
          options: [
            {"Выберите ответ", ""},
            {"Две школы магии", "a"},
            {"Одну монету", "b"},
            {"Три базы", "c"}
          ],
          answer: "a"
        },
        %{
          key: "q2",
          label: "Что помогает сделать формулу пригодной для применения?",
          options: [
            {"Выберите ответ", ""},
            {"Согласовать школу и цель", "a"},
            {"Скрыть её от Академии", "b"},
            {"Отказаться от эффекта", "c"}
          ],
          answer: "a"
        }
      ]
    },
    %{
      key: "academy_civic_law",
      title: "Лекция: право и ответственность",
      body:
        "Секретарь Академии объясняет, что клубное участие и самостоятельная работа оставляют след в ведомости — как и пропущенный экзамен.",
      questions: [
        %{
          key: "q1",
          label: "Что подтверждает участие в клубном окне?",
          options: [
            {"Выберите ответ", ""},
            {"Реальная запись о посещении", "a"},
            {"Обещание в чате", "b"},
            {"Цвет мантии", "c"}
          ],
          answer: "a"
        },
        %{
          key: "q2",
          label: "Как Академия учитывает пропущенный финал?",
          options: [
            {"Выберите ответ", ""},
            {"Как проваленный термин", "a"},
            {"Как отличную оценку", "b"},
            {"Никак", "c"}
          ],
          answer: "a"
        }
      ]
    }
  ]

  @exam_questions [
    %{
      key: "q1",
      label: "Как зовётся столица княжества?",
      options: [
        {"Выберите ответ", ""},
        {"Железная Крепь", "a"},
        {"Врата Зари", "b"},
        {"Пепельная Завеса", "c"}
      ],
      answer: "b"
    },
    %{
      key: "q2",
      label: "Какая школа связана с исцелением?",
      options: [{"Выберите ответ", ""}, {"Жизнь", "a"}, {"Огонь", "b"}, {"Хаос", "c"}],
      answer: "a"
    },
    %{
      key: "q3",
      label: "Кто ведает Фондом Просвещения?",
      options: [
        {"Выберите ответ", ""},
        {"Торговая гильдия", "a"},
        {"Совет Подземелья", "b"},
        {"Академия", "c"}
      ],
      answer: "c"
    },
    %{
      key: "q4",
      label: "Сколько школ магии признаёт Академия?",
      options: [{"Выберите ответ", ""}, {"6", "a"}, {"8", "b"}, {"10", "c"}],
      answer: "b"
    },
    %{
      key: "q5",
      label: "Какой путь лучше всего подходит мастеру инструментов?",
      options: [
        {"Выберите ответ", ""},
        {"Чародейство", "a"},
        {"Алхимия", "b"},
        {"Академия наук", "c"},
        {"Мастерство", "d"}
      ],
      answer: "d"
    }
  ]

  @applied_exam_questions %{
    wizardry: %{
      key: "q6",
      label: "Какой набросок инкантации пригоден для одной вражеской цели?",
      options: [
        {"Выберите ответ", ""},
        {"Указать школу, действие и одну цель", "a"},
        {"Скрыть школу и цель", "b"},
        {"Добавить все школы сразу", "c"}
      ],
      answer: "a"
    },
    alchemy: %{
      key: "q6",
      label: "Что нужно проверить перед варкой рецепта?",
      options: [
        {"Выберите ответ", ""},
        {"Доступность рецепта и нужные реагенты", "a"},
        {"Только цвет колбы", "b"},
        {"Состав чужого кошелька", "c"}
      ],
      answer: "a"
    },
    mastery: %{
      key: "q6",
      label: "Что прежде всего определяет пригодность материала для инструмента?",
      options: [
        {"Выберите ответ", ""},
        {"Назначение и прочность материала", "a"},
        {"Имя владельца", "b"},
        {"Число зрителей", "c"}
      ],
      answer: "a"
    },
    general: %{
      key: "q6",
      label: "Какой принцип делает экзамен академическим?",
      options: [
        {"Выберите ответ", ""},
        {"Ответ сдаёт сам студент в своём термине", "a"},
        {"Друг отвечает вместо студента", "b"},
        {"Оценку выбирает браузер", "c"}
      ],
      answer: "a"
    }
  }

  @doc "Returns the number of real, year-long terms required by a program."
  def required_term_count(program_type) do
    Map.get(@program_term_counts, program_type, 0)
  end

  @doc "Returns the server-owned time window for one term of an enrollment."
  def term_schedule(%Enrollment{} = enrollment, term_number)
      when is_integer(term_number) and term_number > 0 do
    term_count = required_term_count(enrollment.program_type)

    cond do
      term_count == 0 or term_number > term_count ->
        nil

      is_nil(enrollment.started_at) or is_nil(enrollment.expected_completion_at) ->
        nil

      true ->
        total_seconds =
          max(
            DateTime.diff(enrollment.expected_completion_at, enrollment.started_at, :second),
            term_count
          )

        %{
          starts_at:
            DateTime.add(
              enrollment.started_at,
              div(total_seconds * (term_number - 1), term_count),
              :second
            ),
          ends_at:
            DateTime.add(
              enrollment.started_at,
              div(total_seconds * term_number, term_count),
              :second
            )
        }
    end
  end

  def term_schedule(_enrollment, _term_number), do: nil

  @doc "Returns sanitized, track-aware examination questions for one enrollment."
  def exam_questions(%Enrollment{} = enrollment) do
    enrollment
    |> exam_question_specs()
    |> Enum.map(fn question ->
      Map.take(question, [:key, :label, :options])
    end)
  end

  def exam_questions(_enrollment), do: []

  @doc "Scores submitted answers against the server-owned question key."
  def score_exam(%Enrollment{} = enrollment, answers) when is_map(answers) do
    questions = exam_question_specs(enrollment)

    correct_count =
      Enum.count(questions, fn question ->
        Map.get(answers, question.key) == question.answer
      end)

    div(correct_count * 100, length(questions))
  end

  def score_exam(_enrollment, _answers), do: 0

  def current_enrollment(character_id) when is_binary(character_id) do
    Repo.get_by(Enrollment, character_id: character_id, status: :active)
  end

  def enrollment_history(character_id) when is_binary(character_id) do
    Repo.all(
      from enrollment in Enrollment,
        where: enrollment.character_id == ^character_id,
        order_by: [asc: enrollment.inserted_at]
    )
  end

  def active_specialization(character_id) when is_binary(character_id) do
    Repo.get_by(Specialization, character_id: character_id, status: :active)
  end

  def list_specializations(character_id) when is_binary(character_id) do
    Repo.all(
      from specialization in Specialization,
        where: specialization.character_id == ^character_id,
        order_by: [asc: specialization.inserted_at]
    )
  end

  def school_permitted?(character_id, school) when is_binary(character_id) do
    case normalize_school(school) do
      nil ->
        false

      school ->
        school_code = Atom.to_string(school)

        wizard_specialization_permits?(character_id, school_code) or
          school_code in valedictorian_bonus_schools(character_id)
    end
  end

  def school_permitted?(_character_id, _school), do: false

  @doc "Returns the spell schools permanently unlocked by valedictorian rewards."
  def valedictorian_bonus_schools(%Character{} = character) do
    character.metadata
    |> bonus_school_codes()
  end

  def valedictorian_bonus_schools(character_id) when is_binary(character_id) do
    case Repo.get(Character, character_id) do
      %Character{} = character -> valedictorian_bonus_schools(character)
      nil -> []
    end
  end

  def valedictorian_bonus_schools(_character), do: []

  @doc "Returns all permanent valedictorian honors earned by a character."
  def list_valedictorian_honors(character_id) when is_binary(character_id) do
    character_id
    |> completed_enrollments_for_character()
    |> Enum.filter(&valedictorian?/1)
  end

  def list_valedictorian_honors(_character_id), do: []

  @doc "Returns the permanent academic titles earned through completed programs."
  def list_academic_titles(character_id) when is_binary(character_id) do
    character_id
    |> completed_enrollments_for_character()
    |> Enum.filter(&is_binary(academic_title(&1)))
  end

  def list_academic_titles(_character_id), do: []

  @doc "Returns the newest unclaimed valedictorian bonus enrollment, if any."
  def pending_valedictorian_bonus(character_id) when is_binary(character_id) do
    character_id
    |> completed_enrollments_for_character()
    |> Enum.find(&claimable_valedictorian_bonus?/1)
  end

  def pending_valedictorian_bonus(_character_id), do: nil

  @doc "Returns one realm's currently pinned valedictorians for the public bulletin board."
  def list_valedictorians_for_realm(realm_id, opts \\ [])

  def list_valedictorians_for_realm(realm_id, opts)
      when is_binary(realm_id) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.all(
      from enrollment in Enrollment,
        where:
          enrollment.realm_id == ^realm_id and enrollment.status == :completed and
            not is_nil(enrollment.completed_at),
        preload: [:character],
        order_by: [desc: enrollment.completed_at, desc: enrollment.inserted_at]
    )
    |> Enum.filter(&valedictorian?/1)
    |> Enum.filter(&hall_of_fame_active?(&1, now))
  end

  def list_valedictorians_for_realm(_realm_id, _opts), do: []

  @doc "Returns the durable title displayed for a valedictorian enrollment."
  def valedictorian_title(%Enrollment{} = enrollment) do
    metadata = enrollment.metadata || %{}

    Map.get(metadata, "valedictorian_title") ||
      "Валедикториан когорты #{cohort_key(enrollment)}"
  end

  @doc "Returns the permanent non-valedictorian honor title, if this enrollment earned one."
  def academic_title(%Enrollment{} = enrollment) do
    case Map.get(enrollment.metadata || %{}, "academic_title") do
      title when is_binary(title) and byte_size(title) > 0 -> title
      _other -> nil
    end
  end

  @doc "Returns the bulletin-board expiry timestamp for a valedictorian enrollment."
  def hall_of_fame_until(%Enrollment{} = enrollment) do
    metadata = enrollment.metadata || %{}

    case Map.get(metadata, "valedictorian_hall_of_fame_until") do
      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, datetime, _offset} -> datetime
          {:error, _reason} -> legacy_hall_of_fame_until(enrollment)
        end

      _other ->
        legacy_hall_of_fame_until(enrollment)
    end
  end

  @doc "Creates exactly one selected bonus spell for an earned valedictorian honor."
  def claim_valedictorian_bonus_spell(character, school, opts \\ [])

  def claim_valedictorian_bonus_spell(%Character{} = character, school, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    school = normalize_school(school)

    Repo.transaction(fn ->
      character = lock_character!(character.id)

      enrollment =
        character.id
        |> completed_enrollments_for_character(lock?: true)
        |> Enum.find(&claimable_valedictorian_bonus?/1)

      cond do
        is_nil(school) ->
          Repo.rollback(enrollment_changeset("valedictorian bonus school is invalid"))

        is_nil(enrollment) ->
          Repo.rollback(enrollment_changeset("no unclaimed valedictorian bonus is available"))

        true ->
          spell = StarterOutcomes.grant_valedictorian_spell!(character, enrollment, school)
          school_code = Atom.to_string(school)

          updated_character =
            character
            |> Character.changeset(%{
              metadata:
                (character.metadata || %{})
                |> Map.put(
                  @valedictorian_bonus_schools_key,
                  character
                  |> valedictorian_bonus_schools()
                  |> Kernel.++([school_code])
                  |> Enum.uniq()
                )
            })
            |> Repo.update!()

          updated_enrollment =
            enrollment
            |> Enrollment.changeset(%{
              metadata:
                (enrollment.metadata || %{})
                |> Map.put("valedictorian_bonus", %{
                  "status" => "claimed",
                  "school" => school_code,
                  "spell_id" => spell.id,
                  "claimed_at" => DateTime.to_iso8601(now)
                })
            })
            |> Repo.update!()

          %{character: updated_character, enrollment: updated_enrollment, spell: spell}
      end
    end)
    |> normalize_transaction_result()
  end

  def claim_valedictorian_bonus_spell(_character, _school, _opts),
    do: {:error, enrollment_changeset("valedictorian bonus is unavailable")}

  def basic_education_completed?(character_id) when is_binary(character_id) do
    completed_program?(character_id, :basic_education)
  end

  def program_completed?(character_id, program_type) when is_binary(character_id) do
    completed_program?(character_id, program_type)
  end

  @doc "Returns whether an Academy Core graduate earned the top-cohort advisor pick."
  def advisor_pick_eligible?(character_id) when is_binary(character_id) do
    latest_core_enrollment =
      Repo.one(
        from enrollment in Enrollment,
          where:
            enrollment.character_id == ^character_id and enrollment.program_type == :academy_core and
              enrollment.status == :completed,
          order_by: [desc: enrollment.completed_at, desc: enrollment.inserted_at],
          limit: 1
      )

    case latest_core_enrollment do
      %Enrollment{metadata: metadata} ->
        truthy_metadata?(metadata || %{}, "honors") or
          truthy_metadata?(metadata || %{}, "valedictorian")

      nil ->
        false
    end
  end

  def advisor_pick_eligible?(_character_id), do: false

  def academic_affiliated?(character_id) when is_binary(character_id) do
    not is_nil(current_enrollment(character_id)) or
      not is_nil(active_specialization(character_id)) or
      basic_education_completed?(character_id)
  end

  def begin_basic_education(%Character{} = character, opts \\ []) do
    start_program(character, :basic_education, nil, %{}, opts)
  end

  def start_academy_track(%Character{} = character, track, attrs \\ %{}, opts \\ []) do
    start_program(character, :academy_core, track, attrs, opts)
  end

  def start_extended_study(%Character{} = character, opts \\ []) do
    start_program(character, :extended_study, nil, %{}, opts)
  end

  def start_academia(%Character{} = character, opts \\ []) do
    start_program(character, :academia, nil, %{}, opts)
  end

  def complete_enrollment_by_id(enrollment_id, opts \\ []) when is_binary(enrollment_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      enrollment = lock_enrollment!(enrollment_id)
      character = lock_character!(enrollment.character_id)

      cond do
        enrollment.status != :active ->
          Repo.rollback(enrollment_changeset("enrollment is not active"))

        not force? and DateTime.compare(now, enrollment.expected_completion_at) == :lt ->
          Repo.rollback(enrollment_changeset("enrollment is not due yet"))

        true ->
          if DateTime.compare(now, enrollment.expected_completion_at) != :lt do
            reconcile_elapsed_terms!(enrollment, now)
          end

          capstone_required? = academy_core_capstone_due?(enrollment, now)

          capstone_passed? =
            not capstone_required? or academy_core_capstone_passed?(enrollment.id)

          outcome_tier =
            if capstone_required? and not capstone_passed? do
              :capstone_incomplete
            else
              compute_outcome_tier(enrollment.id, enrollment.program_type)
            end

          graduation_metadata =
            enrollment
            |> graduation_metadata(outcome_tier)
            |> record_capstone_status(enrollment, capstone_passed?)

          completion_status = completion_status(enrollment, outcome_tier)

          updated_enrollment =
            enrollment
            |> Enrollment.changeset(%{
              status: completion_status,
              completed_at: now,
              metadata:
                (enrollment.metadata || %{})
                |> Map.put("outcome_tier", to_string(outcome_tier))
                |> Map.merge(graduation_metadata)
            })
            |> Repo.update!()

          updated_enrollment = finalize_cohort_rewards!(updated_enrollment, now)

          updated_character =
            character
            |> Character.changeset(%{
              status:
                if(enrollment.program_type == :basic_education,
                  do: :active,
                  else: character.status
                )
            })
            |> Repo.update!()

          updated_character =
            if award_completion_xp?(enrollment, completion_status) do
              {:ok, %{character: awarded_character}} =
                Progression.grant_xp(Repo, updated_character, completion_xp(enrollment), %{
                  "source" => "academy_enrollment_completion",
                  "enrollment_id" => enrollment.id,
                  "program_type" => to_string(enrollment.program_type),
                  "granted_at" => now
                })

              awarded_character
            else
              updated_character
            end

          specialization =
            if eligible_for_specialization?(updated_enrollment) do
              maybe_upsert_specialization!(updated_enrollment, now)
            end

          starter_reward_result =
            StarterOutcomes.grant!(
              updated_character,
              updated_enrollment,
              specialization,
              outcome_tier
            )

          %{
            enrollment: starter_reward_result.enrollment,
            character: starter_reward_result.character,
            specialization: specialization,
            starter_outcomes: starter_reward_result.starter_outcomes
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def get_term!(term_id) when is_binary(term_id) do
    Repo.get!(Term, term_id)
  end

  def list_terms_for_enrollment(enrollment_id) when is_binary(enrollment_id) do
    Repo.all(
      from term in Term,
        where: term.enrollment_id == ^enrollment_id,
        order_by: [asc: term.term_number]
    )
  end

  def current_term(enrollment_id) when is_binary(enrollment_id) do
    Repo.get_by(Term, enrollment_id: enrollment_id, status: :active)
  end

  def begin_term(enrollment_id, opts \\ []) when is_binary(enrollment_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      enrollment =
        Enrollment
        |> where([e], e.id == ^enrollment_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if enrollment.status != :active do
        Repo.rollback(enrollment_changeset("enrollment is not active"))
      end

      terms = reconcile_elapsed_terms!(enrollment, now)

      if Enum.any?(terms, &(&1.status == :active)) do
        Repo.rollback(enrollment_changeset("a term is already active"))
      end

      existing_count = length(terms)
      term_number = existing_count + 1
      required_terms = required_term_count(enrollment.program_type)
      schedule = term_schedule(enrollment, term_number)

      cond do
        required_terms == 0 ->
          Repo.rollback(enrollment_changeset("program does not define academic terms"))

        existing_count >= required_terms ->
          Repo.rollback(enrollment_changeset("all program terms have already been recorded"))

        is_nil(schedule) ->
          Repo.rollback(enrollment_changeset("term schedule is unavailable"))

        DateTime.compare(now, schedule.starts_at) == :lt ->
          Repo.rollback(enrollment_changeset("the next term has not opened yet"))

        true ->
          %Term{}
          |> Term.changeset(%{
            enrollment_id: enrollment_id,
            realm_id: enrollment.realm_id,
            term_number: term_number,
            status: :active,
            started_at: now,
            metadata: term_metadata("enrollment", schedule)
          })
          |> Repo.insert!()
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns the server-owned term progression metadata in presentation form."
  def term_progress(%Term{} = term, opts \\ []) when is_list(opts) do
    metadata = term.metadata || %{}
    phase = normalize_term_phase(Map.get(metadata, "phase"))
    character_id = Keyword.get(opts, :character_id)

    club_events_attended =
      if term.status == :active and phase == :club_window and is_binary(character_id) do
        club_attendance_count(term, character_id)
      else
        positive_or_zero(Map.get(metadata, "club_events_attended", 0))
      end

    club_events_required =
      positive_or_default(
        Map.get(metadata, "club_events_required", @club_events_for_merit),
        @club_events_for_merit
      )

    %{
      phase: phase,
      lectures_attended: positive_or_zero(Map.get(metadata, "lectures_attended", 0)),
      lectures_required:
        positive_or_default(
          Map.get(metadata, "lectures_required", @lectures_per_term),
          @lectures_per_term
        ),
      lecture_final_ceiling: lecture_final_ceiling(metadata),
      lecture_results: lecture_results(metadata),
      club_events_attended: club_events_attended,
      club_events_required: club_events_required,
      merit_eligible?: club_events_attended >= club_events_required,
      midterm_score: Map.get(metadata, "midterm_score"),
      midterm_skipped?: truthy_metadata?(metadata, "midterm_skipped"),
      final_score: Map.get(metadata, "final_score")
    }
  end

  @doc "Returns the fixed, server-owned duration for a timed Academy exam."
  def exam_duration_seconds, do: @exam_duration_seconds

  @doc """
  Opens or resumes the current term's timed exam attempt.

  The deadline is persisted on the term, so reconnecting or opening another
  browser tab can never create a fresh five-minute window.
  """
  def start_exam_attempt(character_id, term_id, opts \\ [])

  def start_exam_attempt(character_id, term_id, opts)
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      phase = term_progress(term).phase

      if phase not in [:midterm, :final] do
        Repo.rollback(:academy_exam_unavailable)
      end

      case current_exam_attempt(term, phase) do
        {:open, attempt, deadline_at} ->
          if DateTime.compare(now, deadline_at) == :lt do
            %{
              term: term,
              phase: phase,
              attempt_id: attempt["id"],
              deadline_at: deadline_at,
              resumed?: true,
              deadline_worker: nil
            }
          else
            Repo.rollback(:academy_exam_expired)
          end

        :none ->
          attempt_id = Ecto.UUID.generate()
          deadline_at = DateTime.add(now, @exam_duration_seconds, :second)

          attempt = %{
            "id" => attempt_id,
            "phase" => exam_phase_name(phase),
            "opened_at" => DateTime.to_iso8601(now),
            "deadline_at" => DateTime.to_iso8601(deadline_at),
            "deadline_seconds" => @exam_duration_seconds,
            "status" => "open"
          }

          updated_term =
            term
            |> Term.changeset(%{
              metadata: Map.put(term.metadata || %{}, @exam_attempt_metadata_key, attempt)
            })
            |> Repo.update!()

          deadline_worker =
            schedule_exam_deadline!(updated_term, phase, attempt_id, deadline_at)

          %{
            term: updated_term,
            phase: phase,
            attempt_id: attempt_id,
            deadline_at: deadline_at,
            resumed?: false,
            deadline_worker: deadline_worker
          }

        :invalid ->
          Repo.rollback(:academy_exam_unavailable)
      end
    end)
    |> normalize_exam_attempt_result()
  end

  def start_exam_attempt(_character_id, _term_id, _opts), do: {:error, :academy_exam_unavailable}

  @doc """
  Submits one answer set against the persisted, server-authoritative deadline.

  `score` is already server-computed by the caller. The phase and deadline are
  rechecked under the term lock immediately before the grade transition.
  """
  def submit_exam_attempt(character_id, term_id, phase, score, opts \\ [])

  def submit_exam_attempt(character_id, term_id, phase, score, opts)
      when is_binary(character_id) and is_binary(term_id) and is_integer(score) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, phase} <- normalize_exam_phase(phase) do
      Repo.transaction(fn ->
        {term, enrollment} = lock_term_for_character!(term_id, character_id)
        progress = term_progress(term)

        cond do
          term.status != :active ->
            Repo.rollback(:academy_exam_unavailable)

          progress.phase != phase ->
            Repo.rollback(:academy_exam_unavailable)

          score < 0 or score > 100 ->
            Repo.rollback(enrollment_changeset("exam score must be 0–100"))

          true ->
            case current_exam_attempt(term, phase) do
              {:open, _attempt, deadline_at} ->
                if DateTime.compare(now, deadline_at) == :lt do
                  metadata =
                    mark_exam_attempt(
                      term.metadata || %{},
                      phase,
                      "submitted",
                      "submitted_at",
                      now
                    )

                  case phase do
                    :midterm -> submit_midterm_locked!(term, score, now, metadata)
                    :final -> submit_final_locked!(term, enrollment, score, now, metadata)
                  end
                else
                  Repo.rollback(:academy_exam_expired)
                end

              :none ->
                Repo.rollback(:academy_exam_unavailable)

              :invalid ->
                Repo.rollback(:academy_exam_unavailable)
            end
        end
      end)
      |> normalize_exam_attempt_result()
    end
  end

  def submit_exam_attempt(_character_id, _term_id, _phase, _score, _opts),
    do: {:error, :academy_exam_unavailable}

  @doc """
  Applies the deterministic timeout outcome for exactly one persisted attempt.

  This is intentionally safe for a late or retried worker: it only acts while
  the stored phase, attempt id, and deadline all still match.
  """
  def expire_exam_attempt(term_id, phase, attempt_id, opts \\ [])

  def expire_exam_attempt(term_id, phase, attempt_id, opts)
      when is_binary(term_id) and is_binary(attempt_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, phase} <- normalize_exam_phase(phase) do
      Repo.transaction(fn ->
        case lock_exam_term(term_id) do
          nil ->
            Repo.rollback(:academy_exam_unavailable)

          {term, enrollment} ->
            progress = term_progress(term)

            cond do
              term.status != :active ->
                Repo.rollback(:academy_exam_unavailable)

              enrollment.status != :active ->
                Repo.rollback(:academy_exam_unavailable)

              progress.phase != phase ->
                Repo.rollback(:academy_exam_unavailable)

              true ->
                case current_exam_attempt(term, phase) do
                  {:open, %{"id" => ^attempt_id}, deadline_at} ->
                    if DateTime.compare(now, deadline_at) == :lt do
                      Repo.rollback(:exam_not_due)
                    end

                    metadata =
                      mark_exam_attempt(term.metadata || %{}, phase, "expired", "expired_at", now)

                    expire_exam_attempt_locked!(term, enrollment, phase, metadata, now)

                  {:open, _attempt, _deadline_at} ->
                    Repo.rollback(:academy_exam_unavailable)

                  :none ->
                    Repo.rollback(:academy_exam_unavailable)

                  :invalid ->
                    Repo.rollback(:academy_exam_unavailable)
                end
            end
        end
      end)
      |> normalize_exam_attempt_result()
    end
  end

  def expire_exam_attempt(_term_id, _phase, _attempt_id, _opts),
    do: {:error, :academy_exam_unavailable}

  def open_lecture_phase(character_id, term_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :enrollment ->
          Repo.rollback(enrollment_changeset("course selection is no longer open for this term"))

        true ->
          term
          |> Term.changeset(%{
            metadata:
              (term.metadata || %{})
              |> Map.put("phase", "lectures")
              |> Map.put("course_selection_closed_at", DateTime.to_iso8601(now))
          })
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns the next server-owned lecture prompt for a student's active term."
  def lecture_prompt(character_id, term_id)
      when is_binary(character_id) and is_binary(term_id) do
    term =
      Repo.one(
        from term in Term,
          join: enrollment in Enrollment,
          on: enrollment.id == term.enrollment_id,
          where: term.id == ^term_id and enrollment.character_id == ^character_id,
          select: term
      )

    with %Term{status: :active} = term <- term,
         %{phase: :lectures} = progress <- term_progress(term),
         prompt when not is_nil(prompt) <- lecture_material_for(progress.lectures_attended) do
      {:ok, lecture_presentation(prompt, progress.lectures_attended)}
    else
      _other -> {:error, :academy_lecture_unavailable}
    end
  end

  def lecture_prompt(_character_id, _term_id), do: {:error, :academy_lecture_unavailable}

  @doc "Scores and records the scoped student's answer to the next lecture prompt."
  def submit_lecture(character_id, term_id, answers, opts \\ [])

  def submit_lecture(character_id, term_id, answers, opts)
      when is_binary(character_id) and is_binary(term_id) and is_map(answers) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)
      prompt = lecture_material_for(progress.lectures_attended)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :lectures ->
          Repo.rollback(enrollment_changeset("lectures are no longer open for this term"))

        is_nil(prompt) ->
          Repo.rollback(enrollment_changeset("no lecture is currently available"))

        true ->
          correct_answers = lecture_correct_answers(prompt, answers)
          question_count = length(prompt.questions)
          attended = min(progress.lectures_attended + 1, progress.lectures_required)
          final_ceiling = lecture_final_ceiling_for(attended, progress.lectures_required)

          lecture_result = %{
            "lecture_key" => prompt.key,
            "correct_answers" => correct_answers,
            "question_count" => question_count,
            "final_ceiling" => final_ceiling,
            "submitted_at" => DateTime.to_iso8601(now)
          }

          metadata =
            (term.metadata || %{})
            |> Map.put("lectures_attended", attended)
            |> Map.put("lecture_results", lecture_results(term.metadata) ++ [lecture_result])
            |> Map.put("lecture_final_ceiling", final_ceiling)
            |> Map.put(
              "phase",
              if(attended >= progress.lectures_required, do: "club_window", else: "lectures")
            )
            |> Map.put("last_lecture_at", DateTime.to_iso8601(now))
            |> then(fn metadata ->
              if attended >= progress.lectures_required do
                Map.put(metadata, "club_window_opened_at", DateTime.to_iso8601(now))
              else
                metadata
              end
            end)

          updated_term =
            term
            |> Term.changeset(%{metadata: metadata})
            |> Repo.update!()

          character = Repo.get!(Character, character_id)

          case Progression.grant_xp(Repo, character, @lecture_xp, %{
                 "source" => "academy_lecture",
                 "academy_term_id" => term.id,
                 "lecture_key" => prompt.key,
                 "correct_answers" => correct_answers,
                 "question_count" => question_count,
                 "granted_at" => now
               }) do
            {:ok, _result} ->
              %{
                term: updated_term,
                correct_answers: correct_answers,
                question_count: question_count,
                final_ceiling: final_ceiling
              }

            {:error, %Changeset{} = changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def submit_lecture(_character_id, _term_id, _answers, _opts),
    do: {:error, enrollment_changeset("academy lecture is unavailable")}

  def attend_lecture(character_id, term_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :lectures ->
          Repo.rollback(enrollment_changeset("lectures are no longer open for this term"))

        true ->
          attended = min(progress.lectures_attended + 1, progress.lectures_required)

          metadata =
            (term.metadata || %{})
            |> Map.put("lectures_attended", attended)
            |> Map.put(
              "phase",
              if(attended >= progress.lectures_required, do: "club_window", else: "lectures")
            )
            |> Map.put("last_lecture_at", DateTime.to_iso8601(now))
            |> then(fn metadata ->
              if attended >= progress.lectures_required do
                Map.put(metadata, "club_window_opened_at", DateTime.to_iso8601(now))
              else
                metadata
              end
            end)

          updated_term =
            term
            |> Term.changeset(%{metadata: metadata})
            |> Repo.update!()

          character = Repo.get!(Character, character_id)

          case Progression.grant_xp(Repo, character, @lecture_xp, %{
                 "source" => "academy_lecture",
                 "academy_term_id" => term.id,
                 "granted_at" => now
               }) do
            {:ok, _result} ->
              updated_term

            {:error, %Changeset{} = changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Closes the optional lecture window and opens the term's club window."
  def close_lecture_phase(character_id, term_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :lectures ->
          Repo.rollback(enrollment_changeset("lecture window is not open for this term"))

        true ->
          term
          |> Term.changeset(%{
            metadata:
              (term.metadata || %{})
              |> Map.put("phase", "club_window")
              |> Map.put("lecture_window_closed_at", DateTime.to_iso8601(now))
              |> Map.put("club_window_opened_at", DateTime.to_iso8601(now))
          })
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Records one student's office-hour visit for an enrolled course in the active term."
  def attend_office_hours(character_id, term_id, course_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) and is_binary(course_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)

      course_enrollment =
        CourseEnrollment
        |> where(
          [course_enrollment],
          course_enrollment.term_id == ^term.id and
            course_enrollment.course_id == ^course_id and
            course_enrollment.character_id == ^character_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      course =
        Course
        |> where([course], course.id == ^course_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase not in [:lectures, :club_window, :midterm] ->
          Repo.rollback(enrollment_changeset("office hours are not open for this term phase"))

        is_nil(course_enrollment) or course_enrollment.status != :enrolled ->
          Repo.rollback(enrollment_changeset("student is not enrolled in this course"))

        is_nil(course) or course.realm_id != enrollment.realm_id ->
          Repo.rollback(enrollment_changeset("course is not available in this realm"))

        office_hours_attended?(course_enrollment) ->
          Repo.rollback(enrollment_changeset("office hours have already been attended"))

        true ->
          instructor_key = office_hours_instructor_key(course)

          updated_course_enrollment =
            course_enrollment
            |> CourseEnrollment.changeset(%{
              metadata:
                (course_enrollment.metadata || %{})
                |> Map.put("office_hours_attended", true)
                |> Map.put("office_hours_attended_at", DateTime.to_iso8601(now))
                |> Map.put("office_hours_grade_bonus", 5)
                |> Map.put("office_hours_instructor", instructor_key)
            })
            |> Repo.update!()

          _updated_enrollment =
            enrollment
            |> Enrollment.changeset(%{
              metadata:
                record_office_hours_relationship(
                  enrollment.metadata || %{},
                  instructor_key,
                  course.id,
                  now
                )
            })
            |> Repo.update!()

          %{course_enrollment: updated_course_enrollment, instructor_key: instructor_key}
      end
    end)
    |> normalize_transaction_result()
  end

  def skip_midterm(character_id, term_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :midterm ->
          Repo.rollback(enrollment_changeset("midterm is not open for this term"))

        enrollment.program_type != :basic_education ->
          Repo.rollback(enrollment_changeset("midterm is required for this program"))

        true ->
          term
          |> Term.changeset(%{
            metadata:
              (term.metadata || %{})
              |> mark_exam_attempt(:midterm, "skipped", "skipped_at", now)
              |> Map.put("phase", "final")
              |> Map.put("midterm_skipped", true)
              |> Map.put("midterm_skipped_at", DateTime.to_iso8601(now))
          })
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  def close_club_window(character_id, term_id, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      progress = term_progress(term, character_id: character_id)

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        progress.phase != :club_window ->
          Repo.rollback(enrollment_changeset("club window is not open for this term"))

        true ->
          term
          |> Term.changeset(%{
            metadata:
              (term.metadata || %{})
              |> Map.put("phase", "midterm")
              |> Map.put("club_events_attended", progress.club_events_attended)
              |> Map.put("club_window_closed_at", DateTime.to_iso8601(now))
          })
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  def submit_midterm(character_id, term_id, score, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) and is_integer(score) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, _enrollment} = lock_term_for_character!(term_id, character_id)
      submit_midterm_locked!(term, score, now)
    end)
    |> normalize_transaction_result()
  end

  def submit_final(character_id, term_id, score, opts \\ [])
      when is_binary(character_id) and is_binary(term_id) and is_integer(score) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      {term, enrollment} = lock_term_for_character!(term_id, character_id)
      submit_final_locked!(term, enrollment, score, now)
    end)
    |> normalize_transaction_result()
  end

  def submit_exam(term_id, score, opts \\ []) when is_binary(term_id) and is_integer(score) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      term =
        Term
        |> where([t], t.id == ^term_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        score < 0 or score > 100 ->
          Repo.rollback(enrollment_changeset("exam score must be 0–100"))

        true ->
          updated_term =
            term
            |> Term.changeset(%{
              exam_score: score,
              status: :completed,
              ended_at: now
            })
            |> Repo.update!()

          updated_term.enrollment_id
          |> lock_enrollment!()
          |> sync_enrollment_academic_metadata!()

          updated_term
      end
    end)
    |> normalize_transaction_result()
  end

  def fail_term(term_id, opts \\ []) when is_binary(term_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      term =
        Term
        |> where([t], t.id == ^term_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if term.status != :active do
        Repo.rollback(enrollment_changeset("term is not active"))
      end

      updated_term =
        term
        |> Term.changeset(%{status: :failed, ended_at: now})
        |> Repo.update!()

      updated_term.enrollment_id
      |> lock_enrollment!()
      |> sync_enrollment_academic_metadata!()

      updated_term
    end)
    |> normalize_transaction_result()
  end

  def gpa_for_enrollment(enrollment_id) when is_binary(enrollment_id) do
    result =
      Repo.one(
        from term in Term,
          where:
            term.enrollment_id == ^enrollment_id and term.status == :completed and
              not is_nil(term.exam_score),
          select: avg(term.exam_score)
      )

    case result do
      nil -> nil
      avg -> avg |> Decimal.to_float() |> Float.round(2)
    end
  end

  def failed_terms_count(enrollment_id) when is_binary(enrollment_id) do
    Repo.aggregate(
      from(term in Term,
        where: term.enrollment_id == ^enrollment_id and term.status == :failed
      ),
      :count
    )
  end

  @doc "Returns the stable, realm-local graduation cohort key for an enrollment."
  def cohort_key(%Enrollment{} = enrollment) do
    case Map.get(enrollment.metadata || %{}, "cohort_key") do
      key when is_binary(key) and byte_size(key) > 0 -> key
      _other -> derived_cohort_key(enrollment.program_type, enrollment.expected_completion_at)
    end
  end

  @doc "Builds the public GPA leaderboard for the enrollment's real graduation cohort."
  def cohort_leaderboard(%Enrollment{} = enrollment) do
    key = cohort_key(enrollment)

    cohort_enrollments =
      Repo.all(
        from candidate in Enrollment,
          where:
            candidate.realm_id == ^enrollment.realm_id and
              candidate.program_type == ^enrollment.program_type and
              candidate.status in [:active, :completed],
          preload: [:character]
      )
      |> Enum.filter(&(cohort_key(&1) == key))

    terms_by_enrollment =
      cohort_enrollments
      |> Enum.map(& &1.id)
      |> then(fn enrollment_ids ->
        if enrollment_ids == [] do
          %{}
        else
          Term
          |> where([term], term.enrollment_id in ^enrollment_ids)
          |> Repo.all()
          |> Enum.group_by(& &1.enrollment_id)
        end
      end)

    cohort_enrollments
    |> Enum.map(fn candidate ->
      stats = academic_stats(Map.get(terms_by_enrollment, candidate.id, []))

      %{
        enrollment: candidate,
        character: candidate.character,
        gpa: stats.gpa,
        completed_terms: stats.completed_terms,
        failed_terms: stats.failed_terms,
        ranking_eligible?: stats.ranking_eligible?
      }
    end)
    |> Enum.sort_by(fn entry ->
      {
        if(entry.ranking_eligible?, do: 0, else: 1),
        -(entry.gpa || 0.0),
        DateTime.to_unix(entry.enrollment.inserted_at, :microsecond),
        entry.enrollment.id
      }
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} ->
      entry
      |> Map.put(:rank, rank)
      |> Map.put(:cohort_size, length(cohort_enrollments))
    end)
  end

  @doc "Returns the running GPA, rank, club eligibility, and persisted graduation outcome."
  def academic_record(%Enrollment{} = enrollment) do
    stats = academic_stats(list_terms_for_enrollment(enrollment.id))

    leaderboard_entry =
      enrollment
      |> cohort_leaderboard()
      |> Enum.find(&(&1.enrollment.id == enrollment.id))

    metadata = enrollment.metadata || %{}
    outcome_tier = outcome_tier_from_metadata(metadata)

    %{
      cohort_key: cohort_key(enrollment),
      gpa: stats.gpa,
      completed_terms: stats.completed_terms,
      failed_terms: stats.failed_terms,
      ranking_eligible?: stats.ranking_eligible?,
      cohort_rank: leaderboard_entry && leaderboard_entry.rank,
      cohort_size: leaderboard_entry && leaderboard_entry.cohort_size,
      outcome_tier: outcome_tier,
      merit_scholarship_eligible?: truthy_metadata?(metadata, "merit_scholarship_eligible"),
      valedictorian?: truthy_metadata?(metadata, "valedictorian"),
      valedictorian_title:
        if(truthy_metadata?(metadata, "valedictorian"),
          do: valedictorian_title(enrollment),
          else: nil
        ),
      hall_of_fame_until:
        if(truthy_metadata?(metadata, "valedictorian"),
          do: hall_of_fame_until(enrollment),
          else: nil
        ),
      academic_title: academic_title(enrollment),
      honors?: truthy_metadata?(metadata, "honors")
    }
  end

  @doc "Returns the durable starter rewards created for an Academy Core graduate."
  def starter_outcomes(%Enrollment{} = enrollment), do: StarterOutcomes.summary(enrollment)

  @doc "Returns a verified charity stipend receipt attached to an enrollment."
  def charity_stipend(%Enrollment{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "charity_stipend") do
      %{
        "status" => "paid",
        "purpose" => "academy_core_stipend",
        "amount" => amount,
        "ledger_entry_id" => ledger_entry_id
      } = receipt
      when is_integer(amount) and amount > 0 and is_binary(ledger_entry_id) ->
        receipt

      _other ->
        nil
    end
  end

  def charity_stipend(_enrollment), do: nil

  @doc """
  Lists the active seeded curriculum together with its base schedule and any
  Academy Head schedule overlay. The overlay is stored on the realm, so the
  course records themselves remain stable and idempotent to seed.
  """
  def list_seeded_courses_for_realm(realm_id) when is_binary(realm_id) do
    metadata = realm_metadata(Repo.get(Realm, realm_id))
    overrides = curriculum_overrides(metadata)

    Course
    |> where(
      [course],
      course.realm_id == ^realm_id and course.source == :seeded and course.status == :active
    )
    |> order_by([course], asc: course.inserted_at)
    |> Repo.all()
    |> Enum.map(fn course ->
      effective_course = effective_course_for_metadata(course, metadata)

      %{
        course: course,
        base_term_numbers: scheduled_term_numbers(course),
        effective_term_numbers: scheduled_term_numbers(effective_course),
        allowed_term_numbers: allowed_curriculum_terms(course),
        override: curriculum_override_for_course(course, overrides)
      }
    end)
  end

  def list_seeded_courses_for_realm(_realm_id), do: []

  @doc "Returns whether a seeded course may be moved to the given curriculum term."
  def curriculum_term_allowed?(%Course{} = course, term_number)
      when is_integer(term_number) and term_number > 0 do
    term_number in allowed_curriculum_terms(course)
  end

  def curriculum_term_allowed?(_course, _term_number), do: false

  def list_courses_for_realm(realm_id, opts \\ []) when is_binary(realm_id) do
    track = Keyword.get(opts, :track)
    program_type = Keyword.get(opts, :program_type)
    term_number = Keyword.get(opts, :term_number)
    metadata = realm_metadata(Repo.get(Realm, realm_id))

    courses =
      from(course in Course,
        where: course.realm_id == ^realm_id and course.status == :active,
        order_by: [asc: course.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&effective_course_for_metadata(&1, metadata))

    case program_type do
      nil ->
        if(track, do: Enum.filter(courses, &(&1.track == track)), else: courses)

      program_type ->
        Enum.filter(courses, &course_offered_in_term?(&1, program_type, track, term_number))
    end
  end

  @doc "Returns the courses actually offered to one enrollment in a specific term."
  def list_courses_for_term(%Enrollment{} = enrollment, term_number)
      when is_integer(term_number) and term_number > 0 do
    list_courses_for_realm(enrollment.realm_id,
      program_type: enrollment.program_type,
      track: enrollment.track,
      term_number: term_number
    )
  end

  def list_courses_for_term(_enrollment, _term_number), do: []

  def enroll_in_course(character_id, term_id, course_id, opts \\ [])
      when is_binary(character_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      term =
        Term
        |> where([t], t.id == ^term_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      character = lock_character!(character_id)

      enrollment =
        Enrollment
        |> where([enrollment], enrollment.id == ^term.enrollment_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      realm = lock_realm!(enrollment.realm_id)

      course =
        Course
        |> where([course], course.id == ^course_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      effective_course = effective_course_for_metadata(course, realm_metadata(realm))

      cond do
        term.status != :active ->
          Repo.rollback(enrollment_changeset("term is not active"))

        term_progress(term).phase != :enrollment ->
          Repo.rollback(enrollment_changeset("course selection is no longer open for this term"))

        enrollment.character_id != character.id ->
          Repo.rollback(enrollment_changeset("term does not belong to this character"))

        enrollment.realm_id != character.realm_id or course.realm_id != character.realm_id ->
          Repo.rollback(enrollment_changeset("course and term must belong to the same realm"))

        course.status != :active ->
          Repo.rollback(enrollment_changeset("course is not active"))

        not is_nil(course.track) and course.track != enrollment.track ->
          Repo.rollback(enrollment_changeset("course does not match the active study track"))

        not course_offered_in_term?(
          effective_course,
          enrollment.program_type,
          enrollment.track,
          term.term_number
        ) ->
          Repo.rollback(enrollment_changeset("course is not offered in this term"))

        true ->
          :ok
      end

      %CourseEnrollment{}
      |> CourseEnrollment.changeset(%{
        term_id: term_id,
        course_id: course_id,
        character_id: character_id,
        status: :enrolled,
        enrolled_at: now,
        metadata: %{}
      })
      |> Repo.insert!()
    end)
    |> normalize_transaction_result()
  end

  def list_course_enrollments_for_term(term_id) when is_binary(term_id) do
    Repo.all(
      from course_enrollment in CourseEnrollment,
        where: course_enrollment.term_id == ^term_id,
        order_by: [asc: course_enrollment.enrolled_at],
        preload: [:course]
    )
  end

  def grade_course_enrollment(course_enrollment_id, grade, opts \\ [])
      when is_binary(course_enrollment_id) and is_integer(grade) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      ce =
        CourseEnrollment
        |> where([ce], ce.id == ^course_enrollment_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if ce.status != :enrolled do
        Repo.rollback(enrollment_changeset("course enrollment is not active"))
      end

      ce
      |> CourseEnrollment.changeset(%{
        grade: grade,
        status: :completed,
        metadata: Map.put(ce.metadata || %{}, "graded_at", DateTime.to_iso8601(now))
      })
      |> Repo.update!()
    end)
    |> normalize_transaction_result()
  end

  def seed_courses_for_realm(realm_id) when is_binary(realm_id) do
    seeded = default_seeded_courses()

    Enum.map(seeded, fn attrs ->
      case Repo.get_by(Course, realm_id: realm_id, source: :seeded, title: attrs.title) do
        nil ->
          %Course{}
          |> Course.changeset(Map.put(attrs, :realm_id, realm_id))
          |> Repo.insert()

        %Course{} = course ->
          {:ok, course}
      end
    end)
  end

  def complete_due_enrollments(now \\ DateTime.utc_now()) do
    Enrollment
    |> where(
      [enrollment],
      enrollment.status == :active and enrollment.expected_completion_at <= ^now
    )
    |> Repo.all()
    |> Enum.map(fn enrollment ->
      complete_enrollment_by_id(enrollment.id, now: now, force: true)
    end)
  end

  defp reconcile_elapsed_terms!(%Enrollment{} = enrollment, now) do
    terms = locked_terms_for_enrollment(enrollment.id)

    Enum.each(terms, fn term ->
      schedule = term_schedule(enrollment, term.term_number)

      if term.status == :active and term_due?(schedule, now) do
        fail_missed_term!(term, schedule)
      end
    end)

    existing_term_numbers =
      enrollment.id
      |> locked_terms_for_enrollment()
      |> Enum.map(& &1.term_number)
      |> MapSet.new()

    required_term_count(enrollment.program_type)
    |> then(fn term_count ->
      if term_count > 0 do
        Enum.each(1..term_count, fn term_number ->
          schedule = term_schedule(enrollment, term_number)

          if not MapSet.member?(existing_term_numbers, term_number) and term_due?(schedule, now) do
            insert_missed_term!(enrollment, term_number, schedule)
          end
        end)
      end
    end)

    locked_terms_for_enrollment(enrollment.id)
  end

  defp locked_terms_for_enrollment(enrollment_id) do
    Repo.all(
      from term in Term,
        where: term.enrollment_id == ^enrollment_id,
        order_by: [asc: term.term_number],
        lock: "FOR UPDATE"
    )
  end

  defp term_due?(%{ends_at: %DateTime{} = ends_at}, %DateTime{} = now),
    do: DateTime.compare(ends_at, now) != :gt

  defp term_due?(_schedule, _now), do: false

  defp fail_missed_term!(%Term{} = term, schedule) do
    term
    |> Term.changeset(%{
      status: :failed,
      ended_at: schedule.ends_at,
      metadata:
        term.metadata
        |> missed_term_metadata(schedule)
    })
    |> Repo.update!()
  end

  defp insert_missed_term!(%Enrollment{} = enrollment, term_number, schedule) do
    %Term{}
    |> Term.changeset(%{
      enrollment_id: enrollment.id,
      realm_id: enrollment.realm_id,
      term_number: term_number,
      status: :failed,
      started_at: schedule.starts_at,
      ended_at: schedule.ends_at,
      metadata: missed_term_metadata(%{}, schedule)
    })
    |> Repo.insert!()
  end

  defp term_metadata(phase, schedule) do
    %{
      "phase" => phase,
      "lectures_attended" => 0,
      "lectures_required" => @lectures_per_term,
      "club_events_required" => @club_events_for_merit,
      "scheduled_start_at" => DateTime.to_iso8601(schedule.starts_at),
      "scheduled_end_at" => DateTime.to_iso8601(schedule.ends_at)
    }
  end

  defp missed_term_metadata(metadata, schedule) do
    (metadata || %{})
    |> Map.merge(term_metadata("break", schedule))
    |> Map.put("failure_reason", "missed_final")
  end

  defp submit_midterm_locked!(%Term{} = term, score, now, metadata \\ nil) do
    progress = term_progress(term)

    cond do
      term.status != :active ->
        Repo.rollback(enrollment_changeset("term is not active"))

      progress.phase != :midterm ->
        Repo.rollback(enrollment_changeset("midterm is not open for this term"))

      score < 0 or score > 100 ->
        Repo.rollback(enrollment_changeset("exam score must be 0–100"))

      true ->
        term
        |> Term.changeset(%{
          metadata:
            (metadata || term.metadata || %{})
            |> Map.put("phase", "final")
            |> Map.put("midterm_score", score)
            |> Map.put("midterm_submitted_at", DateTime.to_iso8601(now))
        })
        |> Repo.update!()
    end
  end

  defp submit_final_locked!(
         %Term{} = term,
         %Enrollment{} = enrollment,
         score,
         now,
         metadata \\ nil
       ) do
    progress = term_progress(term)

    cond do
      term.status != :active ->
        Repo.rollback(enrollment_changeset("term is not active"))

      progress.phase != :final ->
        Repo.rollback(enrollment_changeset("final is not open for this term"))

      score < 0 or score > 100 ->
        Repo.rollback(enrollment_changeset("exam score must be 0–100"))

      not is_integer(progress.midterm_score) and not midterm_skipped?(enrollment, progress) ->
        Repo.rollback(enrollment_changeset("midterm must be completed before the final"))

      true ->
        term_score = final_term_score(enrollment, progress, score)

        metadata =
          (metadata || term.metadata || %{})
          |> Map.put("phase", "break")
          |> Map.put("final_score", score)
          |> Map.put("final_submitted_at", DateTime.to_iso8601(now))

        updated_term =
          term
          |> Term.changeset(%{
            exam_score: term_score,
            status: :completed,
            ended_at: now,
            metadata: metadata
          })
          |> Repo.update!()

        complete_course_enrollments!(updated_term.id, enrollment.character_id, term_score, now)
        _updated_enrollment = sync_enrollment_academic_metadata!(enrollment)
        updated_term
    end
  end

  defp expire_exam_attempt_locked!(
         %Term{} = term,
         %Enrollment{program_type: :basic_education},
         :midterm,
         metadata,
         now
       ) do
    term
    |> Term.changeset(%{
      metadata:
        metadata
        |> Map.put("phase", "final")
        |> Map.put("midterm_skipped", true)
        |> Map.put("midterm_skipped_at", DateTime.to_iso8601(now))
        |> Map.put("midterm_timeout_at", DateTime.to_iso8601(now))
    })
    |> Repo.update!()
  end

  defp expire_exam_attempt_locked!(
         %Term{} = term,
         %Enrollment{} = enrollment,
         phase,
         metadata,
         now
       ) do
    updated_term =
      term
      |> Term.changeset(%{
        status: :failed,
        ended_at: now,
        metadata:
          metadata
          |> Map.put("phase", "break")
          |> Map.put("failure_reason", "exam_timeout")
          |> Map.put("exam_timeout_phase", exam_phase_name(phase))
      })
      |> Repo.update!()

    _updated_enrollment = sync_enrollment_academic_metadata!(enrollment)
    updated_term
  end

  defp current_exam_attempt(%Term{} = term, phase) do
    case Map.get(term.metadata || %{}, @exam_attempt_metadata_key) do
      %{
        "id" => attempt_id,
        "phase" => stored_phase,
        "deadline_at" => deadline_at,
        "status" => "open"
      } = attempt
      when is_binary(attempt_id) and is_binary(stored_phase) and is_binary(deadline_at) ->
        cond do
          stored_phase != exam_phase_name(phase) ->
            :invalid

          true ->
            case DateTime.from_iso8601(deadline_at) do
              {:ok, parsed_deadline, _utc_offset} -> {:open, attempt, parsed_deadline}
              _other -> :invalid
            end
        end

      %{"status" => "open"} ->
        :invalid

      _other ->
        :none
    end
  end

  defp mark_exam_attempt(metadata, phase, status, timestamp_key, now) when is_map(metadata) do
    phase_name = exam_phase_name(phase)

    case Map.get(metadata, @exam_attempt_metadata_key) do
      %{"phase" => stored_phase, "status" => "open"} = attempt
      when stored_phase == phase_name ->
        Map.put(
          metadata,
          @exam_attempt_metadata_key,
          attempt
          |> Map.put("status", status)
          |> Map.put(timestamp_key, DateTime.to_iso8601(now))
        )

      _other ->
        metadata
    end
  end

  defp mark_exam_attempt(_metadata, _phase, _status, _timestamp_key, _now), do: %{}

  defp normalize_exam_phase(:midterm), do: {:ok, :midterm}
  defp normalize_exam_phase(:final), do: {:ok, :final}
  defp normalize_exam_phase("midterm"), do: {:ok, :midterm}
  defp normalize_exam_phase("final"), do: {:ok, :final}
  defp normalize_exam_phase(_phase), do: {:error, :academy_exam_unavailable}

  defp exam_phase_name(:midterm), do: "midterm"
  defp exam_phase_name(:final), do: "final"

  defp schedule_exam_deadline!(%Term{} = term, phase, attempt_id, %DateTime{} = deadline_at) do
    %{
      "term_id" => term.id,
      "phase" => exam_phase_name(phase),
      "attempt_id" => attempt_id
    }
    |> ExamDeadlineWorker.new(
      schedule_in: max(DateTime.diff(deadline_at, DateTime.utc_now(), :second), 0)
    )
    |> Oban.insert!()
  end

  defp lock_exam_term(term_id) do
    term =
      Term
      |> where([term], term.id == ^term_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case term do
      nil ->
        nil

      %Term{} = term ->
        enrollment =
          Enrollment
          |> where([enrollment], enrollment.id == ^term.enrollment_id)
          |> lock("FOR UPDATE")
          |> Repo.one()

        case enrollment do
          %Enrollment{} = enrollment -> {term, enrollment}
          nil -> nil
        end
    end
  end

  defp lock_term_for_character!(term_id, character_id) do
    term =
      Term
      |> where([term], term.id == ^term_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    character = lock_character!(character_id)

    enrollment =
      Enrollment
      |> where([enrollment], enrollment.id == ^term.enrollment_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    cond do
      enrollment.character_id != character.id ->
        Repo.rollback(enrollment_changeset("term does not belong to this character"))

      enrollment.realm_id != character.realm_id ->
        Repo.rollback(enrollment_changeset("term does not belong to this character"))

      enrollment.status != :active ->
        Repo.rollback(enrollment_changeset("enrollment is not active"))

      true ->
        {term, enrollment}
    end
  end

  defp complete_course_enrollments!(term_id, character_id, grade, now) do
    CourseEnrollment
    |> where(
      [course_enrollment],
      course_enrollment.term_id == ^term_id and course_enrollment.character_id == ^character_id and
        course_enrollment.status == :enrolled
    )
    |> Repo.all()
    |> Enum.each(fn course_enrollment ->
      final_grade = course_grade(course_enrollment, grade)

      course_enrollment
      |> CourseEnrollment.changeset(%{
        grade: final_grade,
        status: :completed,
        metadata:
          (course_enrollment.metadata || %{})
          |> Map.put("graded_at", DateTime.to_iso8601(now))
          |> Map.put("office_hours_grade_applied", final_grade - grade)
      })
      |> Repo.update!()
    end)
  end

  defp course_grade(course_enrollment, grade) do
    min(grade + office_hours_grade_bonus(course_enrollment), 100)
  end

  defp office_hours_grade_bonus(course_enrollment) do
    if office_hours_attended?(course_enrollment), do: 5, else: 0
  end

  defp office_hours_attended?(%CourseEnrollment{} = course_enrollment) do
    truthy_metadata?(course_enrollment.metadata || %{}, "office_hours_attended")
  end

  defp office_hours_instructor_key(%Course{source: :seeded, npc_professor_code: code})
       when is_binary(code) and byte_size(code) > 0,
       do: "npc:#{code}"

  defp office_hours_instructor_key(%Course{publication_id: publication_id})
       when is_binary(publication_id) do
    case Repo.get(Publication, publication_id) do
      %Publication{author_character_id: character_id} when is_binary(character_id) ->
        "professor:#{character_id}"

      _other ->
        "publication:#{publication_id}"
    end
  end

  defp office_hours_instructor_key(%Course{id: course_id}), do: "course:#{course_id}"

  defp record_office_hours_relationship(metadata, instructor_key, course_id, now) do
    relationships = Map.get(metadata, "instructor_relationships", %{})
    relationships = if(is_map(relationships), do: relationships, else: %{})
    relationship = Map.get(relationships, instructor_key, %{})
    relationship = if(is_map(relationship), do: relationship, else: %{})

    updated_relationship =
      relationship
      |> Map.put("office_hours", positive_or_zero(Map.get(relationship, "office_hours")) + 1)
      |> Map.put("score", positive_or_zero(Map.get(relationship, "score")) + 5)
      |> Map.put("last_course_id", course_id)
      |> Map.put("last_office_hours_at", DateTime.to_iso8601(now))

    Map.put(
      metadata,
      "instructor_relationships",
      Map.put(relationships, instructor_key, updated_relationship)
    )
  end

  defp sync_enrollment_academic_metadata!(%Enrollment{} = enrollment) do
    stats = academic_stats(list_terms_for_enrollment(enrollment.id))

    enrollment
    |> Enrollment.changeset(%{
      metadata:
        (enrollment.metadata || %{})
        |> Map.put("gpa", stats.gpa)
        |> Map.put("completed_terms", stats.completed_terms)
        |> Map.put("failed_terms", stats.failed_terms)
        |> Map.put("club_attendance_eligible", stats.ranking_eligible?)
    })
    |> Repo.update!()
  end

  defp academic_stats(terms) when is_list(terms) do
    completed_terms = Enum.filter(terms, &(&1.status == :completed))

    scored_terms =
      Enum.filter(completed_terms, fn term ->
        is_integer(term.exam_score)
      end)

    gpa =
      case scored_terms do
        [] ->
          nil

        terms ->
          terms
          |> Enum.map(& &1.exam_score)
          |> Enum.sum()
          |> Kernel./(length(terms))
          |> Float.round(2)
      end

    %{
      gpa: gpa,
      completed_terms: length(completed_terms),
      failed_terms: Enum.count(terms, &(&1.status == :failed)),
      ranking_eligible?:
        completed_terms != [] and Enum.all?(completed_terms, &club_requirement_met?/1)
    }
  end

  defp club_requirement_met?(%Term{} = term) do
    metadata = term.metadata || %{}

    positive_or_zero(Map.get(metadata, "club_events_attended", 0)) >=
      positive_or_default(
        Map.get(metadata, "club_events_required", @club_events_for_merit),
        @club_events_for_merit
      )
  end

  defp midterm_skipped?(%Enrollment{program_type: :basic_education}, %{midterm_skipped?: true}),
    do: true

  defp midterm_skipped?(_enrollment, _progress), do: false

  defp final_term_score(_enrollment, %{midterm_score: score} = progress, final_score)
       when is_integer(score) do
    score
    |> then(&div(&1 * 40 + final_score * 60, 100))
    |> min(progress.lecture_final_ceiling)
  end

  defp final_term_score(%Enrollment{program_type: :basic_education}, progress, final_score) do
    min(final_score, min(@basic_final_without_midterm_cap, progress.lecture_final_ceiling))
  end

  defp graduation_metadata(%Enrollment{} = enrollment, outcome_tier) do
    leaderboard_entry =
      enrollment
      |> cohort_leaderboard()
      |> Enum.find(&(&1.enrollment.id == enrollment.id))

    rank = leaderboard_entry && leaderboard_entry.rank
    cohort_size = (leaderboard_entry && leaderboard_entry.cohort_size) || 0
    ranking_eligible? = (leaderboard_entry && leaderboard_entry.ranking_eligible?) || false

    %{
      "cohort_rank" => rank,
      "cohort_size" => cohort_size,
      "ranking_eligible" => ranking_eligible?,
      # Rank-based rewards are finalized after the entire cohort closes. This
      # prevents an early worker from granting a scholarship, advisor pick, or
      # title before every peer's final score is present.
      "merit_scholarship_eligible" => false,
      "honors" => false,
      "academic_title" => academic_title_for(enrollment, outcome_tier, false),
      "valedictorian" => false
    }
  end

  defp academic_title_for(%Enrollment{program_type: :basic_education}, :distinction, _honors?),
    do: "Академские почести"

  defp academic_title_for(_enrollment, _outcome_tier, true), do: "Академские почести"
  defp academic_title_for(_enrollment, _outcome_tier, false), do: nil

  defp record_valedictorian_honors(metadata, %Enrollment{} = enrollment, %DateTime{} = now)
       when is_map(metadata) do
    if truthy_metadata?(metadata, "valedictorian") do
      metadata
      |> Map.put("valedictorian_title", "Валедикториан когорты #{cohort_key(enrollment)}")
      |> Map.put(
        "valedictorian_hall_of_fame_until",
        now
        |> DateTime.add(@valedictorian_hall_of_fame_duration_seconds, :second)
        |> DateTime.to_iso8601()
      )
    else
      metadata
    end
  end

  defp finalize_cohort_rewards!(%Enrollment{} = enrollment, %DateTime{} = now) do
    target_cohort_key = cohort_key(enrollment)

    cohort_enrollments =
      Repo.all(
        from candidate in Enrollment,
          where:
            candidate.realm_id == ^enrollment.realm_id and
              candidate.program_type == ^enrollment.program_type and
              candidate.status in [:active, :completed],
          lock: "FOR UPDATE"
      )
      |> Enum.filter(&(cohort_key(&1) == target_cohort_key))

    completed_enrollments = Enum.filter(cohort_enrollments, &(&1.status == :completed))
    cohort_open? = Enum.any?(cohort_enrollments, &(&1.status == :active))

    leaderboard_by_enrollment_id =
      if cohort_open? do
        %{}
      else
        enrollment
        |> cohort_leaderboard()
        |> Map.new(&{&1.enrollment.id, &1})
      end

    Enum.each(completed_enrollments, fn candidate ->
      metadata =
        if cohort_open? do
          provisional_cohort_reward_metadata(candidate.metadata, candidate, now)
        else
          final_cohort_reward_metadata(
            candidate.metadata,
            candidate,
            Map.get(leaderboard_by_enrollment_id, candidate.id),
            now
          )
        end

      candidate
      |> Enrollment.changeset(%{metadata: metadata})
      |> Repo.update!()
    end)

    Repo.get!(Enrollment, enrollment.id)
  end

  defp provisional_cohort_reward_metadata(metadata, %Enrollment{} = enrollment, now) do
    outcome_tier = outcome_tier_from_metadata(enrollment.metadata || %{})

    metadata
    |> Map.put("merit_scholarship_eligible", false)
    |> Map.put("honors", false)
    |> Map.put("academic_title", academic_title_for(enrollment, outcome_tier, false))
    |> valedictorian_award_metadata(enrollment, false, now)
  end

  defp final_cohort_reward_metadata(metadata, %Enrollment{} = enrollment, nil, now) do
    provisional_cohort_reward_metadata(metadata, enrollment, now)
  end

  defp final_cohort_reward_metadata(metadata, %Enrollment{} = enrollment, entry, now) do
    outcome_tier = outcome_tier_from_metadata(enrollment.metadata || %{})
    honors? = ranked_honors?(outcome_tier, entry)

    valedictorian? =
      valedictorian_outcome_eligible?(enrollment) and entry.ranking_eligible? and entry.rank == 1

    metadata
    |> Map.put("cohort_rank", entry.rank)
    |> Map.put("cohort_size", entry.cohort_size)
    |> Map.put("ranking_eligible", entry.ranking_eligible?)
    |> Map.put(
      "merit_scholarship_eligible",
      merit_scholarship_eligible?(enrollment, outcome_tier, entry)
    )
    |> Map.put("honors", honors?)
    |> Map.put("academic_title", academic_title_for(enrollment, outcome_tier, honors?))
    |> valedictorian_award_metadata(enrollment, valedictorian?, now)
  end

  defp ranked_honors?(outcome_tier, entry) do
    outcome_tier not in [:expulsion, :capstone_incomplete] and entry.ranking_eligible? and
      is_integer(entry.rank) and entry.rank <= top_slice_size(entry.cohort_size, 10)
  end

  defp valedictorian_outcome_eligible?(%Enrollment{} = enrollment) do
    outcome_tier_from_metadata(enrollment.metadata || %{}) not in [
      :expulsion,
      :capstone_incomplete
    ]
  end

  defp valedictorian_award_metadata(metadata, enrollment, true, now) do
    metadata
    |> Map.put("valedictorian", true)
    |> record_valedictorian_honors(enrollment, now)
  end

  defp valedictorian_award_metadata(metadata, _enrollment, false, _now) do
    metadata
    |> Map.put("valedictorian", false)
    |> Map.drop(["valedictorian_title", "valedictorian_hall_of_fame_until"])
  end

  defp merit_scholarship_eligible?(
         %Enrollment{program_type: :basic_education},
         outcome_tier,
         %{rank: rank, cohort_size: cohort_size, ranking_eligible?: true}
       )
       when outcome_tier in [:distinction, :pass] do
    outcome_tier == :distinction or rank <= top_slice_size(cohort_size, 4)
  end

  defp merit_scholarship_eligible?(_enrollment, _outcome_tier, _leaderboard_entry), do: false

  defp top_slice_size(size, divisor) when is_integer(size) and size > 0 and is_integer(divisor),
    do: div(size + divisor - 1, divisor)

  defp top_slice_size(_size, _divisor), do: 0

  defp truthy_metadata?(metadata, key) do
    Map.get(metadata, key) in [true, "true"]
  end

  defp outcome_tier_from_metadata(metadata) do
    case Map.get(metadata, "outcome_tier") do
      "distinction" -> :distinction
      "pass" -> :pass
      "probation" -> :probation
      "expulsion" -> :expulsion
      "capstone_incomplete" -> :capstone_incomplete
      _other -> nil
    end
  end

  defp derived_cohort_key(program_type, %DateTime{} = expected_completion_at) do
    "#{program_type}:#{Clock.world_time(expected_completion_at).year}"
  end

  defp derived_cohort_key(program_type, _expected_completion_at), do: "#{program_type}:unassigned"

  defp club_attendance_count(%Term{} = term, character_id)
       when is_binary(character_id) and not is_nil(term.started_at) do
    case club_window_opened_at(term) do
      %DateTime{} = opened_at ->
        Repo.aggregate(
          from(attendance in EventAttendance,
            join: event in Event,
            on: event.id == attendance.event_id,
            where:
              attendance.character_id == ^character_id and event.realm_id == ^term.realm_id and
                attendance.attended_at >= ^opened_at
          ),
          :count
        )

      nil ->
        0
    end
  end

  defp club_attendance_count(_term, _character_id), do: 0

  defp club_window_opened_at(%Term{} = term) do
    case Map.get(term.metadata || %{}, "club_window_opened_at") do
      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, opened_at, _offset} -> opened_at
          {:error, _reason} -> nil
        end

      _other ->
        nil
    end
  end

  defp lecture_material_for(attended) when is_integer(attended) and attended >= 0,
    do: Enum.at(@lecture_material, attended)

  defp lecture_material_for(_attended), do: nil

  defp exam_question_specs(%Enrollment{track: track}) when track in @tracks do
    @exam_questions ++ [Map.fetch!(@applied_exam_questions, track)]
  end

  defp exam_question_specs(_enrollment),
    do: @exam_questions ++ [Map.fetch!(@applied_exam_questions, :general)]

  defp lecture_presentation(prompt, attended) do
    %{
      key: prompt.key,
      number: attended + 1,
      title: prompt.title,
      body: prompt.body,
      questions:
        Enum.map(prompt.questions, fn question ->
          %{
            key: question.key,
            label: question.label,
            options: question.options
          }
        end)
    }
  end

  defp lecture_correct_answers(prompt, answers) do
    Enum.count(prompt.questions, fn question ->
      Map.get(answers, question.key) == question.answer
    end)
  end

  defp lecture_results(metadata) when is_map(metadata) do
    case Map.get(metadata, "lecture_results", []) do
      results when is_list(results) -> Enum.filter(results, &is_map/1)
      _other -> []
    end
  end

  defp lecture_results(_metadata), do: []

  defp lecture_final_ceiling(metadata) when is_map(metadata) do
    lecture_final_ceiling_for(
      positive_or_zero(Map.get(metadata, "lectures_attended", 0)),
      positive_or_default(
        Map.get(metadata, "lectures_required", @lectures_per_term),
        @lectures_per_term
      )
    )
  end

  defp lecture_final_ceiling_for(attended, required)
       when is_integer(attended) and is_integer(required) and required > 0 do
    attended = min(max(attended, 0), required)

    min(
      100,
      @lecture_base_final_ceiling +
        div(attended * (100 - @lecture_base_final_ceiling), required)
    )
  end

  defp lecture_final_ceiling_for(_attended, _required), do: @lecture_base_final_ceiling

  defp normalize_term_phase("enrollment"), do: :enrollment
  defp normalize_term_phase("lectures"), do: :lectures
  defp normalize_term_phase("club_window"), do: :club_window
  defp normalize_term_phase("midterm"), do: :midterm
  defp normalize_term_phase("final"), do: :final
  defp normalize_term_phase("break"), do: :break
  defp normalize_term_phase(_phase), do: :lectures

  defp positive_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp positive_or_zero(_value), do: 0

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp start_program(%Character{} = character, program_type, track, attrs, opts) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())
    duration_game_days = Keyword.get(opts, :duration_game_days, default_duration(program_type))
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      character = lock_character!(character.id)

      validate_program_start!(character, program_type, track, attrs)
      validate_program_cooldown!(character, program_type, now)

      expected_completion_at = Clock.arrival_at(now, duration_game_days)
      funding_type = Keyword.get(opts, :funding_type, default_funding(program_type, character))
      retraining_source = retraining_source_specialization(character, program_type)

      enrollment =
        %Enrollment{}
        |> Enrollment.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          program_type: program_type,
          track: track,
          funding_type: funding_type,
          started_at: now,
          expected_completion_at: expected_completion_at,
          metadata:
            enrollment_metadata(
              program_type,
              track,
              attrs,
              duration_game_days,
              expected_completion_at
            )
            |> record_retraining_source(retraining_source)
        })
        |> Repo.insert!()

      job =
        %{"enrollment_id" => enrollment.id}
        |> CompleteEnrollmentWorker.new(
          schedule_in: max(DateTime.diff(expected_completion_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{enrollment: enrollment, job: job}
    end)
    |> normalize_transaction_result()
  end

  defp validate_program_start!(%Character{} = character, :basic_education, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      completed_program?(character.id, :basic_education) ->
        Repo.rollback(enrollment_changeset("basic education has already been completed"))

      true ->
        :ok
    end
  end

  defp validate_program_start!(%Character{} = character, :academy_core, track, attrs) do
    current_specialization = active_specialization(character.id)

    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :basic_education) ->
        Repo.rollback(enrollment_changeset("basic education must be completed first"))

      not academy_core_admission_permitted?(character.id) ->
        Repo.rollback(
          enrollment_changeset("probation graduates require an active professor recommendation")
        )

      track not in @tracks ->
        Repo.rollback(enrollment_changeset("academy track is invalid"))

      not is_nil(current_specialization) and not completed_program?(character.id, :academy_core) ->
        Repo.rollback(
          enrollment_changeset(
            "active specialization is not eligible for Academy Core retraining"
          )
        )

      true ->
        validate_track_attrs!(track, attrs)
        validate_retraining!(current_specialization, track, attrs)
    end
  end

  defp validate_program_start!(%Character{} = character, :extended_study, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :academy_core) ->
        Repo.rollback(enrollment_changeset("academy core study must be completed first"))

      true ->
        :ok
    end
  end

  defp validate_program_start!(%Character{} = character, :academia, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :academy_core) ->
        Repo.rollback(enrollment_changeset("academy core study must be completed first"))

      true ->
        :ok
    end
  end

  defp validate_program_cooldown!(
         %Character{} = character,
         :basic_education,
         %DateTime{} = now
       ) do
    case latest_basic_expulsion(character.id) do
      %Enrollment{completed_at: %DateTime{} = completed_at} ->
        reenrollment_at = Clock.arrival_at(completed_at, @basic_reenrollment_cooldown_game_days)

        if DateTime.compare(now, reenrollment_at) == :lt do
          Repo.rollback(
            enrollment_changeset("basic education re-enrollment is still on a one-year cooldown")
          )
        end

      _other ->
        :ok
    end
  end

  defp validate_program_cooldown!(_character, _program_type, _now), do: :ok

  defp validate_track_attrs!(:wizardry, attrs) do
    primary_school = normalize_school(Map.get(attrs, "primary_school"))
    secondary_school = normalize_school(Map.get(attrs, "secondary_school"))

    cond do
      is_nil(primary_school) or is_nil(secondary_school) ->
        Repo.rollback(enrollment_changeset("wizardry requires two valid schools"))

      primary_school == secondary_school ->
        Repo.rollback(enrollment_changeset("wizardry schools must be distinct"))

      Spells.opposed_schools?(primary_school, secondary_school) ->
        Repo.rollback(enrollment_changeset("wizardry schools are opposed and cannot be combined"))

      true ->
        :ok
    end
  end

  defp validate_track_attrs!(_track, _attrs), do: :ok

  defp validate_retraining!(%Specialization{track: :wizardry} = specialization, :wizardry, attrs) do
    previous_schools =
      [specialization.primary_school, specialization.secondary_school]
      |> Enum.reject(&is_nil/1)

    selected_schools =
      [
        normalize_school(Map.get(attrs, "primary_school")),
        normalize_school(Map.get(attrs, "secondary_school"))
      ]
      |> Enum.reject(&is_nil/1)

    if Enum.count(selected_schools, &(&1 in previous_schools)) > 1 do
      Repo.rollback(
        enrollment_changeset("wizardry retraining may overlap with at most one prior school")
      )
    end
  end

  defp validate_retraining!(_specialization, _track, _attrs), do: :ok

  defp maybe_upsert_specialization!(
         %Enrollment{program_type: :academy_core, track: track} = enrollment,
         now
       )
       when track in @tracks do
    previous_specialization = retire_retraining_specialization!(enrollment, now)

    attrs = %{
      character_id: enrollment.character_id,
      realm_id: enrollment.realm_id,
      track: track,
      status: :active,
      started_at: now,
      primary_school: normalize_school(enrollment.metadata["primary_school"]),
      secondary_school: normalize_school(enrollment.metadata["secondary_school"]),
      metadata:
        %{"source_enrollment_id" => enrollment.id}
        |> record_retired_specialization(previous_specialization)
    }

    %Specialization{}
    |> Specialization.changeset(attrs)
    |> Repo.insert!()
  end

  defp maybe_upsert_specialization!(_enrollment, _now), do: nil

  defp retire_retraining_specialization!(%Enrollment{} = enrollment, now) do
    source_id = Map.get(enrollment.metadata || %{}, "retraining_from_specialization_id")

    active_specialization =
      Specialization
      |> where(
        [specialization],
        specialization.character_id == ^enrollment.character_id and
          specialization.status == :active
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    case {source_id, active_specialization} do
      {nil, nil} ->
        nil

      {source_id, %Specialization{id: ^source_id} = specialization} when is_binary(source_id) ->
        specialization
        |> Specialization.changeset(%{
          status: :retired,
          ended_at: now,
          metadata:
            Map.put(
              specialization.metadata || %{},
              "retired_by_enrollment_id",
              enrollment.id
            )
        })
        |> Repo.update!()

      _other ->
        Repo.rollback(enrollment_changeset("retraining specialization is unavailable"))
    end
  end

  defp completed_program?(character_id, program_type) do
    Repo.exists?(
      from enrollment in Enrollment,
        where:
          enrollment.character_id == ^character_id and enrollment.program_type == ^program_type and
            enrollment.status == :completed
    )
  end

  defp latest_basic_expulsion(character_id) do
    Enrollment
    |> where(
      [enrollment],
      enrollment.character_id == ^character_id and enrollment.program_type == :basic_education and
        enrollment.status == :failed
    )
    |> order_by([enrollment], desc: enrollment.completed_at, desc: enrollment.inserted_at)
    |> Repo.all()
    |> Enum.find(fn enrollment ->
      Map.get(enrollment.metadata || %{}, "outcome_tier") == "expulsion"
    end)
  end

  defp academy_core_admission_permitted?(character_id) do
    case latest_completed_basic_enrollment(character_id) do
      %Enrollment{metadata: metadata} ->
        case Map.get(metadata || %{}, "outcome_tier") do
          "probation" ->
            active_professor_recommendation?(metadata || %{}) or
              active_academy_head_admission?(metadata || %{})

          _other ->
            true
        end

      nil ->
        false
    end
  end

  defp latest_completed_basic_enrollment(character_id) do
    Repo.one(
      from enrollment in Enrollment,
        where:
          enrollment.character_id == ^character_id and
            enrollment.program_type == :basic_education and enrollment.status == :completed,
        order_by: [desc: enrollment.completed_at, desc: enrollment.inserted_at],
        limit: 1
    )
  end

  defp active_professor_recommendation?(metadata) do
    case Map.get(metadata, "professor_recommendation") do
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

  # Academy Head admission is a separate, durable authority record written
  # only by the scoped Academia headship command. Keeping this predicate local
  # avoids coupling enrollment validation to the headship read model.
  defp active_academy_head_admission?(metadata) do
    case Map.get(metadata, "academy_head_admission") do
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

  defp completion_xp(%Enrollment{program_type: :basic_education}), do: 100
  defp completion_xp(%Enrollment{program_type: :academy_core}), do: 250
  defp completion_xp(%Enrollment{program_type: :extended_study}), do: 180
  defp completion_xp(%Enrollment{program_type: :academia}), do: 320

  defp default_duration(:basic_education), do: 3640
  defp default_duration(:academy_core), do: 1092
  defp default_duration(:extended_study), do: 728
  defp default_duration(:academia), do: 1456

  defp default_funding(:basic_education, _character), do: :none

  defp default_funding(:academy_core, %Character{} = character) do
    if merit_scholarship_available?(character), do: :grant, else: :self_funded
  end

  defp default_funding(_program_type, _character), do: :self_funded

  defp merit_scholarship_available?(%Character{} = character) do
    character.id
    |> enrollment_history()
    |> Enum.any?(fn enrollment ->
      enrollment.program_type == :basic_education and enrollment.status == :completed and
        truthy_metadata?(enrollment.metadata || %{}, "merit_scholarship_eligible")
    end)
  end

  defp enrollment_metadata(program_type, track, attrs, duration_game_days, expected_completion_at) do
    attrs
    |> Map.take(["primary_school", "secondary_school", "notes"])
    |> Map.put("program_type", Atom.to_string(program_type))
    |> then(fn metadata ->
      if(track, do: Map.put(metadata, "track", Atom.to_string(track)), else: metadata)
    end)
    |> Map.put("duration_game_days", duration_game_days)
    |> Map.put("cohort_key", derived_cohort_key(program_type, expected_completion_at))
  end

  defp retraining_source_specialization(%Character{} = character, :academy_core),
    do: active_specialization(character.id)

  defp retraining_source_specialization(_character, _program_type), do: nil

  defp record_retraining_source(metadata, %Specialization{} = specialization) do
    metadata
    |> Map.put("retraining_from_specialization_id", specialization.id)
    |> Map.put("retraining_from_track", Atom.to_string(specialization.track))
  end

  defp record_retraining_source(metadata, _specialization), do: metadata

  defp record_retired_specialization(metadata, %Specialization{} = specialization),
    do: Map.put(metadata, "retraining_from_specialization_id", specialization.id)

  defp record_retired_specialization(metadata, _specialization), do: metadata

  defp wizard_specialization_permits?(character_id, school_code) do
    case active_specialization(character_id) do
      %Specialization{track: :wizardry} = specialization ->
        Atom.to_string(specialization.primary_school) == school_code or
          Atom.to_string(specialization.secondary_school) == school_code

      _other ->
        false
    end
  end

  defp completed_enrollments_for_character(character_id, opts \\ []) do
    query =
      from enrollment in Enrollment,
        where: enrollment.character_id == ^character_id and enrollment.status == :completed,
        order_by: [desc: enrollment.completed_at, desc: enrollment.inserted_at]

    query =
      if Keyword.get(opts, :lock?, false) do
        lock(query, "FOR UPDATE")
      else
        query
      end

    Repo.all(query)
  end

  defp valedictorian?(%Enrollment{metadata: metadata}),
    do: truthy_metadata?(metadata || %{}, "valedictorian")

  defp valedictorian?(_enrollment), do: false

  defp claimable_valedictorian_bonus?(%Enrollment{} = enrollment) do
    valedictorian?(enrollment) and not valedictorian_bonus_claimed?(enrollment)
  end

  defp valedictorian_bonus_claimed?(%Enrollment{metadata: metadata}) do
    case Map.get(metadata || %{}, "valedictorian_bonus") do
      %{"status" => "claimed"} -> true
      %{"spell_id" => spell_id} when is_binary(spell_id) -> true
      _other -> false
    end
  end

  defp bonus_school_codes(metadata) when is_map(metadata) do
    metadata
    |> Map.get(@valedictorian_bonus_schools_key, [])
    |> List.wrap()
    |> Enum.map(&normalize_school/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Atom.to_string/1)
    |> Enum.uniq()
  end

  defp bonus_school_codes(_metadata), do: []

  defp hall_of_fame_active?(%Enrollment{} = enrollment, %DateTime{} = now) do
    case hall_of_fame_until(enrollment) do
      %DateTime{} = expires_at -> DateTime.compare(expires_at, now) == :gt
      nil -> false
    end
  end

  defp legacy_hall_of_fame_until(%Enrollment{completed_at: %DateTime{} = completed_at}) do
    DateTime.add(completed_at, @valedictorian_hall_of_fame_duration_seconds, :second)
  end

  defp legacy_hall_of_fame_until(_enrollment), do: nil

  defp normalize_school(school) when school in @schools, do: school

  defp normalize_school(school) when is_binary(school) do
    case school do
      "fire" -> :fire
      "water" -> :water
      "earth" -> :earth
      "air" -> :air
      "life" -> :life
      "death" -> :death
      "chaos" -> :chaos
      "order" -> :order
      _other -> nil
    end
  end

  defp normalize_school(_school), do: nil

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

  defp lock_enrollment!(enrollment_id) do
    Enrollment
    |> where([enrollment], enrollment.id == ^enrollment_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_exam_attempt_result({:ok, result}), do: {:ok, result}

  defp normalize_exam_attempt_result({:error, %Changeset{} = changeset}),
    do: {:error, changeset}

  defp normalize_exam_attempt_result({:error, reason}) when is_atom(reason),
    do: {:error, reason}

  defp normalize_exam_attempt_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp enrollment_changeset(message) do
    %Enrollment{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp compute_outcome_tier(enrollment_id, :basic_education) do
    failed = failed_terms_count(enrollment_id)

    cond do
      failed >= 7 ->
        :expulsion

      failed >= 4 ->
        :probation

      true ->
        gpa = gpa_for_enrollment(enrollment_id) || 0.0

        if gpa >= 85 and failed <= 1 do
          :distinction
        else
          :pass
        end
    end
  end

  defp compute_outcome_tier(enrollment_id, :academy_core) do
    gpa = gpa_for_enrollment(enrollment_id) || 0.0
    failed = failed_terms_count(enrollment_id)

    cond do
      failed >= 2 -> :probation
      gpa >= 85 and failed == 0 -> :distinction
      true -> :pass
    end
  end

  defp compute_outcome_tier(_enrollment_id, _program_type), do: :pass

  defp academy_core_capstone_due?(
         %Enrollment{
           program_type: :academy_core,
           expected_completion_at: %DateTime{} = expected_completion_at
         },
         %DateTime{} = now
       ) do
    DateTime.compare(now, expected_completion_at) != :lt
  end

  defp academy_core_capstone_due?(_enrollment, _now), do: false

  defp academy_core_capstone_passed?(enrollment_id) do
    case Repo.get_by(Term,
           enrollment_id: enrollment_id,
           term_number: @academy_core_capstone_term_number
         ) do
      %Term{status: :completed, exam_score: score}
      when is_integer(score) and score >= @academy_core_passing_score ->
        true

      _other ->
        false
    end
  end

  defp completion_status(%Enrollment{program_type: :academy_core}, :capstone_incomplete),
    do: :failed

  defp completion_status(_enrollment, :expulsion), do: :failed
  defp completion_status(_enrollment, _outcome_tier), do: :completed

  defp award_completion_xp?(%Enrollment{program_type: :academy_core}, :failed), do: false
  defp award_completion_xp?(_enrollment, _completion_status), do: true

  defp eligible_for_specialization?(%Enrollment{program_type: :academy_core, status: :completed}),
    do: true

  defp eligible_for_specialization?(%Enrollment{program_type: :academy_core}), do: false
  defp eligible_for_specialization?(_enrollment), do: true

  defp record_capstone_status(
         metadata,
         %Enrollment{program_type: :academy_core},
         capstone_passed?
       ),
       do: Map.put(metadata, "capstone_passed", capstone_passed?)

  defp record_capstone_status(metadata, _enrollment, _capstone_passed?), do: metadata

  defp effective_course_for_metadata(%Course{} = course, metadata) do
    case curriculum_override_for_course(course, curriculum_overrides(metadata)) do
      %{"years" => years} ->
        syllabus = if is_map(course.syllabus), do: course.syllabus, else: %{}

        %{
          course
          | syllabus:
              syllabus
              |> Map.delete("year")
              |> Map.put("years", years)
        }

      _other ->
        course
    end
  end

  defp curriculum_override_for_course(%Course{} = course, overrides) when is_map(overrides) do
    with true <- course.source in [:seeded, "seeded"],
         %{} = override <- Map.get(overrides, course.id),
         [term_number] <- Map.get(override, "years"),
         true <- curriculum_term_allowed?(course, term_number) do
      override
    else
      _other -> nil
    end
  end

  defp curriculum_override_for_course(_course, _overrides), do: nil

  defp curriculum_overrides(metadata) when is_map(metadata) do
    case Map.get(metadata, @academy_curriculum_metadata_key) do
      curriculum when is_map(curriculum) ->
        case Map.get(curriculum, @academy_curriculum_overrides_key) do
          overrides when is_map(overrides) -> overrides
          _other -> %{}
        end

      _other ->
        %{}
    end
  end

  defp curriculum_overrides(_metadata), do: %{}

  defp allowed_curriculum_terms(%Course{source: source, track: track})
       when source in [:seeded, "seeded"] do
    case track do
      nil -> Enum.to_list(1..@program_term_counts.basic_education)
      _track -> Enum.to_list(1..@academy_core_capstone_term_number)
    end
  end

  defp allowed_curriculum_terms(_course), do: []

  defp scheduled_term_numbers(%Course{syllabus: syllabus}) when is_map(syllabus) do
    cond do
      is_integer(Map.get(syllabus, "year")) ->
        [Map.get(syllabus, "year")]

      is_list(Map.get(syllabus, "years")) ->
        Enum.filter(Map.get(syllabus, "years"), &(is_integer(&1) and &1 > 0))

      true ->
        []
    end
  end

  defp scheduled_term_numbers(_course), do: []

  defp realm_metadata(%Realm{metadata: metadata}) when is_map(metadata), do: metadata
  defp realm_metadata(_realm), do: %{}

  defp course_offered_in_term?(course, :basic_education, _track, term_number) do
    course_scheduled_for_term?(course, term_number) and
      case course.source do
        source when source in [:seeded, "seeded"] -> is_nil(course.track)
        source when source in [:published, "published"] -> is_nil(course.track)
        _other -> false
      end
  end

  defp course_offered_in_term?(course, :academy_core, track, term_number) do
    course_scheduled_for_term?(course, term_number) and
      case course.source do
        source when source in [:seeded, "seeded"] ->
          course.track == track

        source when source in [:published, "published"] ->
          is_nil(course.track) or course.track == track

        _other ->
          false
      end
  end

  defp course_offered_in_term?(course, program_type, track, term_number)
       when program_type in [:extended_study, :academia] do
    course_scheduled_for_term?(course, term_number) and
      course.source in [:published, "published"] and
      (is_nil(course.track) or course.track == track)
  end

  defp course_offered_in_term?(_course, _program_type, _track, _term_number), do: false

  defp course_scheduled_for_term?(course, term_number)
       when is_integer(term_number) and term_number > 0 do
    syllabus = course.syllabus || %{}

    cond do
      is_integer(Map.get(syllabus, "year")) ->
        Map.get(syllabus, "year") == term_number

      is_list(Map.get(syllabus, "years")) ->
        term_number in Map.get(syllabus, "years")

      true ->
        true
    end
  end

  defp course_scheduled_for_term?(_course, _term_number), do: true

  defp default_seeded_courses do
    [
      %{
        source: :seeded,
        title: "History of the Realm",
        npc_professor_code: "npc_historian",
        syllabus: %{"track" => nil, "years" => [1, 2]}
      },
      %{
        source: :seeded,
        title: "Elemental Literacy",
        npc_professor_code: "npc_elementalist",
        syllabus: %{"track" => nil, "years" => [1]}
      },
      %{
        source: :seeded,
        title: "Overworld Survival",
        npc_professor_code: "npc_ranger",
        syllabus: %{"track" => nil, "years" => [1, 2]}
      },
      %{
        source: :seeded,
        title: "Economic Basics",
        npc_professor_code: "npc_economist",
        syllabus: %{"track" => nil, "years" => [3, 4]}
      },
      %{
        source: :seeded,
        title: "Civic Law",
        npc_professor_code: "npc_magistrate",
        syllabus: %{"track" => nil, "years" => [5, 6]}
      },
      %{
        source: :seeded,
        title: "Latin Fundamentals",
        npc_professor_code: "npc_linguist",
        syllabus: %{"track" => nil, "years" => [7, 8, 9, 10]}
      },
      %{
        source: :seeded,
        title: "Incantation Construction I",
        npc_professor_code: "npc_wizard_1",
        track: :wizardry,
        syllabus: %{"year" => 1}
      },
      %{
        source: :seeded,
        title: "Dual-School Fundamentals",
        npc_professor_code: "npc_wizard_2",
        track: :wizardry,
        syllabus: %{"year" => 1, "focus" => "chosen_schools"}
      },
      %{
        source: :seeded,
        title: "Spellcraft Practicum",
        npc_professor_code: "npc_wizard_3",
        track: :wizardry,
        syllabus: %{"year" => 2, "focus" => "starter_spells"}
      },
      %{
        source: :seeded,
        title: "Incantation Construction II",
        npc_professor_code: "npc_wizard_4",
        track: :wizardry,
        syllabus: %{"year" => 2}
      },
      %{
        source: :seeded,
        title: "Arcane Mini-Thesis",
        npc_professor_code: "npc_wizard_5",
        track: :wizardry,
        syllabus: %{"year" => 3, "focus" => "capstone"}
      },
      %{
        source: :seeded,
        title: "Ingredients Taxonomy",
        npc_professor_code: "npc_alchemist_1",
        track: :alchemy,
        syllabus: %{"year" => 1}
      },
      %{
        source: :seeded,
        title: "Basic Brewing",
        npc_professor_code: "npc_alchemist_2",
        track: :alchemy,
        syllabus: %{"year" => 1}
      },
      %{
        source: :seeded,
        title: "Recipe Development Practicum",
        npc_professor_code: "npc_alchemist_3",
        track: :alchemy,
        syllabus: %{"year" => 2, "focus" => "starter_recipes"}
      },
      %{
        source: :seeded,
        title: "Alchemy Mini-Thesis",
        npc_professor_code: "npc_alchemist_4",
        track: :alchemy,
        syllabus: %{"year" => 3, "focus" => "capstone"}
      },
      %{
        source: :seeded,
        title: "Materials Science",
        npc_professor_code: "npc_master_1",
        track: :mastery,
        syllabus: %{"year" => 1}
      },
      %{
        source: :seeded,
        title: "Basic Forging",
        npc_professor_code: "npc_master_2",
        track: :mastery,
        syllabus: %{"year" => 1}
      },
      %{
        source: :seeded,
        title: "Toolcraft Practicum",
        npc_professor_code: "npc_master_3",
        track: :mastery,
        syllabus: %{"year" => 2, "focus" => "starter_tools"}
      },
      %{
        source: :seeded,
        title: "Mastery Mini-Thesis",
        npc_professor_code: "npc_master_4",
        track: :mastery,
        syllabus: %{"year" => 3, "focus" => "capstone"}
      }
    ]
  end
end
