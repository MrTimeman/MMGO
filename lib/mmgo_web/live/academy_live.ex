defmodule MMGOWeb.AcademyLive do
  @moduledoc """
  Scoped Academy hall: real enrollment, terms, courses, and examination links.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @track_options [
    {"Чародейство", "wizardry"},
    {"Алхимия", "alchemy"},
    {"Мастерство", "mastery"}
  ]

  @school_options [
    {"Огонь", "fire"},
    {"Вода", "water"},
    {"Земля", "earth"},
    {"Воздух", "air"},
    {"Жизнь", "life"},
    {"Смерть", "death"},
    {"Хаос", "chaos"},
    {"Порядок", "order"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:page_title, "Академия")
         |> assign(:error, nil)
         |> refresh_academy()}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, title_for(socket.assigns.live_action || :overview))}
  end

  @impl true
  def handle_event("change_program", %{"academy_program" => attrs}, socket) do
    params =
      socket.assigns.state
      |> program_params()
      |> Map.merge(attrs)

    {:noreply, assign(socket, :program_form, to_form(params, as: :academy_program))}
  end

  @impl true
  def handle_event("start_program", %{"academy_program" => attrs}, socket) do
    case Play.start_academy_program(socket.assigns.character, attrs) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Учебная запись открыта.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event(
        "claim_valedictorian_spell",
        %{"valedictorian_bonus" => %{"school" => school}},
        socket
      ) do
    case Play.claim_scoped_valedictorian_spell(socket.assigns.character, school) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Лауреатская печать внесена в вашу библиотеку заклинаний.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("claim_valedictorian_spell", _params, socket) do
    {:noreply, assign(socket, :error, error_message(:valedictorian_bonus_unavailable))}
  end

  @impl true
  def handle_event("begin_term", _params, socket) do
    case Play.begin_current_academy_term(socket.assigns.character) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Новый термин начат.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("enroll_course", %{"course-id" => course_id}, socket) do
    case Play.enroll_current_academy_course(socket.assigns.character, course_id) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Вы записаны на курс.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("attend_office_hours", %{"course-id" => course_id}, socket) do
    case Play.attend_current_course_office_hours(socket.assigns.character, course_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Приёмные часы внесены в ведомость курса.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("open_lecture_phase", _params, socket) do
    case Play.open_current_academy_lecture_phase(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Выбор курсов закрыт. Лекционный цикл открыт.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("close_lecture_phase", _params, socket) do
    case Play.close_current_academy_lecture_phase(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Лекционное окно закрыто, клубные события открыты.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("attend_lecture", _params, socket) do
    case socket.assigns.state.current_term do
      %{id: term_id} ->
        {:noreply, push_navigate(socket, to: ~p"/academy/lecture/#{term_id}")}

      nil ->
        {:noreply, assign(socket, :error, error_message(:academy_lecture_unavailable))}
    end
  end

  @impl true
  def handle_event("close_club_window", _params, socket) do
    case Play.close_current_academy_club_window(socket.assigns.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Клубное окно закрыто, ведомость передана на промежуточный экзамен.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_academy(socket)}

  @impl true
  def render(%{state: _state, live_action: :timetable} = assigns),
    do: timetable_room(assigns)

  def render(%{state: _state, live_action: :grades} = assigns),
    do: grades_room(assigns)

  def render(%{state: _state, live_action: :library} = assigns),
    do: library_room(assigns)

  def render(%{state: _state, live_action: :courses} = assigns),
    do: courses_room(assigns)

  def render(%{state: _state, live_action: :progress} = assigns),
    do: progress_room(assigns)

  def render(%{state: _state} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-screen" class="acd-screen academy-hall">
        <div class="academy-hall__vault" aria-hidden="true">
          <i></i><i></i><i></i>
        </div>

        <div class="acd-shell academy-hall__shell">
          <div class="academy-hall__topbar">
            <.link id="academy-back-to-map" navigate={~p"/map"} class="acd-exit academy-hall__exit">
              <span aria-hidden="true">←</span> Покинуть Академию
            </.link>
            <button
              id="academy-refresh"
              type="button"
              phx-click="refresh"
              class="academy-hall__bell"
              aria-label="Обновить академические записи"
              title="Позвать архивариуса"
            >
              <span aria-hidden="true">⌁</span> Архивариус
            </button>
          </div>

          <header class="academy-hall__atrium">
            <div class="academy-hall__lantern academy-hall__lantern--left" aria-hidden="true">
              <span></span>
            </div>
            <div class="academy-hall__lantern academy-hall__lantern--right" aria-hidden="true">
              <span></span>
            </div>
            <div class="academy-hall__crest" aria-hidden="true">
              <span>A</span>
            </div>
            <p class="acd-eyebrow">Большой холл · {action_label(@live_action || :overview)}</p>
            <h1>{academy_heading(@state)}</h1>
            <p class="academy-hall__motto">
              Искусство долговечно, память мира — каждая запись здесь скреплена печатью.
            </p>
          </header>

          <div :if={@error} id="academy-error" class="academy-hall__error">
            <span class="academy-hall__error-seal" aria-hidden="true">!</span>
            <p>{@error}</p>
          </div>

          <nav
            id="academy-navigation"
            class="academy-hall__doors"
            aria-label="Залы Академии"
          >
            <.link navigate={~p"/academy"} class="academy-hall__door">
              <span class="academy-hall__door-number">I</span>
              <span><strong>Холл</strong><small>регистратура</small></span>
            </.link>
            <.link navigate={~p"/academy/timetable"} class="academy-hall__door">
              <span class="academy-hall__door-number">II</span>
              <span><strong>Расписание</strong><small>колокола и занятия</small></span>
            </.link>
            <.link navigate={~p"/academy/grades"} class="academy-hall__door">
              <span class="academy-hall__door-number">III</span>
              <span><strong>Ведомость</strong><small>оценки и ранг</small></span>
            </.link>
            <.link navigate={~p"/academy/courses"} class="academy-hall__door">
              <span class="academy-hall__door-number">IV</span>
              <span><strong>Курсы</strong><small>аудитории</small></span>
            </.link>
            <.link navigate={~p"/academy/library"} class="academy-hall__door">
              <span class="academy-hall__door-number">V</span>
              <span><strong>Библиотека</strong><small>полки и гримуары</small></span>
            </.link>
            <.link navigate={~p"/academy/progress"} class="academy-hall__door">
              <span class="academy-hall__door-number">VI</span>
              <span><strong>Путь</strong><small>ступени образования</small></span>
            </.link>
            <.link navigate={~p"/academy/clubs"} class="academy-hall__door">
              <span class="academy-hall__door-number">VII</span>
              <span><strong>Клубы</strong><small>общества студентов</small></span>
            </.link>
            <.link navigate={~p"/academy/research"} class="academy-hall__door">
              <span class="academy-hall__door-number">VIII</span>
              <span><strong>Наука</strong><small>кафедры и тезисы</small></span>
            </.link>
            <.link navigate={~p"/academy/bulletin-board"} class="academy-hall__door">
              <span class="academy-hall__door-number">IX</span>
              <span><strong>Доска</strong><small>объявления</small></span>
            </.link>
          </nav>

          <section id="academy-status" class="academy-hall__registrar">
            <article class="academy-dossier">
              <div class="academy-dossier__pin" aria-hidden="true"></div>
              <p class="academy-paper__kicker">Личное дело студента</p>
              <%= if @state.enrollment do %>
                <h2 id="academy-enrollment">{program_label(@state.enrollment.program_type)}</h2>
                <p class="academy-dossier__line">
                  <span>Запись</span>
                  <strong>{enrollment_status(@state.enrollment.status)}</strong>
                </p>
                <p class="academy-dossier__line">
                  <span>Ожидаемое завершение</span>
                  <strong>{format_time(@state.enrollment.expected_completion_at)}</strong>
                </p>
                <p
                  :if={@state.specialization}
                  id="academy-specialization"
                  class="academy-dossier__specialization"
                >
                  Путь: {track_label(@state.specialization.track)}{school_suffix(
                    @state.specialization
                  )}
                </p>
                <p
                  :if={retraining_enrollment?(@state.enrollment)}
                  id="academy-retraining-enrollment"
                  class="academy-paper__annotation"
                >
                  Переподготовка идёт: прежняя специализация сохранится до выпуска, затем уйдёт в архив.
                </p>
              <% else %>
                <h2 id="academy-no-enrollment">Свободная запись</h2>
                <p class="academy-paper__body">
                  Ваше дело ждёт следующей ступени. Регистратор проверит завершённое обучение перед зачислением.
                </p>
                <p
                  :if={@state.latest_enrollment}
                  id="academy-last-outcome"
                  class="academy-paper__annotation"
                >
                  Последний выпуск: {program_label(@state.latest_enrollment.program_type)} · {outcome_label(
                    @state.academic_record && @state.academic_record.outcome_tier
                  )}
                </p>
              <% end %>
              <div class="academy-dossier__signature">
                <span>реестр Академии</span>
                <i aria-hidden="true">A</i>
              </div>
            </article>

            <article id="academy-progress-summary" class="academy-gradebook">
              <div class="academy-gradebook__spine" aria-hidden="true"></div>
              <div class="academy-gradebook__page">
                <p class="academy-paper__kicker">Учебная ведомость</p>
                <div class="academy-gradebook__gpa">
                  <span>Средний балл</span>
                  <strong>{gpa_label(@state.academic_record && @state.academic_record.gpa)}</strong>
                </div>
                <dl class="academy-gradebook__facts">
                  <div>
                    <dt>Провалено терминов</dt>
                    <dd>{record_failed_terms(@state.academic_record)}</dd>
                  </div>
                  <div>
                    <dt>Текущий термин</dt>
                    <dd>{term_label(@state.current_term)}</dd>
                  </div>
                </dl>
                <p
                  :if={@state.academic_record && @state.academic_record.cohort_rank}
                  id="academy-cohort-standing"
                  class="academy-gradebook__honor"
                >
                  Место в когорте: №{@state.academic_record.cohort_rank} из {@state.academic_record.cohort_size}
                </p>
                <p
                  :if={@state.academic_record && @state.academic_record.merit_scholarship_eligible?}
                  id="academy-merit-grant"
                  class="academy-gradebook__honor"
                >
                  Допущен к стипендии за заслуги.
                </p>
                <p
                  :if={@state.charity_stipend}
                  id="academy-charity-stipend"
                  class="academy-gradebook__honor"
                >
                  Стипендия Фонда Просвещения: {Map.get(@state.charity_stipend, "amount")} ◈.
                </p>
                <div
                  :if={@state.academic_titles != []}
                  id="academy-academic-titles"
                  class="academy-gradebook__titles"
                >
                  <p>Академические титулы</p>
                  <span
                    :for={title <- @state.academic_titles}
                    id={"academy-academic-title-#{title.enrollment_id}"}
                  >
                    {title.title}
                  </span>
                </div>
                <p
                  :if={@state.academic_record && @state.academic_record.valedictorian?}
                  id="academy-valedictorian"
                  class="academy-gradebook__honor"
                >
                  {@state.academic_record.valedictorian_title}
                </p>
                <div
                  :if={@state.valedictorian_honors != []}
                  id="academy-valedictorian-titles"
                  class="academy-gradebook__titles"
                >
                  <p>Лауреатские звания</p>
                  <span
                    :for={honor <- @state.valedictorian_honors}
                    id={"academy-valedictorian-title-#{honor.enrollment_id}"}
                  >
                    {honor.title}
                    <small :if={honor.hall_of_fame_until}>
                      · доска до {format_time(honor.hall_of_fame_until)}
                    </small>
                  </span>
                </div>
              </div>
            </article>
          </section>

          <section
            :if={@state.starter_outcomes}
            id="academy-starter-outcomes"
            class="academy-award-case"
          >
            <div class="academy-award-case__glass">
              <div class="academy-award-case__seal" aria-hidden="true">A</div>
              <div>
                <p class="acd-eyebrow">Выпускной набор</p>
                <h2>
                  {starter_track_label(@state.starter_outcomes)} · {starter_quality_label(
                    @state.starter_outcomes
                  )}
                </h2>
                <p
                  :if={starter_title(@state.starter_outcomes)}
                  id="academy-starter-title"
                  class="academy-award-case__title"
                >
                  Звание: {starter_title(@state.starter_outcomes)}
                </p>
                <p>
                  Награды уже внесены в мир: заклинания, рецепты и инструменты выданы по выпускной ведомости.
                </p>
              </div>
              <.link
                id="academy-open-starter-rewards"
                navigate={starter_destination(@state.starter_outcomes)}
                class="acd-btn acd-btn--primary"
              >
                Открыть набор
              </.link>
            </div>
            <ul id="academy-starter-reward-list" class="academy-award-case__shelf">
              <li
                :for={reward <- starter_rewards(@state.starter_outcomes)}
                id={"academy-starter-reward-#{starter_reward_id(reward)}"}
              >
                <span aria-hidden="true"></span>
                {starter_reward_label(reward)}
              </li>
            </ul>
            <p
              :if={starter_reagent_label(@state.starter_outcomes)}
              id="academy-starter-reagent"
              class="academy-award-case__reagent"
            >
              {starter_reagent_label(@state.starter_outcomes)}
            </p>
          </section>

          <section
            :if={@state.valedictorian_bonus}
            id="academy-valedictorian-bonus"
            class="academy-sealed-letter"
          >
            <div class="academy-sealed-letter__fold" aria-hidden="true"></div>
            <p class="academy-paper__kicker">Личная грамота ректора</p>
            <h2>{@state.valedictorian_bonus.title}</h2>
            <p class="academy-paper__body">
              Выберите одну школу для именной Лауреатской печати. Заклинание будет создано в вашей библиотеке.
            </p>
            <.form
              for={@valedictorian_form}
              id="academy-valedictorian-bonus-form"
              phx-submit="claim_valedictorian_spell"
              class="academy-paper-form academy-paper-form--compact"
            >
              <.input
                field={@valedictorian_form[:school]}
                type="select"
                label="Школа Лауреатской печати"
                options={school_options()}
              />
              <button
                id="academy-claim-valedictorian-spell"
                type="submit"
                class="academy-wax-button"
              >
                Получить заклинание
              </button>
            </.form>
          </section>

          <.academy_program_application
            :if={@state.enrollment == nil && @state.program_options != []}
            state={@state}
            program_form={@program_form}
          />

          <section :if={@state.enrollment} id="academy-terms" class="academy-term-ledger">
            <div class="academy-term-ledger__binding" aria-hidden="true">
              <i></i><i></i><i></i><i></i>
            </div>
            <div class="academy-term-ledger__page">
              <header class="academy-ledger-heading">
                <div>
                  <p class="academy-paper__kicker">Книга семестров</p>
                  <h2>Ведомость пути</h2>
                  <p id="academy-term-count">
                    Зафиксировано терминов: {length(@state.terms)} из {@state.required_terms}
                  </p>
                  <p
                    :if={@state.current_term_schedule}
                    id="academy-current-term-window"
                    class="academy-ledger-heading__note"
                  >
                    Текущий термин: {format_time(@state.current_term_schedule.starts_at)} — {format_time(
                      @state.current_term_schedule.ends_at
                    )}
                  </p>
                  <p
                    :if={is_nil(@state.current_term) && @state.next_term_schedule}
                    id="academy-next-term-window"
                    class="academy-ledger-heading__note"
                  >
                    Следующий термин откроется: {format_time(@state.next_term_schedule.starts_at)}
                  </p>
                </div>
                <div class="academy-term-ledger__actions">
                  <button
                    :if={is_nil(@state.current_term) && term_startable?(@state)}
                    id="academy-begin-term"
                    type="button"
                    phx-click="begin_term"
                    class="academy-ink-button"
                  >
                    Начать следующий термин
                  </button>
                  <p
                    :if={
                      is_nil(@state.current_term) && @state.next_term_schedule &&
                        not term_startable?(@state)
                    }
                    id="academy-term-not-open"
                    class="academy-term-actions__notice"
                  >
                    Следующий термин откроется {format_time(@state.next_term_schedule.starts_at)}.
                  </p>
                  <p
                    :if={is_nil(@state.current_term) && is_nil(@state.next_term_schedule)}
                    id="academy-no-more-terms"
                    class="academy-term-actions__notice"
                  >
                    Все предусмотренные сроки уже внесены в ведомость.
                  </p>
                  <button
                    :if={@state.current_term && @state.term_progress.phase == :enrollment}
                    id="academy-open-lectures"
                    type="button"
                    phx-click="open_lecture_phase"
                    class="academy-ink-button"
                  >
                    Закрыть выбор курсов
                  </button>
                  <.link
                    :if={@state.current_term && @state.term_progress.phase == :lectures}
                    id="academy-attend-lecture"
                    navigate={~p"/academy/lecture/#{@state.current_term.id}"}
                    class="academy-ink-button"
                  >
                    Открыть лекцию ({@state.term_progress.lectures_attended}/{@state.term_progress.lectures_required})
                  </.link>
                  <button
                    :if={@state.current_term && @state.term_progress.phase == :lectures}
                    id="academy-close-lectures"
                    type="button"
                    phx-click="close_lecture_phase"
                    class="academy-ink-button academy-ink-button--outline"
                  >
                    К клубному окну
                  </button>
                  <.link
                    :if={@state.current_term && @state.term_progress.phase in [:midterm, :final]}
                    id="academy-open-exam"
                    navigate={~p"/academy/exam/#{@state.current_term.id}"}
                    class="academy-ink-button"
                  >
                    {term_exam_action_label(@state.term_progress.phase)}
                  </.link>
                </div>
              </header>

              <div :if={@state.current_term} class="acd-phase academy-term-ledger__phase">
                <div class="acd-phase__track">
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :enrollment)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Запись</span>
                  </div>
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :lectures)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Лекции</span>
                  </div>
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :club_window)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Клубы</span>
                  </div>
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :midterm)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Промежуточный</span>
                  </div>
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :final)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Итоговый</span>
                  </div>
                  <div class={[
                    "acd-phase__step",
                    phase_step_class(@state.term_progress.phase, :break)
                  ]}>
                    <span class="acd-phase__dot"></span><span class="acd-phase__label">Перерыв</span>
                  </div>
                </div>
              </div>

              <section
                :if={@state.current_term && @state.term_progress.phase == :club_window}
                id="academy-club-window"
                class="academy-ledger-insert"
              >
                <div>
                  <p class="academy-paper__kicker">Вклейка клубного секретаря</p>
                  <p id="academy-club-window-attendance">
                    Посещено событий:
                    <strong>
                      {@state.term_progress.club_events_attended}/ {@state.term_progress.club_events_required}
                    </strong>
                  </p>
                  <p>
                    Подтверждённое участие требуется для рейтинга на стипендию.
                  </p>
                </div>
                <div class="academy-ledger-insert__actions">
                  <.link
                    id="academy-club-window-link"
                    navigate={~p"/academy/clubs"}
                    class="academy-ink-link"
                  >
                    Открыть книгу клубов
                  </.link>
                  <button
                    id="academy-close-club-window"
                    type="button"
                    phx-click="close_club_window"
                    class="academy-ink-button"
                  >
                    Передать на промежуточный экзамен
                  </button>
                </div>
              </section>

              <ul id="academy-term-list" class="academy-ledger-lines">
                <li :for={term <- @state.terms} id={"academy-term-#{term.id}"}>
                  <span>Термин {term.term_number}</span>
                  <span>{term_status(term.status)}</span>
                  <span>{term_phase_label(term_phase(term))}</span>
                  <strong>{term.exam_score || "—"}</strong>
                </li>
                <li
                  :if={@state.terms == []}
                  id="academy-terms-empty"
                  class="academy-ledger-lines__empty"
                >
                  Термины ещё не начаты.
                </li>
              </ul>
            </div>
          </section>

          <section
            :if={@state.cohort_leaderboard != []}
            id="academy-cohort-leaderboard"
            class="academy-blackboard"
          >
            <div class="academy-blackboard__chalk" aria-hidden="true"></div>
            <header>
              <p class="acd-eyebrow">Открытая ведомость</p>
              <h2>Рейтинг когорты</h2>
              <p>Верхняя четверть и мерит-стипендия учитывают клубное участие.</p>
            </header>
            <ol>
              <li
                :for={entry <- @state.cohort_leaderboard}
                id={"academy-cohort-rank-#{entry.enrollment.id}"}
              >
                <strong>№{entry.rank}</strong>
                <span>{entry.character.name}</span>
                <em :if={entry.ranking_eligible?}>стипендия</em>
                <b>Средний балл: {gpa_label(entry.gpa)}</b>
              </li>
            </ol>
          </section>

          <section :if={@state.current_term} id="academy-courses" class="academy-course-wing">
            <header class="academy-course-wing__header">
              <div>
                <p class="acd-eyebrow">Коридор текущего термина</p>
                <h2>Аудитории и курсы</h2>
              </div>
              <p>
                {if @state.term_progress.phase == :enrollment,
                  do: "Двери открыты для записи.",
                  else: "Запись закрыта; таблички показывают подтверждённые курсы."}
              </p>
            </header>
            <div class="academy-course-wing__corridor">
              <article
                :for={course <- visible_courses(@state)}
                id={"academy-course-#{course.id}"}
                class="academy-classroom"
              >
                <div class="academy-classroom__transom" aria-hidden="true"></div>
                <div class="academy-classroom__plaque">
                  <p>{course_track_label(course.track)} · {course_school_label(course.school)}</p>
                  <h3>{course_title(course)}</h3>
                  <span>{course_summary(course)}</span>
                </div>
                <div class="academy-classroom__status">
                  <p :if={enrolled?(course, @state.course_enrollments)}>Ваша фамилия внесена.</p>
                  <p
                    :if={office_hours_attended?(course, @state.course_enrollments)}
                    id={"academy-office-hours-attended-#{course.id}"}
                  >
                    Приёмные часы посещены · +5 к итоговой ведомости.
                  </p>
                </div>
                <button
                  :if={
                    not enrolled?(course, @state.course_enrollments) &&
                      @state.term_progress.phase == :enrollment
                  }
                  id={"academy-enroll-course-#{course.id}"}
                  type="button"
                  phx-click="enroll_course"
                  phx-value-course-id={course.id}
                  class="academy-classroom__handle"
                >
                  Записаться
                </button>
                <button
                  :if={
                    enrolled?(course, @state.course_enrollments) &&
                      not office_hours_attended?(course, @state.course_enrollments) &&
                      office_hours_open?(@state.term_progress.phase)
                  }
                  id={"academy-office-hours-#{course.id}"}
                  type="button"
                  phx-click="attend_office_hours"
                  phx-value-course-id={course.id}
                  class="academy-classroom__handle"
                >
                  Постучать в кабинет
                </button>
              </article>
              <p :if={visible_courses(@state) == []} id="academy-courses-empty" class="acd-empty">
                Для этого пути пока нет открытых аудиторий.
              </p>
            </div>
          </section>

          <footer class="academy-hall__footer">
            <span aria-hidden="true">A</span>
            <p>Архив Академии · записи принадлежат миру</p>
          </footer>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :active, :atom, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :glyph, :string, required: true

  defp academy_room_header(assigns) do
    ~H"""
    <div class="academy-room__topbar">
      <.link id="academy-back-to-hall" navigate={~p"/academy"} class="academy-room__exit">
        <span aria-hidden="true">←</span> В главный холл
      </.link>
      <button
        id="academy-refresh"
        type="button"
        phx-click="refresh"
        class="academy-room__refresh"
        aria-label="Обновить академические записи"
      >
        <span aria-hidden="true">⌁</span> Позвать архивариуса
      </button>
    </div>

    <header class="academy-room__portal">
      <div class="academy-room__lamp academy-room__lamp--left" aria-hidden="true"></div>
      <div class="academy-room__lamp academy-room__lamp--right" aria-hidden="true"></div>
      <span class="academy-room__glyph" aria-hidden="true">{@glyph}</span>
      <p class="acd-eyebrow">{@eyebrow}</p>
      <h1>{@title}</h1>
      <p>{@subtitle}</p>
    </header>

    <nav
      id="academy-navigation"
      class="academy-room__bookmarks"
      aria-label="Залы Академии"
    >
      <.link navigate={~p"/academy"} class={room_nav_class(@active, :overview)}>Холл</.link>
      <.link navigate={~p"/academy/timetable"} class={room_nav_class(@active, :timetable)}>
        Расписание
      </.link>
      <.link navigate={~p"/academy/grades"} class={room_nav_class(@active, :grades)}>
        Ведомость
      </.link>
      <.link navigate={~p"/academy/library"} class={room_nav_class(@active, :library)}>
        Библиотека
      </.link>
      <.link navigate={~p"/academy/courses"} class={room_nav_class(@active, :courses)}>
        Курсы
      </.link>
      <.link navigate={~p"/academy/progress"} class={room_nav_class(@active, :progress)}>
        Путь
      </.link>
    </nav>
    """
  end

  attr :error, :string, default: nil

  defp academy_room_error(assigns) do
    ~H"""
    <div :if={@error} id="academy-error" class="academy-room__error">
      <span aria-hidden="true">!</span>
      <p>{@error}</p>
    </div>
    """
  end

  attr :state, :map, required: true

  defp term_rhythm(assigns) do
    ~H"""
    <div
      :if={@state.current_term}
      class="academy-rhythm"
      aria-label="Ритм текущего термина"
    >
      <div
        :for={
          {phase, label} <- [
            enrollment: "Запись",
            lectures: "Лекции",
            club_window: "Клубы",
            midterm: "Аттестация",
            final: "Экзамен",
            break: "Перерыв"
          ]
        }
        class={[
          "academy-rhythm__step",
          phase_step_class(@state.term_progress.phase, phase)
        ]}
      >
        <span aria-hidden="true"></span>
        <small>{label}</small>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true

  defp term_action_controls(assigns) do
    ~H"""
    <div id="academy-term-actions" class="academy-term-actions">
      <button
        :if={is_nil(@state.current_term) && term_startable?(@state)}
        id="academy-begin-term"
        type="button"
        phx-click="begin_term"
        class="academy-ink-button"
      >
        Открыть следующий термин
      </button>
      <p
        :if={
          is_nil(@state.current_term) && @state.next_term_schedule &&
            not term_startable?(@state)
        }
        id="academy-term-not-open"
        class="academy-term-actions__notice"
      >
        Следующая запись откроется {format_time(@state.next_term_schedule.starts_at)}. Архив не
        засчитает попытку раньше срока.
      </p>
      <p
        :if={
          is_nil(@state.current_term) && is_nil(@state.next_term_schedule) &&
            @state.enrollment
        }
        id="academy-no-more-terms"
        class="academy-term-actions__notice"
      >
        Все предусмотренные сроки уже внесены в ведомость. Архив ожидает итоговой записи
        программы.
      </p>
      <button
        :if={@state.current_term && @state.term_progress.phase == :enrollment}
        id="academy-open-lectures"
        type="button"
        phx-click="open_lecture_phase"
        class="academy-ink-button"
      >
        Закрыть выбор курсов
      </button>
      <.link
        :if={@state.current_term && @state.term_progress.phase == :lectures}
        id="academy-attend-lecture"
        navigate={~p"/academy/lecture/#{@state.current_term.id}"}
        class="academy-ink-button"
      >
        Открыть лекцию ({@state.term_progress.lectures_attended}/{@state.term_progress.lectures_required})
      </.link>
      <button
        :if={@state.current_term && @state.term_progress.phase == :lectures}
        id="academy-close-lectures"
        type="button"
        phx-click="close_lecture_phase"
        class="academy-ink-button academy-ink-button--outline"
      >
        Перейти к клубам
      </button>
      <.link
        :if={@state.current_term && @state.term_progress.phase in [:midterm, :final]}
        id="academy-open-exam"
        navigate={~p"/academy/exam/#{@state.current_term.id}"}
        class="academy-ink-button"
      >
        {term_exam_action_label(@state.term_progress.phase)}
      </.link>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :program_form, :any, required: true

  defp academy_program_application(assigns) do
    ~H"""
    <section id="academy-programs" class="academy-application academy-room__application">
      <div class="academy-application__header">
        <div>
          <p class="academy-paper__kicker">Форма № 17 · Регистратура</p>
          <h2>Прошение о зачислении</h2>
        </div>
        <div class="academy-application__stamp" aria-hidden="true">ПОДАТЬ</div>
      </div>
      <p class="academy-paper__body">
        Поля меняются вместе с выбранной ступенью. Школы стихий нужны только чародею
        основного пути; алхимику и мастеру они не назначаются.
      </p>
      <.form
        for={@program_form}
        id="academy-program-form"
        phx-change="change_program"
        phx-submit="start_program"
        class="academy-paper-form academy-paper-form--grid"
      >
        <.input
          field={@program_form[:program_type]}
          type="select"
          label="Ступень обучения"
          options={program_options(@state.program_options)}
        />
        <div
          :if={program_form_value(@program_form, :program_type) == "academy_core"}
          id="academy-track-fields"
          class="academy-paper-form__conditional"
        >
          <.input
            field={@program_form[:track]}
            type="select"
            label="Профессиональный путь"
            options={track_options()}
          />
          <p class="academy-paper-form__help">
            Чародей создаёт заклинания, алхимик изучает рецепты, мастер работает с инструментами.
          </p>
        </div>
        <div
          :if={
            program_form_value(@program_form, :program_type) == "academy_core" &&
              program_form_value(@program_form, :track) == "wizardry"
          }
          id="academy-wizardry-school-fields"
          class="academy-paper-form__conditional academy-paper-form__conditional--schools"
        >
          <.input
            field={@program_form[:primary_school]}
            type="select"
            label="Основная школа чародейства"
            options={school_options()}
          />
          <.input
            field={@program_form[:secondary_school]}
            type="select"
            label="Дополнительная школа чародейства"
            options={school_options()}
          />
        </div>
        <button id="academy-start-program" type="submit" class="academy-wax-button">
          Скрепить и подать
        </button>
      </.form>
    </section>
    """
  end

  defp timetable_room(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-timetable-screen" class="acd-screen academy-room academy-room--timetable">
        <div class="academy-room__vault" aria-hidden="true"></div>
        <div class="academy-room__shell">
          <.academy_room_header
            active={:timetable}
            eyebrow="Колокола и занятия"
            title="Расписание термина"
            subtitle="Настенная книга показывает только настоящие сроки, посещения и открытые действия."
            glyph="⌚"
          />
          <.academy_room_error error={@error} />

          <section id="academy-terms" class="academy-agenda-board">
            <div class="academy-agenda-board__frame">
              <header class="academy-agenda-board__heading">
                <div>
                  <p class="academy-paper__kicker">Распорядок · текущая запись</p>
                  <h2>{term_room_heading(@state)}</h2>
                </div>
                <p id="academy-term-count">
                  {length(@state.terms)} из {@state.required_terms} терминов в архиве
                </p>
              </header>

              <p
                :if={@state.current_term_schedule}
                id="academy-current-term-window"
                class="academy-agenda-board__window"
              >
                Текущий срок: {format_time(@state.current_term_schedule.starts_at)} — {format_time(
                  @state.current_term_schedule.ends_at
                )}
              </p>
              <p
                :if={is_nil(@state.current_term) && @state.next_term_schedule}
                id="academy-next-term-window"
                class="academy-agenda-board__window"
              >
                Следующий срок начнётся {format_time(@state.next_term_schedule.starts_at)}
              </p>

              <.term_rhythm state={@state} />
              <.term_action_controls :if={@state.enrollment} state={@state} />

              <div id="academy-term-list" class="academy-agenda">
                <article
                  :for={entry <- term_agenda(@state)}
                  id={"academy-agenda-#{entry.key}"}
                  class={["academy-agenda__entry", "academy-agenda__entry--#{entry.state}"]}
                >
                  <div class="academy-agenda__rail" aria-hidden="true">
                    <span></span><i></i>
                  </div>
                  <div>
                    <small>{entry.when}</small>
                    <h3>{entry.title}</h3>
                    <p>{entry.detail}</p>
                  </div>
                </article>
                <p
                  :if={term_agenda(@state) == []}
                  id="academy-terms-empty"
                  class="academy-paper-empty"
                >
                  Сначала подайте прошение о зачислении в главном холле.
                </p>
              </div>
            </div>
          </section>

          <section
            :if={@state.current_term && @state.term_progress.phase == :club_window}
            id="academy-club-window"
            class="academy-pinned-note"
          >
            <span class="academy-pinned-note__pin" aria-hidden="true"></span>
            <p class="academy-paper__kicker">Записка клубного секретаря</p>
            <h2 id="academy-club-window-attendance">
              Посещено событий: {@state.term_progress.club_events_attended}/{@state.term_progress.club_events_required}
            </h2>
            <p>Подтверждённое участие требуется для рейтинга стипендии.</p>
            <div>
              <.link id="academy-club-window-link" navigate={~p"/academy/clubs"}>
                К книге клубов
              </.link>
              <button id="academy-close-club-window" type="button" phx-click="close_club_window">
                Передать на аттестацию
              </button>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp grades_room(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-grades-screen" class="scene-desk academy-grade-room">
        <div class="academy-grade-room__shell">
          <.academy_room_header
            active={:grades}
            eyebrow="Архив успеваемости"
            title="Личная ведомость"
            subtitle="Оценки лежат в переплёте: никаких тесных таблиц и мелкого служебного шрифта."
            glyph="✒"
          />
          <.academy_room_error error={@error} />

          <div class="book academy-grade-volume">
            <div class="book__spine"></div>
            <div class="book__page">
              <div class="book__leaf">
                <p class="academy-paper__kicker">Книга успеваемости · личный экземпляр</p>
                <h2 class="book__title">{@state.character.name}</h2>
                <p class="book__subtitle">{grade_program_line(@state)}</p>

                <section id="academy-progress-summary" class="academy-grade-summary">
                  <div>
                    <span>Средний балл</span>
                    <strong>{active_gpa(@state)}</strong>
                  </div>
                  <div>
                    <span>Провалено терминов</span>
                    <strong>{active_failed_terms(@state)}</strong>
                  </div>
                  <div>
                    <span>Место в когорте</span>
                    <strong>{cohort_rank_label(@state.academic_record)}</strong>
                  </div>
                </section>

                <div id="academy-term-list" class="academy-grade-records">
                  <article
                    :for={term <- @state.terms}
                    id={"academy-term-#{term.id}"}
                    class={["academy-grade-record", "academy-grade-record--#{term.status}"]}
                  >
                    <header>
                      <div>
                        <small>Термин {term.term_number}</small>
                        <h3>{term_status(term.status)}</h3>
                      </div>
                      <span>{grade_term_mark(term)}</span>
                    </header>
                    <dl>
                      <div>
                        <dt>Аттестация</dt>
                        <dd>{term_midterm_score(term)}</dd>
                      </div>
                      <div>
                        <dt>Итог</dt>
                        <dd>{term.exam_score || "—"}</dd>
                      </div>
                      <div>
                        <dt>Этап</dt>
                        <dd>{term_phase_label(term_phase(term))}</dd>
                      </div>
                    </dl>
                  </article>
                  <p :if={@state.terms == []} id="academy-terms-empty" class="academy-paper-empty">
                    В переплёте пока нет ни одного термина.
                  </p>
                </div>

                <section
                  :if={@state.academic_record}
                  id="academy-grade-outcome"
                  class="academy-grade-outcome"
                >
                  <span aria-hidden="true">A</span>
                  <div>
                    <p>Итоговая запись</p>
                    <strong>{outcome_label(@state.academic_record.outcome_tier)}</strong>
                  </div>
                </section>

                <section
                  :if={@state.academic_titles != [] || @state.valedictorian_honors != []}
                  id="academy-academic-titles"
                  class="academy-grade-honors"
                >
                  <p>Печати и почётные звания</p>
                  <span
                    :for={title <- @state.academic_titles}
                    id={"academy-academic-title-#{title.enrollment_id}"}
                  >
                    {title.title}
                  </span>
                  <span
                    :for={honor <- @state.valedictorian_honors}
                    id={"academy-valedictorian-title-#{honor.enrollment_id}"}
                  >
                    {honor.title}
                  </span>
                </section>
              </div>
            </div>
          </div>

          <section
            :if={@state.cohort_leaderboard != []}
            id="academy-cohort-leaderboard"
            class="academy-ranking-slip"
          >
            <p class="academy-paper__kicker">Вкладыш открытой ведомости</p>
            <h2>Рейтинг когорты</h2>
            <ol>
              <li
                :for={entry <- @state.cohort_leaderboard}
                id={"academy-cohort-rank-#{entry.enrollment.id}"}
              >
                <strong>№{entry.rank}</strong>
                <span>{entry.character.name}</span>
                <small>Средний балл: {gpa_label(entry.gpa)}</small>
              </li>
            </ol>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp library_room(assigns) do
    assigns = assign(assigns, :library_shelves, library_shelves(assigns.state))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-library-screen" class="acd-screen academy-room academy-room--library">
        <div class="academy-library__window" aria-hidden="true"></div>
        <div class="academy-room__shell">
          <.academy_room_header
            active={:library}
            eyebrow="Тишина · лампы · пыль"
            title="Библиотека Академии"
            subtitle="Каталог мира стоит на настоящих полках; личные формулы хранятся в вашем гримуаре."
            glyph="▰"
          />
          <.academy_room_error error={@error} />

          <section id="academy-library-shelves" class="academy-library">
            <div class="academy-library__ladder" aria-hidden="true"><i></i><i></i><i></i></div>
            <article
              :for={shelf <- @library_shelves}
              id={"academy-library-shelf-#{shelf.key}"}
              class="academy-library__bay"
            >
              <header>
                <span>{shelf.mark}</span>
                <div>
                  <p>{shelf.kicker}</p>
                  <h2>{shelf.title}</h2>
                </div>
              </header>
              <div class="academy-library__shelf">
                <article
                  :for={book <- shelf.books}
                  id={"academy-library-book-#{book.id}"}
                  class={["academy-library__book", library_book_class(book.school)]}
                >
                  <div class="academy-library__book-spine" aria-hidden="true">
                    <i></i><i></i>
                  </div>
                  <div class="academy-library__book-label">
                    <small>{book_kind_label(book.kind)}</small>
                    <h3>{book.title}</h3>
                    <p>{book.detail}</p>
                  </div>
                </article>
                <p :if={shelf.books == []} class="academy-library__dust">
                  На этой полке пока только карточка архивариуса.
                </p>
              </div>
            </article>
          </section>

          <aside class="academy-library__desk">
            <div class="academy-library__desk-lamp" aria-hidden="true"></div>
            <div>
              <p class="academy-paper__kicker">Личный каталог</p>
              <h2>Ваши заклинания лежат отдельно</h2>
              <p>
                Библиотека Академии показывает курсы и учебные записи. Собственные формулы,
                гримуары и создание заклинаний находятся в личной книге магии.
              </p>
            </div>
            <.link id="academy-open-spellbook" navigate={~p"/spellbook"} class="academy-wax-button">
              Открыть личный гримуар
            </.link>
          </aside>

          <div class="academy-library__forbidden">
            <span aria-hidden="true">⚿</span>
            <p>
              <strong>Запретная секция.</strong>
              Решётка открывается только по настоящей рекомендации наставника.
            </p>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp courses_room(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-courses-screen" class="acd-screen academy-room academy-room--courses">
        <div class="academy-room__vault" aria-hidden="true"></div>
        <div class="academy-room__shell">
          <.academy_room_header
            active={:courses}
            eyebrow="Коридор аудиторий"
            title="Курсы и запись"
            subtitle="Кафедральные таблички показывают реальный каталог этого мира и состояние вашего термина."
            glyph="❧"
          />
          <.academy_room_error error={@error} />

          <.academy_program_application
            :if={@state.enrollment == nil && @state.program_options != []}
            state={@state}
            program_form={@program_form}
          />

          <section :if={@state.enrollment} class="academy-course-register">
            <div class="academy-course-register__paper">
              <p class="academy-paper__kicker">Лист текущего термина</p>
              <h2>{program_label(@state.enrollment.program_type)}</h2>
              <p id="academy-term-count">
                Зафиксировано терминов: {length(@state.terms)} из {@state.required_terms}
              </p>
              <p
                :if={@state.next_term_schedule && is_nil(@state.current_term)}
                id="academy-next-term-window"
              >
                Следующий срок: {format_time(@state.next_term_schedule.starts_at)}
              </p>
              <.term_rhythm state={@state} />
              <.term_action_controls state={@state} />
            </div>
          </section>

          <section id="academy-courses" class="academy-course-wing academy-course-wing--room">
            <header class="academy-course-wing__header">
              <div>
                <p class="acd-eyebrow">Двери кафедр</p>
                <h2>Доступные аудитории</h2>
              </div>
              <p>{course_window_note(@state)}</p>
            </header>
            <div class="academy-course-wing__corridor">
              <article
                :for={course <- visible_courses(@state)}
                id={"academy-course-#{course.id}"}
                class="academy-classroom"
              >
                <div class="academy-classroom__transom" aria-hidden="true"></div>
                <div class="academy-classroom__plaque">
                  <p>{course_track_label(course.track)} · {course_school_label(course.school)}</p>
                  <h3>{course_title(course)}</h3>
                  <span>{course_summary(course)}</span>
                </div>
                <div class="academy-classroom__status">
                  <p :if={enrolled?(course, @state.course_enrollments)}>Ваша фамилия внесена.</p>
                  <p
                    :if={office_hours_attended?(course, @state.course_enrollments)}
                    id={"academy-office-hours-attended-#{course.id}"}
                  >
                    Приёмные часы посещены · +5 к итоговой ведомости.
                  </p>
                </div>
                <button
                  :if={
                    @state.current_term &&
                      not enrolled?(course, @state.course_enrollments) &&
                      @state.term_progress.phase == :enrollment
                  }
                  id={"academy-enroll-course-#{course.id}"}
                  type="button"
                  phx-click="enroll_course"
                  phx-value-course-id={course.id}
                  class="academy-classroom__handle"
                >
                  Записаться
                </button>
                <button
                  :if={
                    @state.current_term &&
                      enrolled?(course, @state.course_enrollments) &&
                      not office_hours_attended?(course, @state.course_enrollments) &&
                      office_hours_open?(@state.term_progress.phase)
                  }
                  id={"academy-office-hours-#{course.id}"}
                  type="button"
                  phx-click="attend_office_hours"
                  phx-value-course-id={course.id}
                  class="academy-classroom__handle"
                >
                  Постучать в кабинет
                </button>
              </article>
              <p :if={visible_courses(@state) == []} id="academy-courses-empty" class="acd-empty">
                Для этого пути пока нет открытых аудиторий.
              </p>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp progress_room(assigns) do
    assigns = assign(assigns, :education_ladder, education_ladder(assigns.state))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-progress-screen" class="acd-screen academy-room academy-room--progress">
        <div class="academy-path__tower" aria-hidden="true"></div>
        <div class="academy-room__shell">
          <.academy_room_header
            active={:progress}
            eyebrow="От первой парты до кафедры"
            title="Образовательный путь"
            subtitle="Каменная лестница отмечает только ваши завершённые, текущие и ещё закрытые ступени."
            glyph="✦"
          />
          <.academy_room_error error={@error} />

          <section id="academy-education-ladder" class="academy-path">
            <div class="academy-path__banister" aria-hidden="true"></div>
            <article
              :for={stage <- @education_ladder}
              id={"academy-path-stage-#{stage.key}"}
              class={["academy-path__stage", "academy-path__stage--#{stage.state}"]}
            >
              <div class="academy-path__step" aria-hidden="true">
                <span>{stage.glyph}</span>
              </div>
              <div class="academy-path__plaque">
                <header>
                  <div>
                    <small>{stage.span}</small>
                    <h2>{stage.title}</h2>
                  </div>
                  <b>{stage_status_label(stage.state)}</b>
                </header>
                <p>{stage.detail}</p>
                <div :if={stage.notes != []} class="academy-path__notes">
                  <span :for={note <- stage.notes}>{note}</span>
                </div>
              </div>
            </article>
          </section>

          <section id="academy-progress-summary" class="academy-path__certificate">
            <div class="academy-path__seal" aria-hidden="true">A</div>
            <div>
              <p class="academy-paper__kicker">Текущее положение</p>
              <h2>{progress_heading(@state)}</h2>
              <p>{progress_summary(@state)}</p>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_academy(socket) do
    case Play.academy_state(socket.assigns.current_scope.character) do
      {:ok, state} -> assign_state(socket, state)
      {:error, _reason} -> push_navigate(socket, to: ~p"/map")
    end
  end

  defp phase_step_class(current, step) when current == step, do: "acd-phase__step--now"

  defp phase_step_class(current, step) do
    phases = [:enrollment, :lectures, :club_window, :midterm, :final, :break]

    current_index = Enum.find_index(phases, &(&1 == current))
    step_index = Enum.find_index(phases, &(&1 == step))

    if current_index && step_index && step_index < current_index do
      "acd-phase__step--done"
    end
  end

  defp room_nav_class(active, room) do
    [
      "academy-room__bookmark",
      active == room && "academy-room__bookmark--active"
    ]
  end

  defp program_form_value(form, key) do
    case form[key].value do
      nil -> ""
      value -> to_string(value)
    end
  end

  defp term_startable?(%{current_term: nil, next_term_schedule: %{starts_at: starts_at}})
       when not is_nil(starts_at) do
    DateTime.compare(DateTime.utc_now(), starts_at) != :lt
  end

  defp term_startable?(_state), do: false

  defp term_room_heading(%{enrollment: nil}), do: "Учебная запись ещё не открыта"

  defp term_room_heading(%{current_term: nil, enrollment: enrollment}),
    do: "#{program_label(enrollment.program_type)} · между терминами"

  defp term_room_heading(%{current_term: term}),
    do: "Термин #{term.term_number} · #{term_phase_label(term_phase(term))}"

  defp term_agenda(%{enrollment: nil}), do: []

  defp term_agenda(%{current_term: nil, terms: terms}) do
    Enum.map(terms, fn term ->
      %{
        key: "term-#{term.id}",
        state: archived_term_state(term.status),
        when: "Архивная запись",
        title: "Термин #{term.term_number} · #{term_status(term.status)}",
        detail: archived_term_detail(term)
      }
    end)
  end

  defp term_agenda(%{current_term: _term, term_progress: progress} = state) do
    [
      %{
        key: "enrollment",
        phase: :enrollment,
        title: "Выбор курсов",
        detail:
          "#{length(state.course_enrollments)} #{russian_course_count(length(state.course_enrollments))} внесено в лист."
      },
      %{
        key: "lectures",
        phase: :lectures,
        title: "Лекционный цикл",
        detail:
          "Посещено #{progress.lectures_attended} из #{progress.lectures_required} обязательных лекций."
      },
      %{
        key: "club-window",
        phase: :club_window,
        title: "Клубное окно",
        detail:
          "Подтверждено #{progress.club_events_attended} из #{progress.club_events_required} событий."
      },
      %{
        key: "midterm",
        phase: :midterm,
        title: "Промежуточная аттестация",
        detail:
          if(progress.midterm_score,
            do: "Оценка внесена: #{progress.midterm_score}.",
            else: "Оценка ещё не внесена."
          )
      },
      %{
        key: "final",
        phase: :final,
        title: "Итоговый экзамен",
        detail:
          if(progress.final_score,
            do: "Ответ принят: #{progress.final_score}.",
            else: "Итог ожидает открытия экзамена."
          )
      },
      %{
        key: "break",
        phase: :break,
        title: "Закрытие ведомости",
        detail: "После экзамена переплёт передадут в архив."
      }
    ]
    |> Enum.map(fn entry ->
      entry
      |> Map.put(:state, agenda_phase_state(progress.phase, entry.phase))
      |> Map.put(:when, agenda_when(state, entry.phase))
    end)
  end

  defp archived_term_state(:failed), do: :missed
  defp archived_term_state(:pending), do: :future
  defp archived_term_state(:active), do: :now
  defp archived_term_state(_status), do: :done

  defp archived_term_detail(%{status: :pending}),
    do: "Срок прошёл без открытия; до завершения программы он не считается проваленным."

  defp archived_term_detail(%{exam_score: score}) when is_integer(score),
    do: "Итоговая оценка: #{score}."

  defp archived_term_detail(_term), do: "Итоговая оценка не внесена."

  defp agenda_phase_state(current, current), do: :now

  defp agenda_phase_state(current, phase) do
    phases = [:enrollment, :lectures, :club_window, :midterm, :final, :break]
    current_index = Enum.find_index(phases, &(&1 == current)) || 0
    phase_index = Enum.find_index(phases, &(&1 == phase)) || 0
    if phase_index < current_index, do: :done, else: :future
  end

  defp agenda_when(%{current_term_schedule: schedule}, :enrollment) when not is_nil(schedule),
    do: "С #{format_time(schedule.starts_at)}"

  defp agenda_when(%{current_term_schedule: schedule}, :break) when not is_nil(schedule),
    do: "До #{format_time(schedule.ends_at)}"

  defp agenda_when(_state, _phase), do: "Текущий термин"

  defp russian_course_count(count) when rem(count, 10) == 1 and rem(count, 100) != 11,
    do: "курс"

  defp russian_course_count(count)
       when rem(count, 10) in 2..4 and rem(count, 100) not in 12..14,
       do: "курса"

  defp russian_course_count(_count), do: "курсов"

  defp grade_program_line(%{enrollment: enrollment, latest_enrollment: latest}) do
    case enrollment || latest do
      nil -> "Учебная запись не открыта"
      record -> program_label(record.program_type)
    end
  end

  defp active_gpa(%{gpa: gpa}) when not is_nil(gpa), do: gpa_label(gpa)

  defp active_gpa(%{academic_record: %{gpa: gpa}}) when not is_nil(gpa),
    do: gpa_label(gpa)

  defp active_gpa(_state), do: "—"

  defp active_failed_terms(%{failed_terms: failed_terms}) when is_integer(failed_terms),
    do: failed_terms

  defp active_failed_terms(%{academic_record: %{failed_terms: failed_terms}})
       when is_integer(failed_terms),
       do: failed_terms

  defp active_failed_terms(_state), do: 0

  defp cohort_rank_label(%{cohort_rank: rank, cohort_size: size})
       when is_integer(rank) and is_integer(size),
       do: "#{rank} из #{size}"

  defp cohort_rank_label(_record), do: "—"

  defp grade_term_mark(%{status: :failed}), do: "не зачтён"
  defp grade_term_mark(%{status: :completed, exam_score: score}) when is_integer(score), do: score
  defp grade_term_mark(%{status: :active}), do: "текущий"
  defp grade_term_mark(_term), do: "—"

  defp term_midterm_score(%{metadata: metadata}),
    do: Map.get(metadata || %{}, "midterm_score") || "—"

  defp library_shelves(state) do
    enrolled_books =
      Enum.flat_map(state.course_enrollments, fn
        %{course: %{} = course, grade: grade} ->
          [
            %{
              id: "enrolled-#{course.id}",
              title: course_title(course),
              detail:
                if(grade,
                  do: "Оценка по курсу: #{grade}.",
                  else: course_summary(course)
                ),
              kind: :enrolled,
              school: course.school
            }
          ]

        _other ->
          []
      end)

    catalog_books =
      state
      |> visible_courses()
      |> Enum.reject(&enrolled?(&1, state.course_enrollments))
      |> Enum.map(fn course ->
        %{
          id: "catalog-#{course.id}",
          title: course_title(course),
          detail: course_summary(course),
          kind: {:course, course.track, course.school},
          school: course.school
        }
      end)

    record_books =
      Enum.map(state.academic_titles ++ state.valedictorian_honors, fn title ->
        %{
          id: "record-#{title.enrollment_id}",
          title: title.title,
          detail: "Архивная грамота, подтверждённая печатью Академии.",
          kind: :record,
          school: nil
        }
      end)

    [
      %{
        key: "current",
        mark: "I",
        kicker: "На руках",
        title: "Курсы текущего термина",
        books: enrolled_books
      },
      %{
        key: "catalog",
        mark: "II",
        kicker: "Каталог мира",
        title: "Учебные гримуары",
        books: catalog_books
      },
      %{
        key: "archive",
        mark: "III",
        kicker: "Личный архив",
        title: "Грамоты и почётные записи",
        books: record_books
      }
    ]
  end

  defp library_book_class(nil), do: "academy-library__book--general"
  defp library_book_class(school), do: "academy-library__book--#{school}"

  defp book_kind_label(:enrolled), do: "В вашей учебной записи"

  defp book_kind_label({:course, track, school}),
    do: "#{course_track_label(track)} · #{course_school_label(school)}"

  defp book_kind_label(:record), do: "Личное дело"
  defp book_kind_label(_kind), do: "Учебный гримуар"

  defp course_window_note(%{current_term: nil}),
    do: "Осмотрите каталог. Запись станет доступна после открытия термина."

  defp course_window_note(%{term_progress: %{phase: :enrollment}}),
    do: "Двери открыты для записи."

  defp course_window_note(_state),
    do: "Запись закрыта; таблички показывают подтверждённые курсы."

  defp education_ladder(state) do
    [
      %{
        key: :basic,
        program: :basic_education,
        glyph: "I",
        title: "Базовое образование",
        span: "10 терминов",
        detail: "Всеобщая грамота, история мира и основы магической безопасности."
      },
      %{
        key: :core,
        program: :academy_core,
        glyph: "II",
        title: "Основной путь Академии",
        span: "3 термина",
        detail: "Чародейство, алхимия или мастерство с итоговой практической работой."
      },
      %{
        key: :extended,
        program: :extended_study,
        glyph: "III",
        title: "Углублённое обучение",
        span: "2 термина",
        detail: "Дополнительная специализация перед научной кафедрой."
      },
      %{
        key: :academia,
        program: :academia,
        glyph: "IV",
        title: "Академия наук",
        span: "4 термина",
        detail: "Наставник, исследование, публикации, тезис и открытая защита."
      },
      %{
        key: :professor,
        program: :professor,
        glyph: "V",
        title: "Профессорская кафедра",
        span: "карьера",
        detail: "Право вести курсы, брать учеников и участвовать в совете Академии."
      }
    ]
    |> Enum.map(fn stage ->
      Map.merge(stage, %{
        state: education_stage_state(state, stage.program),
        notes: education_stage_notes(state, stage.program)
      })
    end)
  end

  defp education_stage_state(state, :professor) do
    if state.academic_titles != [], do: :future, else: :locked
  end

  defp education_stage_state(state, program) do
    cond do
      state.enrollment && state.enrollment.program_type == program ->
        :now

      Enum.any?(
        state.enrollment_history,
        &(&1.program_type == program && &1.status == :completed)
      ) ->
        :done

      true ->
        :locked
    end
  end

  defp education_stage_notes(state, :professor) do
    if state.academic_titles == [], do: [], else: ["Научные звания уже внесены в личное дело"]
  end

  defp education_stage_notes(state, program) do
    enrollment =
      if state.enrollment && state.enrollment.program_type == program do
        state.enrollment
      else
        Enum.find(state.enrollment_history, &(&1.program_type == program))
      end

    case enrollment do
      nil ->
        []

      %{status: :active} ->
        [
          "#{length(state.terms)} из #{state.required_terms} терминов",
          track_note(enrollment)
        ]
        |> Enum.reject(&is_nil/1)

      %{status: status, metadata: metadata} ->
        [
          enrollment_status(status),
          outcome_label(Map.get(metadata || %{}, "outcome_tier"))
        ]
    end
  end

  defp track_note(%{track: nil}), do: nil
  defp track_note(%{track: track}), do: "Путь: #{track_label(track)}"

  defp stage_status_label(:done), do: "завершено"
  defp stage_status_label(:now), do: "вы здесь"
  defp stage_status_label(:future), do: "впереди"
  defp stage_status_label(:locked), do: "закрыто"

  defp progress_heading(%{enrollment: nil, latest_enrollment: nil}), do: "Начало пути"

  defp progress_heading(%{enrollment: nil, latest_enrollment: latest}),
    do: "#{program_label(latest.program_type)} · запись закрыта"

  defp progress_heading(%{enrollment: enrollment}),
    do: "#{program_label(enrollment.program_type)} · #{enrollment_status(enrollment.status)}"

  defp progress_summary(%{enrollment: nil, program_options: []}),
    do: "Регистратура пока не предлагает следующую ступень."

  defp progress_summary(%{enrollment: nil}),
    do: "Следующую доступную ступень можно открыть в главном холле или в коридоре курсов."

  defp progress_summary(state) do
    "#{length(state.terms)} из #{state.required_terms} терминов внесено; средний балл — #{active_gpa(state)}."
  end

  defp assign_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:state, state)
    |> assign(:error, nil)
    |> assign(:program_form, to_form(program_params(state), as: :academy_program))
    |> assign(:valedictorian_form, to_form(%{"school" => "fire"}, as: :valedictorian_bonus))
  end

  defp program_params(%{program_options: [option | _rest]}) do
    %{
      "program_type" => option.code,
      "track" => "wizardry",
      "primary_school" => "fire",
      "secondary_school" => "air"
    }
  end

  defp program_params(_state),
    do: %{
      "program_type" => "",
      "track" => "wizardry",
      "primary_school" => "fire",
      "secondary_school" => "air"
    }

  defp program_options(options) do
    Enum.map(options, fn option ->
      {String.replace(option.label, "Academy Core", "Ядро Академии"), option.code}
    end)
  end

  defp track_options, do: @track_options
  defp school_options, do: @school_options

  defp visible_courses(%{courses: courses, enrollment: enrollment}) when is_nil(enrollment),
    do: courses

  defp visible_courses(%{courses: courses, enrollment: enrollment}),
    do: Enum.filter(courses, &(is_nil(&1.track) or &1.track == enrollment.track))

  defp enrolled?(course, enrollments), do: Enum.any?(enrollments, &(&1.course_id == course.id))

  defp office_hours_attended?(course, enrollments) do
    case Enum.find(enrollments, &(&1.course_id == course.id)) do
      %{metadata: metadata} -> Map.get(metadata || %{}, "office_hours_attended") in [true, "true"]
      _other -> false
    end
  end

  defp office_hours_open?(phase) when phase in [:lectures, :club_window, :midterm], do: true
  defp office_hours_open?(_phase), do: false

  defp academy_heading(%{enrollment: nil}), do: "Зачисление и путь"
  defp academy_heading(%{enrollment: enrollment}), do: program_label(enrollment.program_type)
  defp title_for(action), do: "Академия · #{action_label(action)}"
  defp action_label(:timetable), do: "расписание"
  defp action_label(:grades), do: "ведомость"
  defp action_label(:library), do: "библиотека"
  defp action_label(:courses), do: "курсы"
  defp action_label(:progress), do: "путь"
  defp action_label(_action), do: "холл"
  defp program_label(:basic_education), do: "Базовое образование"
  defp program_label(:academy_core), do: "Ядро Академии"
  defp program_label(:extended_study), do: "Расширенный курс"
  defp program_label(:academia), do: "Академия наук"
  defp program_label(_program), do: "Учебная запись"
  defp enrollment_status(:active), do: "идёт"
  defp enrollment_status(:completed), do: "завершена"
  defp enrollment_status(:failed), do: "не завершена"
  defp enrollment_status(_status), do: "ожидает"
  defp term_status(:active), do: "идёт"
  defp term_status(:completed), do: "завершён"
  defp term_status(:failed), do: "провален"
  defp term_status(_status), do: "ожидает"
  defp term_label(nil), do: "не открыт"
  defp term_label(term), do: "#{term.term_number} · #{term_status(term.status)}"

  defp term_phase(%{metadata: metadata}),
    do: Map.get(metadata || %{}, "phase") |> term_phase_from_metadata()

  defp term_phase(_term), do: :enrollment
  defp term_phase_from_metadata("enrollment"), do: :enrollment
  defp term_phase_from_metadata("lectures"), do: :lectures
  defp term_phase_from_metadata("club_window"), do: :club_window
  defp term_phase_from_metadata("midterm"), do: :midterm
  defp term_phase_from_metadata("final"), do: :final
  defp term_phase_from_metadata("break"), do: :break
  defp term_phase_from_metadata(_phase), do: :enrollment
  defp term_phase_label(:enrollment), do: "Выбор курсов"
  defp term_phase_label(:lectures), do: "Лекции"
  defp term_phase_label(:club_window), do: "Клубное окно"
  defp term_phase_label(:midterm), do: "Промежуточный экзамен"
  defp term_phase_label(:final), do: "Итоговый экзамен"
  defp term_phase_label(:break), do: "Перерыв"
  defp term_phase_label(_phase), do: "Ведомость"
  defp term_exam_action_label(:midterm), do: "Открыть промежуточный экзамен"
  defp term_exam_action_label(:final), do: "Открыть итоговый экзамен"
  defp term_exam_action_label(phase), do: term_phase_label(phase)
  defp track_label(:wizardry), do: "Чародейство"
  defp track_label(:alchemy), do: "Алхимия"
  defp track_label(:mastery), do: "Мастерство"
  defp track_label(_track), do: "Общий путь"
  defp course_track_label(track), do: track_label(track)
  defp course_school_label(nil), do: "общий курс"
  defp course_school_label(school), do: school_label(school)

  defp school_suffix(%{track: :wizardry, primary_school: first, secondary_school: second}),
    do: " · #{school_label(first)} + #{school_label(second)}"

  defp school_suffix(_specialization), do: ""

  defp school_label(:fire), do: "Огонь"
  defp school_label(:water), do: "Вода"
  defp school_label(:earth), do: "Земля"
  defp school_label(:air), do: "Воздух"
  defp school_label(:life), do: "Жизнь"
  defp school_label(:death), do: "Смерть"
  defp school_label(:chaos), do: "Хаос"
  defp school_label(:order), do: "Порядок"
  defp school_label("fire"), do: "Огонь"
  defp school_label("water"), do: "Вода"
  defp school_label("earth"), do: "Земля"
  defp school_label("air"), do: "Воздух"
  defp school_label("life"), do: "Жизнь"
  defp school_label("death"), do: "Смерть"
  defp school_label("chaos"), do: "Хаос"
  defp school_label("order"), do: "Порядок"
  defp school_label(school), do: to_string(school)

  defp retraining_enrollment?(%{metadata: metadata}),
    do: is_binary(Map.get(metadata || %{}, "retraining_from_specialization_id"))

  defp retraining_enrollment?(_enrollment), do: false
  defp gpa_label(nil), do: "—"
  defp gpa_label(gpa), do: to_string(gpa)
  defp record_failed_terms(nil), do: 0
  defp record_failed_terms(record), do: record.failed_terms
  defp outcome_label(:distinction), do: "с отличием"
  defp outcome_label("distinction"), do: "с отличием"
  defp outcome_label(:pass), do: "зачёт"
  defp outcome_label("pass"), do: "зачёт"
  defp outcome_label(:probation), do: "испытательный выпуск"
  defp outcome_label("probation"), do: "испытательный выпуск"
  defp outcome_label(:expulsion), do: "отчисление"
  defp outcome_label("expulsion"), do: "отчисление"
  defp outcome_label(:capstone_incomplete), do: "не пройден итоговый проект"
  defp outcome_label("capstone_incomplete"), do: "не пройден итоговый проект"
  defp outcome_label(_outcome), do: "ведомость ожидает итогов"

  defp starter_track_label(%{"track" => "wizardry"}), do: "Чародейство"
  defp starter_track_label(%{"track" => "alchemy"}), do: "Алхимия"
  defp starter_track_label(%{"track" => "mastery"}), do: "Мастерство"
  defp starter_track_label(%{"track" => "basic_education"}), do: "Базовое образование"
  defp starter_track_label(_outcomes), do: "Выпускной набор"

  defp starter_quality_label(%{"quality" => "refined"}), do: "отличное качество"
  defp starter_quality_label(%{"quality" => "standard"}), do: "стандартное качество"
  defp starter_quality_label(%{"quality" => "provisional"}), do: "учебное качество"
  defp starter_quality_label(%{"quality" => "honors"}), do: "выпуск с отличием"
  defp starter_quality_label(_outcomes), do: "качество по ведомости"

  defp starter_title(%{"title" => title}) when is_binary(title), do: title
  defp starter_title(_outcomes), do: nil

  defp starter_destination(%{"track" => "wizardry"}), do: "/spellbook"
  defp starter_destination(%{"track" => "alchemy"}), do: "/alchemy"
  defp starter_destination(%{"track" => "mastery"}), do: "/inventory"
  defp starter_destination(%{"track" => "basic_education"}), do: "/spellbook"
  defp starter_destination(_outcomes), do: "/academy"

  defp starter_rewards(%{"rewards" => rewards}) when is_list(rewards), do: rewards
  defp starter_rewards(_outcomes), do: []

  defp starter_reward_id(reward) do
    Map.get(reward, "id") || Map.get(reward, "inventory_item_id") || Map.get(reward, "code") ||
      "record"
  end

  defp starter_reward_label(%{"kind" => "spell", "name" => name, "school" => school}),
    do: "Заклинание: #{name} · #{school_label(school)}"

  defp starter_reward_label(%{"kind" => "recipe", "name" => name}), do: "Рецепт: #{name}"
  defp starter_reward_label(%{"kind" => "tool", "name" => name}), do: "Инструмент: #{name}"
  defp starter_reward_label(%{"name" => name}), do: name
  defp starter_reward_label(_reward), do: "Награда внесена в ведомость."

  defp starter_reagent_label(%{"starter_reagent" => %{} = reagent}) do
    case {Map.get(reagent, "name"), Map.get(reagent, "quantity")} do
      {name, quantity} when is_binary(name) and is_integer(quantity) ->
        "Для первой варки выданы реагенты: #{name} ×#{quantity}."

      _other ->
        nil
    end
  end

  defp starter_reagent_label(_outcomes), do: nil

  defp format_time(nil), do: "не назначено"
  defp format_time(datetime), do: Calendar.strftime(datetime, "%d.%m %H:%M")

  defp course_summary(course),
    do:
      course.syllabus["summary"] || course.metadata["summary"] ||
        "Описание курса появится в ведомости преподавателя."

  defp course_title(%{title: title}), do: localized_course_title(title)

  defp localized_course_title("History of the Realm"), do: "История мира"
  defp localized_course_title("Elemental Literacy"), do: "Основы стихий"
  defp localized_course_title("Overworld Survival"), do: "Выживание в открытом мире"
  defp localized_course_title("Economic Basics"), do: "Основы экономики"
  defp localized_course_title("Civic Law"), do: "Гражданское право"
  defp localized_course_title("Latin Fundamentals"), do: "Основы латыни"
  defp localized_course_title("Incantation Construction I"), do: "Создание заклинаний I"
  defp localized_course_title("Dual-School Fundamentals"), do: "Основы двух школ"
  defp localized_course_title("Spellcraft Practicum"), do: "Практикум по чародейству"
  defp localized_course_title("Incantation Construction II"), do: "Создание заклинаний II"
  defp localized_course_title("Arcane Mini-Thesis"), do: "Малая работа по чародейству"
  defp localized_course_title("Ingredients Taxonomy"), do: "Систематика ингредиентов"
  defp localized_course_title("Basic Brewing"), do: "Основы зельеварения"

  defp localized_course_title("Recipe Development Practicum"),
    do: "Практикум по созданию рецептов"

  defp localized_course_title("Alchemy Mini-Thesis"), do: "Малая работа по алхимии"
  defp localized_course_title("Materials Science"), do: "Материаловедение"
  defp localized_course_title("Basic Forging"), do: "Основы кузнечного дела"
  defp localized_course_title("Toolcraft Practicum"), do: "Практикум по инструментам"
  defp localized_course_title("Mastery Mini-Thesis"), do: "Малая работа по мастерству"
  defp localized_course_title(title), do: title

  defp error_message(:academy_location_unavailable),
    do: "Академические дела доступны только в городе."

  defp error_message(:academy_program_unavailable), do: "Эта ступень обучения сейчас недоступна."
  defp error_message(:academy_enrollment_unavailable), do: "Активная учебная запись не найдена."
  defp error_message(:academy_term_already_active), do: "Текущий термин уже открыт."
  defp error_message(:academy_term_unavailable), do: "Активный термин не найден."
  defp error_message(:academy_exam_unavailable), do: "Экзамен ещё не открыт для этого термина."

  defp error_message(:academy_lecture_unavailable),
    do: "Лекция сейчас не открыта для этого термина."

  defp error_message(:valedictorian_bonus_unavailable),
    do: "Лауреатская награда сейчас недоступна."

  defp error_message(:academy_course_unavailable),
    do: "Этот курс нельзя добавить к вашему термину."

  defp error_message(:academy_office_hours_unavailable),
    do: "Приёмные часы сейчас недоступны для этого курса."

  defp error_message(_reason), do: "Академия отклонила действие: проверьте путь, термин и место."
end
