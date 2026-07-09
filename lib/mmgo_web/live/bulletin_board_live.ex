defmodule MMGOWeb.BulletinBoardLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGO.Accounts
  alias MMGO.Clubs
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, session, socket) do
    character = socket.assigns[:current_character] || load_character(session)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :city) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          realm_id = character.realm_id

          {:ok,
           socket
           |> assign(:page_title, "Bulletin Board")
           |> assign(:character, character)
           |> assign(:realm_id, realm_id)
           |> assign(:courses, load_courses(realm_id))
           |> assign(:upcoming_events, load_events(realm_id))
           |> assign(:leaderboard, load_leaderboard(realm_id))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bulletin-board">
      <a href={~p"/academy"} class="map-back-link">← В холл Академии</a>
      <h1>Доска объявлений</h1>

      <section class="bb-section">
        <h2>Курсы семестра</h2>
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
                <td>{course.title}</td>
                <td>{course.track || "—"}</td>
                <td>{course.npc_professor_code || "игрок-профессор"}</td>
                <td>{source_label(course.source)}</td>
              </tr>
            <% end %>
            <%= if @courses == [] do %>
              <tr>
                <td colspan="4">
                  <div class="acd-empty">
                    Курсы ещё не вывешены. Писарь оставил место для первого листка.
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
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

      <section class="bb-section">
        <h2>Рейтинг курса</h2>
        <ol class="bb-list">
          <%= for {enrollment, gpa, rank} <- @leaderboard do %>
            <li>
              {rank}-е место — студент <code>{enrollment.character_id}</code> — GPA {gpa || "—"}
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
          <li>
            <strong>Альберт Северин</strong>
            — «Двойная печать огня и хаоса» <.link navigate={~p"/academy/thesis/demo"}>слушать</.link>
          </li>
        </ul>
      </section>

      <div class="bb-nav">
        <.link navigate={~p"/academy/study-desk"}>К своему столу</.link>
      </div>
    </div>
    """
  end

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    Accounts.get_character!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

  defp load_courses(nil), do: []

  defp load_courses(realm_id), do: Academy.list_courses_for_realm(realm_id)

  defp load_events(nil), do: []

  defp load_events(realm_id), do: Clubs.list_upcoming_events_for_realm(realm_id)

  defp load_leaderboard(nil), do: []

  defp load_leaderboard(realm_id) do
    import Ecto.Query
    alias MMGO.Academy.Enrollment
    alias MMGO.Repo

    active_enrollments =
      Repo.all(
        from e in Enrollment,
          where: e.realm_id == ^realm_id and e.status == :active,
          order_by: [asc: e.inserted_at]
      )

    active_enrollments
    |> Enum.map(fn enrollment ->
      gpa = Academy.gpa_for_enrollment(enrollment.id)
      {enrollment, gpa}
    end)
    |> Enum.sort_by(fn {_, gpa} -> -(gpa || 0.0) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{enrollment, gpa}, rank} -> {enrollment, gpa, rank} end)
  end

  defp source_label(:seeded), do: "курс Академии"
  defp source_label("seeded"), do: "курс Академии"
  defp source_label(:published), do: "профессорский"
  defp source_label("published"), do: "профессорский"
  defp source_label(other), do: other || "—"

  defp event_kind_label(:general_meeting), do: "общий круг"
  defp event_kind_label(:duel_tournament), do: "дуэльный турнир"
  defp event_kind_label(:research_session), do: "исследовательская встреча"
  defp event_kind_label(:expedition_briefing), do: "экспедиционный разбор"
  defp event_kind_label(other), do: other || "событие"
end
