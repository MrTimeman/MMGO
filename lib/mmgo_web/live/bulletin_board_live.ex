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
      <a href={~p"/map"} class="map-back-link">← World map</a>
      <h1>Academy Bulletin Board</h1>

      <section class="bb-section">
        <h2>Courses This Term</h2>
        <table class="bb-table">
          <thead>
            <tr>
              <th>Course</th>
              <th>Track</th>
              <th>Professor</th>
              <th>Source</th>
            </tr>
          </thead>
          <tbody>
            <%= for course <- @courses do %>
              <tr>
                <td>{course.title}</td>
                <td>{course.track || "—"}</td>
                <td>{course.npc_professor_code || "Player"}</td>
                <td>{course.source}</td>
              </tr>
            <% end %>
            <%= if @courses == [] do %>
              <tr>
                <td colspan="4">No courses available this term.</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </section>

      <section class="bb-section">
        <h2>Upcoming Club Events</h2>
        <ul class="bb-list">
          <%= for event <- @upcoming_events do %>
            <li>
              <strong>{event.club && event.club.name}</strong>
              — {event.kind} @ {Calendar.strftime(event.scheduled_at, "%Y-%m-%d %H:%M UTC")}
              <.link navigate={~p"/academy/club-events/#{event.id}"}>Join</.link>
            </li>
          <% end %>
          <%= if @upcoming_events == [] do %>
            <li>No upcoming events.</li>
          <% end %>
        </ul>
      </section>

      <section class="bb-section">
        <h2>Cohort Leaderboard</h2>
        <ol class="bb-list">
          <%= for {enrollment, gpa, rank} <- @leaderboard do %>
            <li>
              #{rank} — character <code>{enrollment.character_id}</code> — GPA {gpa || "—"}
            </li>
          <% end %>
          <%= if @leaderboard == [] do %>
            <li>No rankings yet.</li>
          <% end %>
        </ol>
      </section>

      <div class="bb-nav">
        <.link navigate={~p"/academy/study-desk"}>My Study Desk</.link>
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
end
