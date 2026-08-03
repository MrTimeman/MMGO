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
         |> put_flash(:info, "Кафедра закрыта: вы получили статус почётного исследователя.")
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
         |> put_flash(:info, "Глава Академии утвердил испытательный допуск выпускника.")
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
         |> put_flash(:info, "Курс опубликован в каталоге мира.")
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
      <main id="academia-screen" class="acd-screen acd-research-screen">
        <div class="acd-research-shell">
          <div class="acd-research-tools">
            <.link
              id="academia-back-academy"
              navigate={~p"/academy"}
              class="acd-exit"
            >
              ← В Академию
            </.link>
            <button
              id="academia-refresh"
              type="button"
              phx-click="refresh"
              class="acd-clerk-action"
            >
              Сверить реестры
            </button>
          </div>

          <header class="acd-research-masthead">
            <div class="acd-research-crest" aria-hidden="true">A</div>
            <div class="acd-research-masthead__copy">
              <p class="acd-eyebrow">Академия наук · архив кафедры</p>
              <h1 class="acd-research-title">Исследования и кафедра</h1>
              <p class="acd-research-intro">
                Проекты, публикации и преподавание используют реальные записи мира. Завершение исследования назначается временем мира; тезис проходит отдельную открытую защиту.
              </p>
            </div>
            <span class="acd-research-masthead__number">реестр XVII</span>
          </header>

          <div
            :if={@error}
            id="academia-error"
            class="acd-red-slip"
          >
            {@error}
          </div>

          <section class="acd-folio-grid">
            <article
              id="academia-career"
              class="acd-dossier acd-dossier--appointment"
            >
              <span class="acd-dossier__clip" aria-hidden="true"></span>
              <p class="acd-kicker">личное дело · статус кафедры</p>
              <%= cond do %>
                <% @state.professor -> %>
                  <h2 id="academia-professor" class="acd-document-title">
                    Профессор
                  </h2>
                  <p class="acd-copy">
                    Ваши курсы появляются в общем каталоге; активные студенты смогут записываться только в совместимый термин и путь.
                  </p>
                  <button
                    id="academia-retire-professor"
                    type="button"
                    phx-click="retire_professor"
                    class="acd-ink-action acd-ink-action--muted"
                  >
                    Уйти в эмеритуру
                  </button>
                <% @state.emeritus_professor -> %>
                  <h2 id="academia-emeritus" class="acd-document-title">
                    Почётный исследователь
                  </h2>
                  <p class="acd-copy">
                    Вы больше не ведёте курсы, не участвуете в выборах главы и не берёте новых аспирантов. Право публикации и поручительства для выпускников с испытательным допуском сохранено.
                  </p>
                <% true -> %>
                  <h2 id="academia-researcher" class="acd-document-title">
                    Исследователь
                  </h2>
                  <p class="acd-copy">
                    Профессорство открывается после принятой защиты тезиса. Назначение проверяется сервером, а не этой кнопкой.
                  </p>
                  <button
                    id="academia-appoint-professor"
                    type="button"
                    phx-click="appoint"
                    class="acd-ink-action"
                  >
                    Подать на кафедру
                  </button>
              <% end %>
              <span class="acd-wax-seal acd-wax-seal--small" aria-hidden="true">каф.</span>
            </article>

            <article class="acd-dossier acd-dossier--active">
              <span class="acd-dossier__pin" aria-hidden="true"></span>
              <p class="acd-kicker">лист наблюдений · активная работа</p>
              <%= if @state.active_project do %>
                <h2 id="academia-active-project" class="acd-document-title">
                  {@state.active_project.title}
                </h2>
                <p class="acd-copy acd-copy--ruled">
                  {project_kind_label(@state.active_project.project_kind)} · завершение {format_time(
                    @state.active_project.completes_at
                  )}
                </p>
              <% else %>
                <h2 id="academia-no-active-project" class="acd-document-title">
                  Стол свободен
                </h2>
                <p class="acd-copy acd-copy--ruled">
                  После завершения программы Академии наук можно начать одну исследовательскую работу.
                </p>
              <% end %>
            </article>
          </section>

          <section
            id="academia-headship"
            class="acd-council-ledger"
          >
            <div class="acd-ledger-spine" aria-hidden="true"></div>
            <div class="acd-ledger-heading">
              <div>
                <p class="acd-kicker">протокол совета мира</p>
                <h2 id="academia-head" class="acd-ledger-title">
                  Глава Академии: {academy_head_name(@state.headship.head)}
                </h2>
              </div>
              <p
                :if={@state.headship.term_active?}
                id="academia-head-term"
                class="acd-term-stamp"
              >
                Полномочия до {format_time(@state.headship.term_ends_at)}
              </p>
            </div>
            <p class="acd-ledger-copy">
              Только действующие профессора этого мира выбирают главу на десятидневный срок. Состав избирателей фиксируется при открытии голосования; кафедра наставников в него не входит.
            </p>

            <button
              :if={@state.headship.can_open_election?}
              id="academia-open-head-election"
              type="button"
              phx-click="open_head_election"
              class="acd-seal-action"
            >
              Открыть выборы главы
            </button>

            <%= if @state.headship.open_election do %>
              <div id="academia-head-election" class="acd-ledger-section acd-ballot-sheet">
                <p id="academia-head-election-tally" class="acd-ledger-note">
                  Голосов: {@state.headship.open_election.votes_cast}/ {@state.headship.open_election.voter_count}; закрытие {format_time(
                    @state.headship.open_election.closes_at
                  )}.
                </p>
                <div class="acd-candidate-grid">
                  <article
                    :for={candidate <- @state.headship.open_election.candidates}
                    id={"academia-head-candidate-#{candidate.professor.character_id}"}
                    class="acd-ballot"
                  >
                    <span class="acd-ballot__mark" aria-hidden="true"></span>
                    <p class="acd-ballot__name">{candidate.professor.character.name}</p>
                    <p class="acd-ballot__votes">Поддержка: {candidate.votes}</p>
                    <button
                      :if={@state.headship.open_election.can_vote?}
                      id={"academia-vote-head-#{candidate.professor.character_id}"}
                      type="button"
                      phx-click="vote_head"
                      phx-value-candidate-id={candidate.professor.character_id}
                      class="acd-ink-action acd-ink-action--compact"
                    >
                      Голосовать
                    </button>
                  </article>
                </div>
                <p
                  :if={not @state.headship.open_election.can_vote?}
                  id="academia-head-vote-recorded"
                  class="acd-margin-note"
                >
                  Ваш голос уже учтён или вы не вошли в зафиксированный состав профессоров.
                </p>
                <button
                  :if={@state.headship.can_settle_election?}
                  id="academia-settle-head-election"
                  type="button"
                  phx-click="settle_head_election"
                  class="acd-clerk-action acd-clerk-action--on-paper"
                >
                  Подвести итог срока голосования
                </button>
              </div>
            <% end %>

            <section
              :if={current_academy_head?(@state) and @state.headship_admission_candidates != []}
              id="academia-head-probation-admissions"
              class="acd-ledger-section"
            >
              <h3 class="acd-ledger-subtitle">Испытательный допуск выпускников</h3>
              <p class="acd-ledger-copy">
                Решение создаёт непередаваемую запись допуска в Ядро Академии и не меняет деньги или оценки кандидата.
              </p>
              <div class="acd-candidate-grid acd-candidate-grid--wide">
                <article
                  :for={candidate <- @state.headship_admission_candidates}
                  id={"academia-head-admission-candidate-#{candidate.character.id}"}
                  class="acd-approval-slip"
                >
                  <p class="acd-approval-slip__name">{candidate.character.name}</p>
                  <button
                    id={"academia-head-admit-#{candidate.character.id}"}
                    type="button"
                    phx-click="admit_probation_as_head"
                    phx-value-candidate-id={candidate.character.id}
                    class="acd-ink-action acd-ink-action--compact"
                  >
                    Утвердить допуск
                  </button>
                </article>
              </div>
            </section>

            <section
              :if={current_academy_head?(@state)}
              id="academia-head-charity-stipends"
              class="acd-ledger-section"
            >
              <div class="acd-ledger-subhead">
                <div>
                  <h3 class="acd-ledger-subtitle">Стипендии Фонда Просвещения</h3>
                  <p class="acd-ledger-copy">
                    Разовая стипендия доступна только действующему студенту Ядра Академии с грантовым финансированием. Средства переходят из фонда прямо в его кошелёк и оставляют квитанцию в ведомости.
                  </p>
                </div>
                <p id="academia-charity-fund-balance" class="acd-fund-seal">
                  В фонде: {@state.charity_fund_balance} ◈
                </p>
              </div>

              <%= if @state.headship_charity_stipend_candidates == [] do %>
                <p id="academia-charity-stipends-empty" class="acd-margin-note">
                  Сейчас нет студентов с грантовой записью, ожидающих первую стипендию.
                </p>
              <% else %>
                <.form
                  for={@charity_stipend_form}
                  id="academia-charity-stipend-form"
                  phx-submit="award_charity_stipend"
                  class="acd-form acd-form--triple"
                >
                  <.input
                    field={@charity_stipend_form[:candidate_id]}
                    type="select"
                    label="Студент"
                    class="acd-control"
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
                    class="acd-control"
                  />
                  <button
                    id="academia-award-charity-stipend"
                    type="submit"
                    class="acd-seal-action"
                  >
                    Выдать стипендию
                  </button>
                </.form>
              <% end %>
            </section>

            <section
              :if={current_academy_head?(@state)}
              id="academia-head-curriculum"
              class="acd-ledger-section"
            >
              <h3 class="acd-ledger-subtitle">Коррекция учебного плана</h3>
              <p class="acd-ledger-copy">
                Глава Академии переносит только активные базовые курсы на допустимый термин. Это меняет будущий выбор курсов в каталоге, но не переименовывает курс и не трогает уже открытые ведомости.
              </p>

              <%= if @state.headship_curriculum_courses == [] do %>
                <p id="academia-head-curriculum-empty" class="acd-margin-note">
                  Базовые курсы для этого мира ещё не подготовлены.
                </p>
              <% else %>
                <.form
                  for={@curriculum_override_form}
                  id="academia-head-curriculum-form"
                  phx-submit="set_curriculum_override"
                  class="acd-form acd-form--triple"
                >
                  <.input
                    field={@curriculum_override_form[:course_id]}
                    type="select"
                    label="Базовый курс"
                    class="acd-control"
                    options={curriculum_course_options(@state.headship_curriculum_courses)}
                  />
                  <.input
                    field={@curriculum_override_form[:term_number]}
                    type="number"
                    label="Новый термин"
                    min="1"
                    max="10"
                    inputmode="numeric"
                    class="acd-control"
                  />
                  <button
                    id="academia-set-curriculum-override"
                    type="submit"
                    class="acd-seal-action"
                  >
                    Перенести курс
                  </button>
                </.form>

                <div id="academia-head-curriculum-courses" class="acd-curriculum-grid">
                  <article
                    :for={curriculum <- @state.headship_curriculum_courses}
                    id={"academia-curriculum-course-#{curriculum.course.id}"}
                    class="acd-curriculum-card"
                  >
                    <p class="acd-curriculum-card__title">{course_title(curriculum.course)}</p>
                    <p class="acd-curriculum-card__terms">
                      Базово: {curriculum_terms_label(curriculum.base_term_numbers)} · сейчас: {curriculum_terms_label(
                        curriculum.effective_term_numbers
                      )}
                    </p>
                    <p class="acd-curriculum-card__allowed">
                      Допустимые термины: {curriculum_terms_label(curriculum.allowed_term_numbers)}
                    </p>
                    <%= if curriculum.override do %>
                      <div
                        id={"academia-curriculum-override-#{curriculum.course.id}"}
                        class="acd-curriculum-card__override"
                      >
                        <p>Перенос внесён в реестр мира.</p>
                        <button
                          id={"academia-reset-curriculum-#{curriculum.course.id}"}
                          type="button"
                          phx-click="clear_curriculum_override"
                          phx-value-course-id={curriculum.course.id}
                          class="acd-clerk-action acd-clerk-action--on-paper"
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
            class="acd-appointment-letter"
          >
            <span class="acd-appointment-letter__fold" aria-hidden="true"></span>
            <p class="acd-kicker">закрытое назначение · наставник</p>
            <%= if @state.advisor do %>
              <h2 id="academia-current-advisor" class="acd-document-title">
                {advisor_name(@state.advisor, @state.professors)}
              </h2>
              <p class="acd-copy">
                Связь уже закреплена в записи Академии. Наставник участвует в комиссии вашей будущей защиты, если остаётся действующим профессором.
              </p>
              <p id="academia-advisor-bonus" class="acd-hand-note">
                Новые исследования идут на 20% быстрее; базовая награда за работу не уменьшается.
              </p>
            <% else %>
              <%= cond do %>
                <% not @state.academia_admitted? -> %>
                  <h2
                    id="academia-advisor-admission-required"
                    class="acd-document-title"
                  >
                    Сначала поступите в Академию наук
                  </h2>
                  <p class="acd-copy">
                    Наставник выбирается в момент поступления в Академию наук и ведёт вас через последующую исследовательскую работу.
                  </p>
                <% @state.advisor_pick_eligible? -> %>
                  <h2 id="academia-advisor-request" class="acd-document-title">
                    Выберите наставника
                  </h2>
                  <p class="acd-copy">
                    Ваше место в верхней десятой части Ядра Академии даёт право запросить любого действующего профессора своего мира.
                  </p>
                  <div class="acd-portrait-grid">
                    <article
                      :for={professor <- @state.professors}
                      :if={professor.character_id != @state.character.id}
                      id={"academia-advisor-#{professor.character_id}"}
                      class="acd-professor-slip"
                    >
                      <span class="acd-professor-slip__portrait" aria-hidden="true">
                        {String.first(professor.character.name)}
                      </span>
                      <p class="acd-professor-slip__name">{professor.character.name}</p>
                      <button
                        id={"academia-choose-advisor-#{professor.character_id}"}
                        type="button"
                        phx-click="choose_advisor"
                        phx-value-professor-id={professor.character_id}
                        class="acd-ink-action acd-ink-action--compact"
                      >
                        Запросить
                      </button>
                    </article>
                  </div>
                  <p
                    :if={not @state.advisor_match_available?}
                    id="academia-advisor-empty"
                    class="acd-margin-note"
                  >
                    В этом мире пока нет другого действующего профессора.
                  </p>
                <% true -> %>
                  <h2 id="academia-advisor-match" class="acd-document-title">
                    Назначение наставника
                  </h2>
                  <p class="acd-copy">
                    Право выбрать любого наставника получают выпускники верхней десятой части Ядра Академии. Остальным Академия подбирает действующего профессора по текущей нагрузке.
                  </p>
                  <button
                    :if={@state.advisor_match_available?}
                    id="academia-match-advisor"
                    type="button"
                    phx-click="match_advisor"
                    class="acd-ink-action"
                  >
                    Получить назначение
                  </button>
                  <p
                    :if={not @state.advisor_match_available?}
                    id="academia-advisor-empty"
                    class="acd-margin-note"
                  >
                    В этом мире пока нет другого действующего профессора.
                  </p>
              <% end %>
            <% end %>
            <span class="acd-wax-seal" aria-hidden="true">A</span>
          </section>

          <section class="acd-research-folio">
            <span class="acd-folio-tab">форма R-12</span>
            <h2 class="acd-document-title">Начать исследование</h2>
            <p class="acd-copy">
              Вид и название проверяются в домене; одновременно может идти только один проект.
            </p>
            <.form
              for={@research_form}
              id="academia-research-form"
              phx-submit="start_research"
              class="acd-form acd-form--research"
            >
              <.input
                field={@research_form[:project_kind]}
                type="select"
                label="Вид работы"
                class="acd-control"
                options={research_kind_options()}
              />
              <.input
                field={@research_form[:title]}
                type="text"
                label="Название"
                class="acd-control"
              />
              <button
                id="academia-start-research"
                type="submit"
                class="acd-seal-action"
              >
                Начать
              </button>
            </.form>
          </section>

          <section
            :if={@state.professor}
            id="academia-course-publication"
            class="acd-course-folio"
          >
            <span class="acd-course-folio__ribbon" aria-hidden="true"></span>
            <p class="acd-kicker">лист кафедры · новый курс</p>
            <h2 class="acd-document-title">Опубликовать курс</h2>
            <p class="acd-copy">
              Публикация одновременно создаёт запись каталога, поэтому студентам не нужно ждать отдельного ручного импорта.
            </p>
            <.form
              for={@course_form}
              id="academia-course-form"
              phx-submit="publish_course"
              class="acd-form acd-form--course"
            >
              <.input
                field={@course_form[:title]}
                type="text"
                label="Название курса"
                class="acd-control"
              />
              <.input
                field={@course_form[:summary]}
                type="text"
                label="Короткое описание"
                class="acd-control"
              />
              <.input
                field={@course_form[:track]}
                type="select"
                label="Путь"
                class="acd-control"
                options={track_options()}
              />
              <.input
                field={@course_form[:school]}
                type="select"
                label="Школа"
                class="acd-control"
                options={school_options()}
              />
              <button
                id="academia-publish-course"
                type="submit"
                class="acd-seal-action"
              >
                Опубликовать
              </button>
            </.form>
          </section>

          <section
            :if={@state.recommendation_authority?}
            id="academia-recommendations"
            class="acd-recommendation-file"
          >
            <p class="acd-kicker">исходящая корреспонденция</p>
            <h2 class="acd-document-title">Поручительства</h2>
            <p class="acd-copy">
              Профессор или почётный исследователь может запечатать непередаваемое поручительство для выпускника с испытательным допуском. Оно открывает только поступление в Ядро Академии и остаётся в его академической записи.
            </p>
            <div class="acd-letter-grid">
              <article
                :for={candidate <- @state.recommendation_candidates}
                id={"academia-recommendation-candidate-#{candidate.character.id}"}
                class="acd-recommendation-letter"
              >
                <span class="acd-recommendation-letter__seal" aria-hidden="true"></span>
                <p class="acd-recommendation-letter__name">{candidate.character.name}</p>
                <p class="acd-recommendation-letter__status">Выпуск: испытательный допуск</p>
                <button
                  id={"academia-write-recommendation-#{candidate.character.id}"}
                  type="button"
                  phx-click="write_recommendation"
                  phx-value-candidate-id={candidate.character.id}
                  class="acd-ink-action acd-ink-action--compact"
                >
                  Выдать поручительство
                </button>
              </article>
              <p
                :if={@state.recommendation_candidates == []}
                id="academia-recommendations-empty"
                class="acd-margin-note"
              >
                В этом мире сейчас нет выпускников, ожидающих поручительства.
              </p>
            </div>
          </section>

          <section class="acd-archive-ledger">
            <div class="acd-ledger-heading">
              <div>
                <p class="acd-kicker">ваши исследования</p>
                <h2 class="acd-ledger-title">Архив работ</h2>
              </div>
              <span class="acd-ledger-counter">{@state.projects |> length()} записей</span>
            </div>
            <ul id="academia-projects" phx-update="stream" class="acd-project-register">
              <li id="academia-projects-empty" class="acd-empty-stream">
                Исследовательских записей ещё нет.
              </li>
              <li
                :for={{dom_id, project} <- @streams.academia_projects}
                id={dom_id}
                class="acd-project-entry"
              >
                <div
                  id={"academia-project-#{project.id}"}
                  class="acd-project-entry__row"
                >
                  <div>
                    <p class="acd-project-entry__title">{project.title}</p>
                    <p class="acd-project-entry__meta">
                      {project_kind_label(project.project_kind)} · {project_status_label(
                        project.status
                      )}
                    </p>
                  </div>
                  <.link
                    :if={project.project_kind == :thesis and not is_nil(project.defense_state)}
                    id={"academia-thesis-#{project.id}"}
                    navigate={~p"/academy/thesis/#{project.id}"}
                    class="acd-ink-link"
                  >
                    Протокол защиты
                  </.link>
                </div>
              </li>
            </ul>
          </section>

          <section class="acd-library-case">
            <div class="acd-library-case__head">
              <p class="acd-kicker">библиотека мира</p>
              <h2>Каталог публикаций</h2>
            </div>
            <ul id="academia-publications" phx-update="stream" class="acd-publication-shelf">
              <li id="academia-publications-empty" class="acd-empty-stream">
                Публикаций пока нет.
              </li>
              <li
                :for={{dom_id, publication} <- @streams.academia_publications}
                id={dom_id}
                class="acd-publication-book"
              >
                <span class="acd-publication-book__bands" aria-hidden="true"></span>
                <p id={"academia-publication-#{publication.id}"} class="acd-publication-book__title">
                  {publication.title}
                </p>
                <p class="acd-publication-book__kind">
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
          {"#{character.name} · Ядро Академии", character.id}
        end)
    ]
  end

  defp curriculum_course_options(courses) do
    [
      {"Выберите базовый курс", ""}
      | Enum.map(courses, fn %{course: course, allowed_term_numbers: allowed_terms} ->
          {
            "#{course_title(course)} · термины #{curriculum_terms_label(allowed_terms)}",
            course.id
          }
        end)
    ]
  end

  defp curriculum_terms_label([]), do: "не указаны"

  defp curriculum_terms_label(term_numbers) when is_list(term_numbers),
    do: Enum.map_join(term_numbers, ", ", &to_string/1)

  defp curriculum_terms_label(_term_numbers), do: "не указаны"

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
