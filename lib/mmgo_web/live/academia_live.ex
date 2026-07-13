defmodule MMGOWeb.AcademiaLive do
  @moduledoc """
  Scoped research and professor-career surface for the Academy of Sciences.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @research_kind_options [
    {"Заклинание", "spell"},
    {"Зелье", "potion"},
    {"Инструмент", "tool"},
    {"Тезис", "thesis"}
  ]

  @track_options [
    {"Открытый курс", ""},
    {"Чародейство", "wizardry"},
    {"Алхимия", "alchemy"},
    {"Мастерство", "mastery"}
  ]

  @school_options [
    {"Без школы", ""},
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
         |> assign(:page_title, "Академия наук")
         |> assign(:error, nil)
         |> refresh_academia()}
    end
  end

  @impl true
  def handle_event("start_research", %{"research" => attrs}, socket) do
    case Play.start_scoped_research(socket.assigns.current_scope.character, attrs) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Исследование поставлено в очередь Академии.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("appoint", _params, socket) do
    case Play.appoint_scoped_professor(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Кафедра утвердила ваше профессорское назначение.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("retire_professor", _params, socket) do
    case Play.retire_scoped_professor(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Кафедра закрыта: вы получили статус Researcher Emeritus.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("open_head_election", _params, socket) do
    case Play.open_scoped_academy_head_election(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Открыты выборы главы Академии среди действующих профессоров.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("vote_head", %{"candidate-id" => candidate_character_id}, socket) do
    case Play.vote_scoped_academy_head(
           socket.assigns.current_scope.character,
           candidate_character_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Голос профессора записан в реестр Академии.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("settle_head_election", _params, socket) do
    case Play.settle_scoped_academy_head_election(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Срок голосования закрыт; итог записан в реестр Академии.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("admit_probation_as_head", %{"candidate-id" => candidate_character_id}, socket) do
    case Play.admit_scoped_probation_as_academy_head(
           socket.assigns.current_scope.character,
           candidate_character_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Глава Академии утвердил допуск выпускника с probation.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event(
        "award_charity_stipend",
        %{"charity_stipend" => %{"candidate_id" => candidate_character_id, "amount" => amount}},
        socket
      ) do
    with {:ok, amount} <- parse_positive_amount(amount),
         {:ok, state} <-
           Play.award_scoped_academy_head_charity_stipend(
             socket.assigns.current_scope.character,
             candidate_character_id,
             amount
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Стипендия переведена из благотворительного фонда и записана в ведомость."
       )
       |> assign(:error, nil)
       |> assign_state(state)}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event(
        "set_curriculum_override",
        %{"curriculum" => %{"course_id" => course_id, "term_number" => term_number}},
        socket
      ) do
    with {:ok, term_number} <- parse_positive_term_number(term_number),
         {:ok, state} <-
           Play.set_scoped_academy_head_curriculum_override(
             socket.assigns.current_scope.character,
             course_id,
             term_number
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Расписание курса изменено решением главы Академии.")
       |> assign(:error, nil)
       |> assign_state(state)}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("set_curriculum_override", _params, socket) do
    {:noreply, assign(socket, :error, error_message(:invalid_term_number))}
  end

  @impl true
  def handle_event("clear_curriculum_override", %{"course-id" => course_id}, socket) do
    case Play.clear_scoped_academy_head_curriculum_override(
           socket.assigns.current_scope.character,
           course_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Курс возвращён к базовому расписанию.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("choose_advisor", %{"professor-id" => professor_character_id}, socket) do
    case Play.choose_scoped_advisor(
           socket.assigns.current_scope.character,
           professor_character_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Наставник внесён в вашу академическую запись.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("match_advisor", _params, socket) do
    case Play.match_scoped_advisor(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Академия закрепила наставника по доступности кафедры.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("write_recommendation", %{"candidate-id" => candidate_character_id}, socket) do
    case Play.write_scoped_admission_recommendation(
           socket.assigns.current_scope.character,
           candidate_character_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Рекомендация запечатана в академической записи студента.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("publish_course", %{"course" => attrs}, socket) do
    case Play.publish_scoped_course(socket.assigns.current_scope.character, attrs) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Курс опубликован в каталоге реалма.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_academia(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="academia-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-5xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="academia-back-academy"
              navigate={~p"/academy"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← В Академию
            </.link>
            <button
              id="academia-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200 transition hover:border-stone-400"
            >
              Обновить записи
            </button>
          </div>

          <header class="rounded-2xl border border-amber-400/25 bg-gradient-to-br from-amber-950/35 via-stone-950 to-sky-950/25 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.25em] text-amber-200/75">Академия наук</p>
            <h1 class="mt-2 font-serif text-3xl text-amber-100">Исследования и кафедра</h1>
            <p class="mt-3 max-w-3xl text-sm leading-6 text-stone-300">
              Проекты, публикации и преподавание используют реальные записи мира. Завершение исследования назначается временем мира; тезис проходит отдельную открытую защиту.
            </p>
          </header>

          <div
            :if={@error}
            id="academia-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section class="grid gap-4 lg:grid-cols-2">
            <article
              id="academia-career"
              class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-stone-500">статус кафедры</p>
              <%= cond do %>
                <% @state.professor -> %>
                  <h2 id="academia-professor" class="mt-2 font-serif text-2xl text-emerald-100">
                    Профессор
                  </h2>
                  <p class="mt-3 text-sm leading-6 text-stone-300">
                    Ваши курсы появляются в каталоге реалма; активные студенты смогут записываться только в совместимый термин и путь.
                  </p>
                  <button
                    id="academia-retire-professor"
                    type="button"
                    phx-click="retire_professor"
                    class="mt-5 rounded-lg border border-stone-500 px-4 py-3 text-sm font-semibold text-stone-200 transition hover:border-stone-300 hover:bg-stone-800"
                  >
                    Уйти в эмеритуру
                  </button>
                <% @state.emeritus_professor -> %>
                  <h2 id="academia-emeritus" class="mt-2 font-serif text-2xl text-violet-100">
                    Researcher Emeritus
                  </h2>
                  <p class="mt-3 text-sm leading-6 text-stone-300">
                    Вы больше не ведёте курсы, не участвуете в выборах главы и не берёте новых аспирантов. Право публикации и поручительства для probation-выпускников сохранено.
                  </p>
                <% true -> %>
                  <h2 id="academia-researcher" class="mt-2 font-serif text-2xl text-stone-100">
                    Исследователь
                  </h2>
                  <p class="mt-3 text-sm leading-6 text-stone-300">
                    Профессорство открывается после принятой защиты тезиса. Назначение проверяется сервером, а не этой кнопкой.
                  </p>
                  <button
                    id="academia-appoint-professor"
                    type="button"
                    phx-click="appoint"
                    class="mt-5 rounded-lg border border-amber-300/50 px-4 py-3 text-sm font-semibold text-amber-100 transition hover:bg-amber-950/35"
                  >
                    Подать на кафедру
                  </button>
              <% end %>
            </article>

            <article class="rounded-2xl border border-sky-400/20 bg-sky-950/15 p-6 shadow-lg">
              <p class="text-xs uppercase tracking-[0.2em] text-sky-200/75">активная работа</p>
              <%= if @state.active_project do %>
                <h2 id="academia-active-project" class="mt-2 font-serif text-2xl text-sky-100">
                  {@state.active_project.title}
                </h2>
                <p class="mt-3 text-sm text-stone-300">
                  {project_kind_label(@state.active_project.project_kind)} · завершение {format_time(
                    @state.active_project.completes_at
                  )}
                </p>
              <% else %>
                <h2 id="academia-no-active-project" class="mt-2 font-serif text-2xl text-sky-100">
                  Стол свободен
                </h2>
                <p class="mt-3 text-sm text-stone-300">
                  После завершения программы Academia можно начать одну исследовательскую работу.
                </p>
              <% end %>
            </article>
          </section>

          <section
            id="academia-headship"
            class="rounded-2xl border border-amber-400/25 bg-amber-950/15 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-amber-200/75">совет реалма</p>
                <h2 id="academia-head" class="mt-1 font-serif text-2xl text-amber-100">
                  Глава Академии: {academy_head_name(@state.headship.head)}
                </h2>
              </div>
              <p
                :if={@state.headship.term_active?}
                id="academia-head-term"
                class="text-sm text-amber-100"
              >
                Полномочия до {format_time(@state.headship.term_ends_at)}
              </p>
            </div>
            <p class="mt-3 text-sm leading-6 text-stone-300">
              Только действующие профессора реалма выбирают главу на десятидневный срок. Состав избирателей фиксируется при открытии голосования; NPC-кафедра в него не входит.
            </p>

            <button
              :if={@state.headship.can_open_election?}
              id="academia-open-head-election"
              type="button"
              phx-click="open_head_election"
              class="mt-4 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
            >
              Открыть выборы главы
            </button>

            <%= if @state.headship.open_election do %>
              <div id="academia-head-election" class="mt-5 border-t border-amber-300/20 pt-4">
                <p id="academia-head-election-tally" class="text-sm text-stone-300">
                  Голосов: {@state.headship.open_election.votes_cast}/ {@state.headship.open_election.voter_count}; закрытие {format_time(
                    @state.headship.open_election.closes_at
                  )}.
                </p>
                <div class="mt-4 grid gap-3 md:grid-cols-3">
                  <article
                    :for={candidate <- @state.headship.open_election.candidates}
                    id={"academia-head-candidate-#{candidate.professor.character_id}"}
                    class="rounded-xl border border-amber-300/15 bg-stone-950/55 p-4"
                  >
                    <p class="font-medium text-stone-100">{candidate.professor.character.name}</p>
                    <p class="mt-1 text-sm text-stone-400">Поддержка: {candidate.votes}</p>
                    <button
                      :if={@state.headship.open_election.can_vote?}
                      id={"academia-vote-head-#{candidate.professor.character_id}"}
                      type="button"
                      phx-click="vote_head"
                      phx-value-candidate-id={candidate.professor.character_id}
                      class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
                    >
                      Голосовать
                    </button>
                  </article>
                </div>
                <p
                  :if={not @state.headship.open_election.can_vote?}
                  id="academia-head-vote-recorded"
                  class="mt-3 text-sm text-stone-400"
                >
                  Ваш голос уже учтён или вы не вошли в зафиксированный состав профессоров.
                </p>
                <button
                  :if={@state.headship.can_settle_election?}
                  id="academia-settle-head-election"
                  type="button"
                  phx-click="settle_head_election"
                  class="mt-4 rounded border border-stone-500 px-3 py-2 text-sm text-stone-200"
                >
                  Подвести итог срока голосования
                </button>
              </div>
            <% end %>

            <section
              :if={current_academy_head?(@state) and @state.headship_admission_candidates != []}
              id="academia-head-probation-admissions"
              class="mt-5 border-t border-amber-300/20 pt-4"
            >
              <h3 class="font-serif text-xl text-amber-100">Допуск probation-выпускников</h3>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                Решение создаёт непередаваемую запись допуска к Academy Core и не меняет деньги или оценки кандидата.
              </p>
              <div class="mt-4 grid gap-3 md:grid-cols-2">
                <article
                  :for={candidate <- @state.headship_admission_candidates}
                  id={"academia-head-admission-candidate-#{candidate.character.id}"}
                  class="rounded-xl border border-amber-300/15 bg-stone-950/55 p-4"
                >
                  <p class="font-medium text-stone-100">{candidate.character.name}</p>
                  <button
                    id={"academia-head-admit-#{candidate.character.id}"}
                    type="button"
                    phx-click="admit_probation_as_head"
                    phx-value-candidate-id={candidate.character.id}
                    class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
                  >
                    Утвердить допуск
                  </button>
                </article>
              </div>
            </section>

            <section
              :if={current_academy_head?(@state)}
              id="academia-head-charity-stipends"
              class="mt-5 border-t border-amber-300/20 pt-4"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-3">
                <div>
                  <h3 class="font-serif text-xl text-amber-100">Стипендии Фонда Просвещения</h3>
                  <p class="mt-2 text-sm leading-6 text-stone-300">
                    Разовая стипендия доступна только действующему студенту Academy Core с грантовым финансированием. Средства переходят из фонда прямо в его кошелёк и оставляют квитанцию в ведомости.
                  </p>
                </div>
                <p id="academia-charity-fund-balance" class="text-sm text-amber-100">
                  В фонде: {@state.charity_fund_balance} ◈
                </p>
              </div>

              <%= if @state.headship_charity_stipend_candidates == [] do %>
                <p id="academia-charity-stipends-empty" class="mt-4 text-sm text-stone-400">
                  Сейчас нет студентов с грантовой записью, ожидающих первую стипендию.
                </p>
              <% else %>
                <.form
                  for={@charity_stipend_form}
                  id="academia-charity-stipend-form"
                  phx-submit="award_charity_stipend"
                  class="mt-4 grid gap-3 md:grid-cols-[minmax(0,1fr)_10rem_auto] md:items-end"
                >
                  <.input
                    field={@charity_stipend_form[:candidate_id]}
                    type="select"
                    label="Студент"
                    options={
                      charity_stipend_candidate_options(@state.headship_charity_stipend_candidates)
                    }
                  />
                  <.input
                    field={@charity_stipend_form[:amount]}
                    type="number"
                    label="Сумма"
                    min="1"
                    inputmode="numeric"
                  />
                  <button
                    id="academia-award-charity-stipend"
                    type="submit"
                    class="rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
                  >
                    Выдать стипендию
                  </button>
                </.form>
              <% end %>
            </section>

            <section
              :if={current_academy_head?(@state)}
              id="academia-head-curriculum"
              class="mt-5 border-t border-amber-300/20 pt-4"
            >
              <h3 class="font-serif text-xl text-amber-100">Коррекция учебного плана</h3>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                Глава Академии переносит только активные базовые курсы на допустимый термин. Это меняет будущий выбор курсов в каталоге, но не переименовывает курс и не трогает уже открытые ведомости.
              </p>

              <%= if @state.headship_curriculum_courses == [] do %>
                <p id="academia-head-curriculum-empty" class="mt-4 text-sm text-stone-400">
                  Базовые курсы для этого реалма ещё не посеяны.
                </p>
              <% else %>
                <.form
                  for={@curriculum_override_form}
                  id="academia-head-curriculum-form"
                  phx-submit="set_curriculum_override"
                  class="mt-4 grid gap-3 md:grid-cols-[minmax(0,1fr)_10rem_auto] md:items-end"
                >
                  <.input
                    field={@curriculum_override_form[:course_id]}
                    type="select"
                    label="Базовый курс"
                    options={curriculum_course_options(@state.headship_curriculum_courses)}
                  />
                  <.input
                    field={@curriculum_override_form[:term_number]}
                    type="number"
                    label="Новый термин"
                    min="1"
                    max="10"
                    inputmode="numeric"
                  />
                  <button
                    id="academia-set-curriculum-override"
                    type="submit"
                    class="rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
                  >
                    Перенести курс
                  </button>
                </.form>

                <div id="academia-head-curriculum-courses" class="mt-4 grid gap-3 md:grid-cols-2">
                  <article
                    :for={curriculum <- @state.headship_curriculum_courses}
                    id={"academia-curriculum-course-#{curriculum.course.id}"}
                    class="rounded-xl border border-amber-300/15 bg-stone-950/55 p-4"
                  >
                    <p class="font-medium text-stone-100">{curriculum.course.title}</p>
                    <p class="mt-1 text-sm text-stone-400">
                      Базово: {curriculum_terms_label(curriculum.base_term_numbers)} · сейчас: {curriculum_terms_label(
                        curriculum.effective_term_numbers
                      )}
                    </p>
                    <p class="mt-1 text-xs uppercase tracking-wide text-amber-100/75">
                      Допустимые термины: {curriculum_terms_label(curriculum.allowed_term_numbers)}
                    </p>
                    <%= if curriculum.override do %>
                      <div
                        id={"academia-curriculum-override-#{curriculum.course.id}"}
                        class="mt-3 flex flex-wrap items-center justify-between gap-3"
                      >
                        <p class="text-sm text-amber-100">Перенос внесён в реестр реалма.</p>
                        <button
                          id={"academia-reset-curriculum-#{curriculum.course.id}"}
                          type="button"
                          phx-click="clear_curriculum_override"
                          phx-value-course-id={curriculum.course.id}
                          class="rounded border border-stone-500 px-3 py-2 text-sm text-stone-200 transition hover:bg-stone-800"
                        >
                          Вернуть базовый план
                        </button>
                      </div>
                    <% end %>
                  </article>
                </div>
              <% end %>
            </section>
          </section>

          <section
            id="academia-advisor"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-6 shadow-lg"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">наставник</p>
            <%= if @state.advisor do %>
              <h2 id="academia-current-advisor" class="mt-2 font-serif text-2xl text-violet-100">
                {advisor_name(@state.advisor, @state.professors)}
              </h2>
              <p class="mt-3 text-sm leading-6 text-stone-300">
                Связь уже закреплена в записи Академии. Наставник участвует в комиссии вашей будущей защиты, если остаётся действующим профессором.
              </p>
              <p id="academia-advisor-bonus" class="mt-2 text-sm text-violet-100">
                Новые исследования идут на 20% быстрее; базовая награда за работу не уменьшается.
              </p>
            <% else %>
              <%= cond do %>
                <% not @state.academia_admitted? -> %>
                  <h2
                    id="academia-advisor-admission-required"
                    class="mt-2 font-serif text-2xl text-violet-100"
                  >
                    Сначала поступите в Academia
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-stone-300">
                    Наставник выбирается в момент поступления в Academia и ведёт вас через последующую исследовательскую работу.
                  </p>
                <% @state.advisor_pick_eligible? -> %>
                  <h2 id="academia-advisor-request" class="mt-2 font-serif text-2xl text-violet-100">
                    Выберите наставника
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-stone-300">
                    Ваше место в верхней десятой части Academy Core даёт право запросить любого действующего профессора своего реалма.
                  </p>
                  <div class="mt-5 grid gap-3 md:grid-cols-3">
                    <article
                      :for={professor <- @state.professors}
                      :if={professor.character_id != @state.character.id}
                      id={"academia-advisor-#{professor.character_id}"}
                      class="rounded-xl border border-violet-300/15 bg-stone-950/55 p-4"
                    >
                      <p class="font-medium text-stone-100">{professor.character.name}</p>
                      <button
                        id={"academia-choose-advisor-#{professor.character_id}"}
                        type="button"
                        phx-click="choose_advisor"
                        phx-value-professor-id={professor.character_id}
                        class="mt-3 rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-950/40"
                      >
                        Запросить
                      </button>
                    </article>
                  </div>
                  <p
                    :if={not @state.advisor_match_available?}
                    id="academia-advisor-empty"
                    class="mt-4 text-sm text-stone-400"
                  >
                    В реалме пока нет другого действующего профессора.
                  </p>
                <% true -> %>
                  <h2 id="academia-advisor-match" class="mt-2 font-serif text-2xl text-violet-100">
                    Назначение наставника
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-stone-300">
                    Право выбрать любого наставника получают выпускники верхней десятой части Academy Core. Остальным Академия подбирает действующего профессора по текущей нагрузке.
                  </p>
                  <button
                    :if={@state.advisor_match_available?}
                    id="academia-match-advisor"
                    type="button"
                    phx-click="match_advisor"
                    class="mt-5 rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-950/40"
                  >
                    Получить назначение
                  </button>
                  <p
                    :if={not @state.advisor_match_available?}
                    id="academia-advisor-empty"
                    class="mt-4 text-sm text-stone-400"
                  >
                    В реалме пока нет другого действующего профессора.
                  </p>
              <% end %>
            <% end %>
          </section>

          <section class="rounded-2xl border border-sky-400/20 bg-sky-950/15 p-6 shadow-lg">
            <h2 class="font-serif text-2xl text-sky-100">Начать исследование</h2>
            <p class="mt-2 text-sm text-stone-400">
              Вид и название проверяются в домене; одновременно может идти только один проект.
            </p>
            <.form
              for={@research_form}
              id="academia-research-form"
              phx-submit="start_research"
              class="mt-5 grid gap-3 md:grid-cols-[1fr_2fr_auto]"
            >
              <.input
                field={@research_form[:project_kind]}
                type="select"
                label="Вид работы"
                options={research_kind_options()}
              />
              <.input field={@research_form[:title]} type="text" label="Название" />
              <button
                id="academia-start-research"
                type="submit"
                class="self-end rounded-lg bg-sky-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-sky-200"
              >
                Начать
              </button>
            </.form>
          </section>

          <section
            :if={@state.professor}
            id="academia-course-publication"
            class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-6 shadow-lg"
          >
            <h2 class="font-serif text-2xl text-emerald-100">Опубликовать курс</h2>
            <p class="mt-2 text-sm text-stone-400">
              Публикация одновременно создаёт запись каталога, поэтому студентам не нужно ждать отдельного ручного импорта.
            </p>
            <.form
              for={@course_form}
              id="academia-course-form"
              phx-submit="publish_course"
              class="mt-5 grid gap-3 md:grid-cols-2"
            >
              <.input field={@course_form[:title]} type="text" label="Название курса" />
              <.input
                field={@course_form[:summary]}
                type="text"
                label="Короткое описание"
              />
              <.input
                field={@course_form[:track]}
                type="select"
                label="Путь"
                options={track_options()}
              />
              <.input
                field={@course_form[:school]}
                type="select"
                label="Школа"
                options={school_options()}
              />
              <button
                id="academia-publish-course"
                type="submit"
                class="rounded-lg bg-emerald-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-emerald-200"
              >
                Опубликовать
              </button>
            </.form>
          </section>

          <section
            :if={@state.recommendation_authority?}
            id="academia-recommendations"
            class="rounded-2xl border border-amber-400/20 bg-amber-950/15 p-6 shadow-lg"
          >
            <h2 class="font-serif text-2xl text-amber-100">Поручительства</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Профессор или Researcher Emeritus может запечатать непередаваемое поручительство для выпускника с probation. Оно открывает только поступление на Academy Core и остаётся в его академической записи.
            </p>
            <div class="mt-4 grid gap-3 md:grid-cols-2">
              <article
                :for={candidate <- @state.recommendation_candidates}
                id={"academia-recommendation-candidate-#{candidate.character.id}"}
                class="rounded-xl border border-amber-300/15 bg-stone-950/55 p-4"
              >
                <p class="font-medium text-stone-100">{candidate.character.name}</p>
                <p class="mt-1 text-sm text-stone-400">Выпуск: probation</p>
                <button
                  id={"academia-write-recommendation-#{candidate.character.id}"}
                  type="button"
                  phx-click="write_recommendation"
                  phx-value-candidate-id={candidate.character.id}
                  class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100 transition hover:bg-amber-950/40"
                >
                  Выдать поручительство
                </button>
              </article>
              <p
                :if={@state.recommendation_candidates == []}
                id="academia-recommendations-empty"
                class="text-sm text-stone-400"
              >
                В этом реалме сейчас нет выпускников, ожидающих поручительства.
              </p>
            </div>
          </section>

          <section class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg">
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-stone-500">ваши исследования</p>
                <h2 class="mt-1 font-serif text-2xl text-stone-100">Архив работ</h2>
              </div>
              <span class="text-sm text-stone-400">{@state.projects |> length()} записей</span>
            </div>
            <ul id="academia-projects" phx-update="stream" class="mt-5 space-y-2">
              <li id="academia-projects-empty" class="hidden only:block text-sm text-stone-400">
                Исследовательских записей ещё нет.
              </li>
              <li
                :for={{dom_id, project} <- @streams.academia_projects}
                id={dom_id}
                class="rounded-lg border border-stone-700 bg-stone-950/50 px-4 py-3"
              >
                <div
                  id={"academia-project-#{project.id}"}
                  class="flex flex-wrap items-center justify-between gap-3"
                >
                  <div>
                    <p class="font-medium text-stone-100">{project.title}</p>
                    <p class="mt-1 text-sm text-stone-400">
                      {project_kind_label(project.project_kind)} · {project_status_label(
                        project.status
                      )}
                    </p>
                  </div>
                  <.link
                    :if={project.project_kind == :thesis and not is_nil(project.defense_state)}
                    id={"academia-thesis-#{project.id}"}
                    navigate={~p"/academy/thesis/#{project.id}"}
                    class="text-sm text-violet-200 underline decoration-violet-500/40 underline-offset-4"
                  >
                    Протокол защиты
                  </.link>
                </div>
              </li>
            </ul>
          </section>

          <section class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-6 shadow-lg">
            <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">библиотека реалма</p>
            <ul id="academia-publications" phx-update="stream" class="mt-4 grid gap-3 md:grid-cols-2">
              <li id="academia-publications-empty" class="hidden only:block text-sm text-stone-400">
                Публикаций пока нет.
              </li>
              <li
                :for={{dom_id, publication} <- @streams.academia_publications}
                id={dom_id}
                class="rounded-lg border border-violet-300/15 bg-stone-950/50 px-4 py-3"
              >
                <p id={"academia-publication-#{publication.id}"} class="font-medium text-stone-100">
                  {publication.title}
                </p>
                <p class="mt-1 text-sm text-stone-400">
                  {publication_kind_label(publication.publication_kind)}
                </p>
              </li>
            </ul>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_academia(socket) do
    case Play.academia_state(socket.assigns.current_scope.character) do
      {:ok, state} -> assign_state(socket, state)
      {:error, _reason} -> push_navigate(socket, to: ~p"/map")
    end
  end

  defp assign_state(socket, state) do
    socket
    |> assign(:state, state)
    |> assign(:research_form, to_form(%{"project_kind" => "spell", "title" => ""}, as: :research))
    |> assign(
      :charity_stipend_form,
      to_form(%{"candidate_id" => "", "amount" => ""}, as: :charity_stipend)
    )
    |> assign(
      :curriculum_override_form,
      to_form(%{"course_id" => "", "term_number" => ""}, as: :curriculum)
    )
    |> assign(
      :course_form,
      to_form(%{"title" => "", "summary" => "", "track" => "", "school" => ""}, as: :course)
    )
    |> stream(:academia_projects, state.projects, reset: true)
    |> stream(:academia_publications, state.publications, reset: true)
  end

  defp project_kind_label(:spell), do: "заклинание"
  defp project_kind_label(:potion), do: "зелье"
  defp project_kind_label(:tool), do: "инструмент"
  defp project_kind_label(:thesis), do: "тезис"
  defp project_kind_label(:course), do: "курс"
  defp project_kind_label(_kind), do: "работа"

  defp publication_kind_label(:spell), do: "заклинание"
  defp publication_kind_label(:potion), do: "зелье"
  defp publication_kind_label(:tool), do: "инструмент"
  defp publication_kind_label(:thesis), do: "тезис"
  defp publication_kind_label(:course), do: "курс"
  defp publication_kind_label(_kind), do: "публикация"

  defp project_status_label(:active), do: "в работе"
  defp project_status_label(:completed), do: "завершено"
  defp project_status_label(:failed), do: "не завершено"
  defp project_status_label(:cancelled), do: "отменено"
  defp project_status_label(_status), do: "ожидает"

  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "не назначено"
  defp research_kind_options, do: @research_kind_options
  defp track_options, do: @track_options
  defp school_options, do: @school_options

  defp advisor_name(%{professor_character_id: professor_id}, professors) do
    case Enum.find(professors, &(&1.character_id == professor_id)) do
      %{character: %{name: name}} -> name
      _other -> "действующий наставник"
    end
  end

  defp academy_head_name(%{character: %{name: name}}) when is_binary(name), do: name
  defp academy_head_name(_head), do: "должность вакантна"

  defp current_academy_head?(%{character: character, headship: headship}) do
    headship.term_active? and not is_nil(headship.head) and
      headship.head.character_id == character.id
  end

  defp current_academy_head?(_state), do: false

  defp charity_stipend_candidate_options(candidates) do
    [
      {"Выберите студента", ""}
      | Enum.map(candidates, fn %{character: character} ->
          {"#{character.name} · Academy Core", character.id}
        end)
    ]
  end

  defp curriculum_course_options(courses) do
    [
      {"Выберите базовый курс", ""}
      | Enum.map(courses, fn %{course: course, allowed_term_numbers: allowed_terms} ->
          {
            "#{course.title} · термины #{curriculum_terms_label(allowed_terms)}",
            course.id
          }
        end)
    ]
  end

  defp curriculum_terms_label([]), do: "не указаны"

  defp curriculum_terms_label(term_numbers) when is_list(term_numbers),
    do: Enum.map_join(term_numbers, ", ", &to_string/1)

  defp curriculum_terms_label(_term_numbers), do: "не указаны"

  defp parse_positive_amount(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} when amount > 0 -> {:ok, amount}
      _other -> {:error, :invalid_amount}
    end
  end

  defp parse_positive_amount(_value), do: {:error, :invalid_amount}

  defp parse_positive_term_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {term_number, ""} when term_number > 0 -> {:ok, term_number}
      _other -> {:error, :invalid_term_number}
    end
  end

  defp parse_positive_term_number(_value), do: {:error, :invalid_term_number}

  defp error_message(:academy_location_unavailable),
    do: "Академические дела доступны только в городе."

  defp error_message(:research_unavailable), do: "Этот вид исследования сейчас недоступен."
  defp error_message(:research_title_required), do: "Укажите название работы."

  defp error_message(:professor_required),
    do: "Публиковать курсы может только действующий профессор."

  defp error_message(:course_publication_unavailable), do: "Параметры курса недопустимы."
  defp error_message(:advisor_unavailable), do: "Этот наставник недоступен для выбора."

  defp error_message(:recommendation_candidate_unavailable),
    do: "Этот выпускник больше не ожидает поручительства."

  defp error_message(:academy_head_election_unavailable),
    do: "Выборы главы Академии сейчас недоступны."

  defp error_message(:academy_head_admission_candidate_unavailable),
    do: "Этот выпускник больше не ожидает допуска главы Академии."

  defp error_message(:academy_head_charity_stipend_unavailable),
    do: "Эта стипендия больше недоступна для выдачи."

  defp error_message(:invalid_amount), do: "Укажите положительную сумму стипендии."

  defp error_message(:academy_head_curriculum_unavailable),
    do: "Этот курс сейчас недоступен для решения главы Академии."

  defp error_message(:invalid_term_number), do: "Укажите положительный номер термина."

  defp error_message(%Ecto.Changeset{}),
    do: "Академия отклонила это действие. Проверьте право и состояние работы."

  defp error_message(_reason), do: "Не удалось обновить запись Академии наук."
end
