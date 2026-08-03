defmodule MMGOWeb.BulletinBoardLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGO.Academia
  alias MMGO.Clubs
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        realm_id = character.realm_id

        {:ok,
         socket
         |> assign(:page_title, "Доска объявлений")
         |> assign(:character, character)
         |> assign(:realm_id, realm_id)
         |> assign(:courses, load_courses(character))
         |> assign(:upcoming_events, load_events(realm_id))
         |> assign(:leaderboard, load_leaderboard(character))
         |> assign(:hall_of_fame, Academy.list_valedictorians_for_realm(realm_id))
         |> assign(:thesis_defenses, Academia.list_open_thesis_defenses_for_realm(realm_id))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bulletin-board">
        <.link id="bulletin-back-to-academy" navigate={~p"/academy"} class="map-back-link">
          ← В холл Академии
        </.link>
        <h1>Доска объявлений</h1>

        <section id="bulletin-courses" class="bb-section">
          <h2>Курсы семестра</h2>
          <div class="bb-table-wrap">
            <table class="bb-table">
              <thead>
                <tr>
                  <th>Курс</th>
                  <th>Путь</th>
                  <th>Профессор</th>
                  <th>Источник</th>
                </tr>
              </thead>
              <tbody>
                <%= for course <- @courses do %>
                  <tr>
                    <td data-label="Курс">{course_title(course)}</td>
                    <td data-label="Путь">{track_label(course.track)}</td>
                    <td data-label="Профессор">
                      {professor_label(course.npc_professor_code)}
                    </td>
                    <td data-label="Источник">{source_label(course.source)}</td>
                  </tr>
                <% end %>
                <%= if @courses == [] do %>
                  <tr class="bb-table__empty">
                    <td colspan="4">
                      <div class="acd-empty">
                        Курсы ещё не вывешены. Писарь оставил место для первого листка.
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>

        <section class="bb-section">
          <h2>Клубные события</h2>
          <ul class="bb-list">
            <%= for event <- @upcoming_events do %>
              <li>
                <strong>{event.club && event.club.name}</strong>
                — {event_kind_label(event.kind)} · {Calendar.strftime(
                  event.scheduled_at,
                  "%d.%m %H:%M UTC"
                )}
                <.link navigate={~p"/academy/club-events/#{event.id}"}>записаться</.link>
              </li>
            <% end %>
            <%= if @upcoming_events == [] do %>
              <li>На этой неделе клубы молчат. Следите за печатями президентов.</li>
            <% end %>
          </ul>
        </section>

        <section id="bulletin-hall-of-fame" class="bb-section">
          <h2>Зал славы</h2>
          <p class="bb-muted">
            Валедикторианы остаются на этой доске один реальный год после выпуска.
          </p>
          <ul class="bb-list">
            <%= for enrollment <- @hall_of_fame do %>
              <li id={"bulletin-valedictorian-#{enrollment.id}"}>
                <strong>{enrollment.character.name}</strong>
                — {Academy.valedictorian_title(enrollment)} · {program_label(enrollment.program_type)}
                <span class="bb-muted">· до {hall_of_fame_until_label(enrollment)}</span>
              </li>
            <% end %>
            <%= if @hall_of_fame == [] do %>
              <li>Пока ни один выпускник не занял первое место в подтверждённой когорте.</li>
            <% end %>
          </ul>
        </section>

        <section class="bb-section">
          <h2>Рейтинг когорты</h2>
          <ol class="bb-list">
            <%= for entry <- @leaderboard do %>
              <li id={"bulletin-cohort-rank-#{entry.enrollment.id}"}>
                {entry.rank}-е место — студент <strong>{entry.character.name}</strong>
                — средний балл {entry.gpa || "—"}
                <span :if={entry.ranking_eligible?}> · стипендия</span>
              </li>
            <% end %>
            <%= if @leaderboard == [] do %>
              <li>Рейтинг ещё пуст: экзаменационные ведомости не принесли в холл.</li>
            <% end %>
          </ol>
        </section>

        <section class="bb-section">
          <h2>Открытые защиты</h2>
          <ul class="bb-list">
            <%= for defense <- @thesis_defenses do %>
              <li id={"bulletin-thesis-#{defense.id}"}>
                <strong>{defense.character.name}</strong>
                — «{defense.title}» · {thesis_state_label(defense.defense_state)}
                <.link navigate={~p"/academy/thesis/#{defense.id}"}>слушать</.link>
              </li>
            <% end %>
            <%= if @thesis_defenses == [] do %>
              <li>Сегодня открытых защит нет.</li>
            <% end %>
          </ul>
        </section>

        <div class="bb-nav">
          <.link id="bulletin-study-desk-link" navigate={~p"/academy/study-desk"}>
            К своему столу
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_courses(character) do
    enrollment = Academy.current_enrollment(character.id)

    case {enrollment, enrollment && Academy.current_term(enrollment.id)} do
      {%{} = enrollment, %{term_number: term_number}} ->
        Academy.list_courses_for_term(enrollment, term_number)

      _other ->
        Academy.list_courses_for_realm(character.realm_id)
    end
  end

  defp load_events(nil), do: []

  defp load_events(realm_id), do: Clubs.list_upcoming_events_for_realm(realm_id)

  defp load_leaderboard(character) do
    enrollment =
      Academy.current_enrollment(character.id) ||
        List.last(Academy.enrollment_history(character.id))

    if enrollment, do: Academy.cohort_leaderboard(enrollment), else: []
  end

  defp source_label(:seeded), do: "курс Академии"
  defp source_label("seeded"), do: "курс Академии"
  defp source_label(:published), do: "профессорский"
  defp source_label("published"), do: "профессорский"
  defp source_label(_other), do: "академический"

  defp event_kind_label(:general_meeting), do: "общий круг"
  defp event_kind_label(:duel_tournament), do: "дуэльный турнир"
  defp event_kind_label(:research_session), do: "исследовательская встреча"
  defp event_kind_label(:expedition_briefing), do: "экспедиционный разбор"
  defp event_kind_label(_other), do: "событие"

  defp track_label(:wizardry), do: "Чародейство"
  defp track_label(:alchemy), do: "Алхимия"
  defp track_label(:mastery), do: "Мастерство"
  defp track_label(_track), do: "Общий курс"

  defp professor_label(nil), do: "профессор-игрок"
  defp professor_label("npc_historian"), do: "кафедра истории"
  defp professor_label("npc_elementalist"), do: "кафедра стихий"
  defp professor_label("npc_ranger"), do: "кафедра экспедиций"
  defp professor_label("npc_economist"), do: "кафедра экономики"
  defp professor_label("npc_magistrate"), do: "кафедра права"
  defp professor_label("npc_linguist"), do: "кафедра латыни"
  defp professor_label(code) when is_binary(code) and code != "", do: "наставник Академии"
  defp professor_label(_code), do: "профессор-игрок"

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

  defp program_label(:basic_education), do: "базовое образование"
  defp program_label(:academy_core), do: "Ядро Академии"
  defp program_label(:extended_study), do: "расширенный курс"
  defp program_label(:academia), do: "Академия наук"
  defp program_label(_program), do: "выпуск"

  defp hall_of_fame_until_label(enrollment) do
    enrollment
    |> Academy.hall_of_fame_until()
    |> Calendar.strftime("%d.%m.%Y")
  end

  defp thesis_state_label(:pending_defense), do: "слушание назначено"
  defp thesis_state_label(:under_review), do: "комиссия голосует"
  defp thesis_state_label(_state), do: "ожидает"
end
