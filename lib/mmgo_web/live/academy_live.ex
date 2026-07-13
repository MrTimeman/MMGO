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
         |> put_flash(:info, "Клубное окно закрыто, ведомость передана на мидтерм.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_academy(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academy-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-5xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="academy-back-to-map"
              navigate={~p"/map"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← Карта мира
            </.link>
            <button
              id="academy-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200"
            >
              Обновить
            </button>
          </div>

          <header class="rounded-2xl border border-sky-400/25 bg-gradient-to-br from-slate-900 via-stone-950 to-sky-950/30 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.25em] text-sky-200/75">
              академия · {action_label(@live_action || :overview)}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-sky-100">{academy_heading(@state)}</h1>
            <p class="mt-3 max-w-3xl text-sm leading-6 text-stone-300">
              Учебные записи, термины и курсы читаются из состояния мира; экзамен проверяет только ваш активный термин.
            </p>
          </header>

          <div
            :if={@error}
            id="academy-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section id="academy-status" class="grid gap-4 lg:grid-cols-[1.4fr_1fr]">
            <article class="rounded-2xl border border-stone-700 bg-stone-900/80 p-5 shadow-lg">
              <p class="text-xs uppercase tracking-[0.2em] text-stone-500">учебная запись</p>
              <%= if @state.enrollment do %>
                <h2 id="academy-enrollment" class="mt-2 font-serif text-2xl text-stone-100">
                  {program_label(@state.enrollment.program_type)}
                </h2>
                <p class="mt-2 text-sm text-stone-300">
                  Статус: {enrollment_status(@state.enrollment.status)} · завершение {format_time(
                    @state.enrollment.expected_completion_at
                  )}
                </p>
                <p
                  :if={@state.specialization}
                  id="academy-specialization"
                  class="mt-3 text-sm text-sky-100"
                >
                  Путь: {track_label(@state.specialization.track)}{school_suffix(
                    @state.specialization
                  )}
                </p>
                <p
                  :if={retraining_enrollment?(@state.enrollment)}
                  id="academy-retraining-enrollment"
                  class="mt-2 text-sm text-amber-100"
                >
                  Переподготовка идёт: прежняя специализация сохранится до вашего выпуска, затем уйдёт в архив.
                </p>
              <% else %>
                <h2 id="academy-no-enrollment" class="mt-2 font-serif text-2xl text-stone-100">
                  Свободная запись
                </h2>
                <p class="mt-2 text-sm text-stone-400">
                  Следующая доступная программа зависит от уже завершённого обучения.
                </p>
                <p
                  :if={@state.latest_enrollment}
                  id="academy-last-outcome"
                  class="mt-3 text-sm text-sky-100"
                >
                  Последний выпуск: {program_label(@state.latest_enrollment.program_type)} · {outcome_label(
                    @state.academic_record && @state.academic_record.outcome_tier
                  )}
                </p>
              <% end %>
            </article>

            <article
              id="academy-progress-summary"
              class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-5 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">успеваемость</p>
              <p class="mt-2 font-serif text-3xl text-emerald-100">
                {gpa_label(@state.academic_record && @state.academic_record.gpa)}
              </p>
              <p class="text-sm text-stone-300">
                Проваленных терминов: {record_failed_terms(@state.academic_record)}
              </p>
              <p
                :if={@state.academic_record && @state.academic_record.cohort_rank}
                id="academy-cohort-standing"
                class="mt-2 text-sm text-emerald-100"
              >
                Когорта: №{@state.academic_record.cohort_rank} из {@state.academic_record.cohort_size}
              </p>
              <p
                :if={@state.academic_record && @state.academic_record.merit_scholarship_eligible?}
                id="academy-merit-grant"
                class="mt-1 text-sm text-amber-100"
              >
                Доступен merit grant на Academy Core.
              </p>
              <p
                :if={@state.charity_stipend}
                id="academy-charity-stipend"
                class="mt-1 text-sm text-amber-100"
              >
                Получена стипендия Фонда Просвещения: {Map.get(@state.charity_stipend, "amount")} ◈.
              </p>
              <div
                :if={@state.academic_titles != []}
                id="academy-academic-titles"
                class="mt-3 space-y-1 border-t border-amber-300/15 pt-3 text-sm text-amber-100"
              >
                <p class="text-xs uppercase tracking-[0.16em] text-amber-100/70">
                  академические титулы
                </p>
                <p
                  :for={title <- @state.academic_titles}
                  id={"academy-academic-title-#{title.enrollment_id}"}
                >
                  {title.title}
                </p>
              </div>
              <p
                :if={@state.academic_record && @state.academic_record.valedictorian?}
                id="academy-valedictorian"
                class="mt-1 text-sm text-violet-100"
              >
                Звание: {@state.academic_record.valedictorian_title}.
              </p>
              <div
                :if={@state.valedictorian_honors != []}
                id="academy-valedictorian-titles"
                class="mt-3 space-y-1 border-t border-violet-300/15 pt-3 text-sm text-violet-100"
              >
                <p class="text-xs uppercase tracking-[0.16em] text-violet-200/70">звания</p>
                <p
                  :for={honor <- @state.valedictorian_honors}
                  id={"academy-valedictorian-title-#{honor.enrollment_id}"}
                >
                  {honor.title}
                  <span :if={honor.hall_of_fame_until} class="text-stone-400">
                    · доска до {format_time(honor.hall_of_fame_until)}
                  </span>
                </p>
              </div>
              <p class="mt-3 text-sm text-stone-400">
                Текущий термин: {term_label(@state.current_term)}
              </p>
            </article>
          </section>

          <section
            :if={@state.starter_outcomes}
            id="academy-starter-outcomes"
            class="rounded-2xl border border-violet-400/30 bg-violet-950/20 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">выпускной набор</p>
                <h2 class="mt-1 font-serif text-2xl text-violet-100">
                  {starter_track_label(@state.starter_outcomes)} · {starter_quality_label(
                    @state.starter_outcomes
                  )}
                </h2>
                <p
                  :if={starter_title(@state.starter_outcomes)}
                  id="academy-starter-title"
                  class="mt-2 text-sm text-amber-100"
                >
                  Звание: {starter_title(@state.starter_outcomes)}
                </p>
                <p class="mt-2 max-w-2xl text-sm text-stone-300">
                  Награды уже внесены в мир: это не памятная запись, а ваши заклинания, рецепты или инструменты.
                </p>
              </div>
              <.link
                id="academy-open-starter-rewards"
                navigate={starter_destination(@state.starter_outcomes)}
                class="rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 hover:bg-violet-950/60"
              >
                Открыть набор
              </.link>
            </div>
            <ul id="academy-starter-reward-list" class="mt-4 grid gap-2 md:grid-cols-3">
              <li
                :for={reward <- starter_rewards(@state.starter_outcomes)}
                id={"academy-starter-reward-#{starter_reward_id(reward)}"}
                class="rounded-lg border border-violet-300/15 bg-stone-950/55 px-4 py-3 text-sm text-stone-100"
              >
                {starter_reward_label(reward)}
              </li>
            </ul>
            <p
              :if={starter_reagent_label(@state.starter_outcomes)}
              id="academy-starter-reagent"
              class="mt-3 text-sm text-amber-100"
            >
              {starter_reagent_label(@state.starter_outcomes)}
            </p>
          </section>

          <section
            :if={@state.valedictorian_bonus}
            id="academy-valedictorian-bonus"
            class="rounded-2xl border border-amber-300/35 bg-amber-950/20 p-6 shadow-lg"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-amber-100/80">награда валедикториана</p>
            <h2 class="mt-1 font-serif text-2xl text-amber-100">
              {@state.valedictorian_bonus.title}
            </h2>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-stone-300">
              Выберите одну школу для именной Лауреатской печати. Заклинание будет создано в вашей библиотеке, а выбранная школа останется разрешённой для этой награды.
            </p>
            <.form
              for={@valedictorian_form}
              id="academy-valedictorian-bonus-form"
              phx-submit="claim_valedictorian_spell"
              class="mt-4 flex flex-wrap items-end gap-3"
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
                class="rounded-lg bg-amber-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-200"
              >
                Получить заклинание
              </button>
            </.form>
          </section>

          <section
            :if={@state.enrollment == nil and @state.program_options != []}
            id="academy-programs"
            class="rounded-2xl border border-sky-400/20 bg-sky-950/15 p-6 shadow-lg"
          >
            <h2 class="font-serif text-2xl text-sky-100">Следующая ступень</h2>
            <p class="mt-2 text-sm text-stone-400">
              Академия сама проверяет право на поступление и параметры выбранного пути.
            </p>
            <.form
              for={@program_form}
              id="academy-program-form"
              phx-submit="start_program"
              class="mt-4 grid gap-3 md:grid-cols-2"
            >
              <.input
                field={@program_form[:program_type]}
                type="select"
                label="Программа"
                options={program_options(@state.program_options)}
              />
              <.input
                field={@program_form[:track]}
                type="select"
                label="Путь (для Academy Core)"
                options={track_options()}
              />
              <.input
                field={@program_form[:primary_school]}
                type="select"
                label="Первая школа (для чародейства)"
                options={school_options()}
              />
              <.input
                field={@program_form[:secondary_school]}
                type="select"
                label="Вторая школа (для чародейства)"
                options={school_options()}
              />
              <button
                id="academy-start-program"
                type="submit"
                class="rounded-lg bg-sky-300 px-4 py-3 text-sm font-semibold text-stone-950 hover:bg-sky-200"
              >
                Открыть запись
              </button>
            </.form>
          </section>

          <section
            :if={@state.enrollment}
            id="academy-terms"
            class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-stone-500">термины</p>
                <h2 class="mt-1 font-serif text-2xl text-stone-100">Ведомость пути</h2>
                <p id="academy-term-count" class="mt-1 text-sm text-stone-400">
                  Зафиксировано терминов: {length(@state.terms)} из {@state.required_terms}
                </p>
                <p
                  :if={@state.current_term_schedule}
                  id="academy-current-term-window"
                  class="mt-1 text-xs text-sky-100"
                >
                  Окно текущего термина: {format_time(@state.current_term_schedule.starts_at)} — {format_time(
                    @state.current_term_schedule.ends_at
                  )}
                </p>
                <p
                  :if={is_nil(@state.current_term) && @state.next_term_schedule}
                  id="academy-next-term-window"
                  class="mt-1 text-xs text-sky-100"
                >
                  Следующий термин откроется: {format_time(@state.next_term_schedule.starts_at)}
                </p>
              </div>
              <button
                :if={is_nil(@state.current_term)}
                id="academy-begin-term"
                type="button"
                phx-click="begin_term"
                class="rounded bg-sky-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Начать следующий термин
              </button>
              <button
                :if={@state.current_term && @state.term_progress.phase == :enrollment}
                id="academy-open-lectures"
                type="button"
                phx-click="open_lecture_phase"
                class="rounded bg-sky-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Закрыть выбор курсов
              </button>
              <.link
                :if={@state.current_term && @state.term_progress.phase == :lectures}
                id="academy-attend-lecture"
                navigate={~p"/academy/lecture/#{@state.current_term.id}"}
                class="rounded bg-violet-300 px-3 py-2 text-sm font-semibold text-stone-950 transition hover:bg-violet-200"
              >
                Открыть лекцию ({@state.term_progress.lectures_attended}/{@state.term_progress.lectures_required})
              </.link>
              <button
                :if={@state.current_term && @state.term_progress.phase == :lectures}
                id="academy-close-lectures"
                type="button"
                phx-click="close_lecture_phase"
                class="rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-950/50"
              >
                Перейти к клубному окну
              </button>
              <.link
                :if={@state.current_term && @state.term_progress.phase in [:midterm, :final]}
                id="academy-open-exam"
                navigate={~p"/academy/exam/#{@state.current_term.id}"}
                class="rounded bg-amber-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                {term_phase_label(@state.term_progress.phase)}
              </.link>
            </div>
            <section
              :if={@state.current_term && @state.term_progress.phase == :club_window}
              id="academy-club-window"
              class="mt-4 rounded-xl border border-emerald-400/25 bg-emerald-950/15 p-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.16em] text-emerald-200/75">клубное окно</p>
                  <p id="academy-club-window-attendance" class="mt-1 text-sm text-stone-200">
                    Посещено событий: {@state.term_progress.club_events_attended}/ {@state.term_progress.club_events_required}
                  </p>
                  <p class="mt-1 text-sm text-stone-400">
                    Участие в реальном событии клуба фиксируется в ведомости и нужно для мерит-рейтинга.
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.link
                    id="academy-club-window-link"
                    navigate={~p"/academy/clubs"}
                    class="rounded border border-emerald-300/50 px-3 py-2 text-sm text-emerald-100"
                  >
                    К клубам
                  </.link>
                  <button
                    id="academy-close-club-window"
                    type="button"
                    phx-click="close_club_window"
                    class="rounded bg-emerald-300 px-3 py-2 text-sm font-semibold text-stone-950"
                  >
                    Перейти к мидтерму
                  </button>
                </div>
              </div>
            </section>
            <ul id="academy-term-list" class="mt-4 space-y-2">
              <li
                :for={term <- @state.terms}
                id={"academy-term-#{term.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 px-4 py-3 text-sm"
              >
                <span>Термин {term.term_number}</span>
                <span class="text-stone-300">
                  {term_status(term.status)} · {term_phase_label(term_phase(term))} · экзамен: {term.exam_score ||
                    "—"}
                </span>
              </li>
              <li
                :if={@state.terms == []}
                id="academy-terms-empty"
                class="rounded-lg bg-stone-950/55 px-4 py-3 text-sm text-stone-400"
              >
                Термины ещё не начаты.
              </li>
            </ul>
          </section>

          <section
            :if={@state.cohort_leaderboard != []}
            id="academy-cohort-leaderboard"
            class="rounded-2xl border border-amber-400/20 bg-amber-950/10 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-amber-100/75">когорта</p>
                <h2 class="mt-1 font-serif text-2xl text-amber-100">Открытая ведомость</h2>
              </div>
              <p class="text-sm text-stone-400">
                Верхняя четверть и merit grant учитывают подтверждённое клубное участие.
              </p>
            </div>
            <ol class="mt-4 space-y-2">
              <li
                :for={entry <- @state.cohort_leaderboard}
                id={"academy-cohort-rank-#{entry.enrollment.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 px-4 py-3 text-sm"
              >
                <span>
                  №{entry.rank} · {entry.character.name}
                  <span :if={entry.ranking_eligible?} class="text-emerald-200">· merit</span>
                </span>
                <span class="text-stone-300">GPA {gpa_label(entry.gpa)}</span>
              </li>
            </ol>
          </section>

          <section
            :if={@state.current_term}
            id="academy-courses"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">
                  каталог текущего термина
                </p>
                <h2 class="mt-1 font-serif text-2xl text-violet-100">Курсы realm</h2>
              </div>
              <span class="text-sm text-stone-400">
                {if @state.term_progress.phase == :enrollment,
                  do: "Запись проверяет ваш термин, путь и realm.",
                  else: "Выбор курсов закрыт; в ведомости остались только подтверждённые записи."}
              </span>
            </div>
            <div class="mt-4 grid gap-3 md:grid-cols-2">
              <article
                :for={course <- visible_courses(@state)}
                id={"academy-course-#{course.id}"}
                class="rounded-xl border border-violet-300/15 bg-stone-950/55 p-4"
              >
                <p class="text-xs uppercase tracking-[0.16em] text-stone-500">
                  {course_track_label(course.track)} · {course_school_label(course.school)}
                </p>
                <h3 class="mt-1 font-serif text-lg text-stone-100">{course.title}</h3>
                <p class="mt-2 text-sm text-stone-400">{course_summary(course)}</p>
                <p
                  :if={enrolled?(course, @state.course_enrollments)}
                  class="mt-3 text-sm text-emerald-200"
                >
                  Вы уже записаны.
                </p>
                <p
                  :if={office_hours_attended?(course, @state.course_enrollments)}
                  id={"academy-office-hours-attended-#{course.id}"}
                  class="mt-2 text-sm text-amber-100"
                >
                  Приёмные часы посещены · +5 к итоговой ведомости курса.
                </p>
                <button
                  :if={
                    not enrolled?(course, @state.course_enrollments) &&
                      @state.term_progress.phase == :enrollment
                  }
                  id={"academy-enroll-course-#{course.id}"}
                  type="button"
                  phx-click="enroll_course"
                  phx-value-course-id={course.id}
                  class="mt-3 rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100"
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
                  class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
                >
                  Посетить приёмные часы
                </button>
              </article>
              <p
                :if={visible_courses(@state) == []}
                id="academy-courses-empty"
                class="text-sm text-stone-400"
              >
                Для этого пути пока нет опубликованных курсов.
              </p>
            </div>
          </section>

          <nav
            id="academy-navigation"
            class="flex flex-wrap gap-2 rounded-2xl border border-stone-700 bg-stone-900/70 p-4 text-sm"
          >
            <.link navigate={~p"/academy"} class="rounded px-3 py-2 hover:bg-stone-800">Холл</.link>
            <.link navigate={~p"/academy/timetable"} class="rounded px-3 py-2 hover:bg-stone-800">
              Расписание
            </.link>
            <.link navigate={~p"/academy/grades"} class="rounded px-3 py-2 hover:bg-stone-800">
              Ведомость
            </.link>
            <.link navigate={~p"/academy/courses"} class="rounded px-3 py-2 hover:bg-stone-800">
              Курсы
            </.link>
            <.link navigate={~p"/academy/clubs"} class="rounded px-3 py-2 hover:bg-stone-800">
              Клубы
            </.link>
            <.link navigate={~p"/academy/research"} class="rounded px-3 py-2 hover:bg-stone-800">
              Наука
            </.link>
            <.link navigate={~p"/academy/bulletin-board"} class="rounded px-3 py-2 hover:bg-stone-800">
              Доска
            </.link>
          </nav>
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

  defp program_options(options), do: Enum.map(options, &{&1.label, &1.code})
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
  defp program_label(:academy_core), do: "Academy Core"
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
  defp term_phase_label(:midterm), do: "Открыть мидтерм"
  defp term_phase_label(:final), do: "Открыть финал"
  defp term_phase_label(:break), do: "Перерыв"
  defp term_phase_label(_phase), do: "Ведомость"
  defp track_label(:wizardry), do: "Чародейство"
  defp track_label(:alchemy), do: "Алхимия"
  defp track_label(:mastery), do: "Мастерство"
  defp track_label(_track), do: "Общий путь"
  defp course_track_label(track), do: track_label(track)
  defp course_school_label(nil), do: "общий"
  defp course_school_label(school), do: school |> to_string() |> String.capitalize()

  defp school_suffix(%{track: :wizardry, primary_school: first, secondary_school: second}),
    do: " · #{String.capitalize(to_string(first))} + #{String.capitalize(to_string(second))}"

  defp school_suffix(_specialization), do: ""

  defp retraining_enrollment?(%{metadata: metadata}),
    do: is_binary(Map.get(metadata || %{}, "retraining_from_specialization_id"))

  defp retraining_enrollment?(_enrollment), do: false
  defp gpa_label(nil), do: "—"
  defp gpa_label(gpa), do: to_string(gpa)
  defp record_failed_terms(nil), do: 0
  defp record_failed_terms(record), do: record.failed_terms
  defp outcome_label(:distinction), do: "с отличием"
  defp outcome_label(:pass), do: "зачёт"
  defp outcome_label(:probation), do: "испытательный выпуск"
  defp outcome_label(:expulsion), do: "отчисление"
  defp outcome_label(:capstone_incomplete), do: "не пройден итоговый проект"
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
    do: "Заклинание: #{name} · #{String.capitalize(school)}"

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
