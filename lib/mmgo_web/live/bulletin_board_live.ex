defmodule MMGOWeb.BulletinBoardLive do
  use MMGOWeb, :live_view

  alias MMGO.Academy
  alias MMGO.Clubs

  @tabs ~w(court schedule clubs ranks)
  @buildings [
    %{key: "wizardry", name: "Факультет Чародейства", sub: "Две школы на выбор", glyph: "✦"},
    %{key: "alchemy", name: "Факультет Алхимии", sub: "Варка, травы, перегонка", glyph: "⚗"},
    %{key: "mastery", name: "Факультет Мастерства", sub: "Оружие, доспех, ловушки", glyph: "⚒"},
    %{key: "academia", name: "Коллегия Исследований", sub: "Аспирантура и диссертации", glyph: "☉"},
  ]

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns[:current_character]
    realm_id = character && character.realm_id

    {:ok,
     socket
     |> assign(:page_title, "Академия")
     |> assign(:tab, "court")
     |> assign(:realm_id, realm_id)
     |> assign(:courses, load_courses(realm_id))
     |> assign(:upcoming_events, load_events(realm_id))
     |> assign(:leaderboard, load_leaderboard(realm_id))}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :buildings, @buildings)

    ~H"""
    <div class="ac-shell">
      <header class="ac-topbar">
        <.link navigate={~p"/play"} class="ac-topbar__back" aria-label="На карту">‹</.link>
        <div class="ac-topbar__crest">✦</div>
        <div class="ac-topbar__title">
          <p class="ac-topbar__kicker">Ministry of Magic</p>
          <p class="ac-topbar__name">Академия</p>
        </div>
        <.link navigate={~p"/academy/study-desk"} class="inkbtn" style="font-size:0.72rem;padding:0.4rem 0.8rem;">
          Мой стол →
        </.link>
      </header>

      <nav class="ac-tabs">
        <button class={"ac-tab #{if @tab == "court", do: "is-active"}"} phx-click="switch_tab" phx-value-tab="court">Двор</button>
        <button class={"ac-tab #{if @tab == "schedule", do: "is-active"}"} phx-click="switch_tab" phx-value-tab="schedule">Расписание</button>
        <button class={"ac-tab #{if @tab == "clubs", do: "is-active"}"} phx-click="switch_tab" phx-value-tab="clubs">Клубы</button>
        <button class={"ac-tab #{if @tab == "ranks", do: "is-active"}"} phx-click="switch_tab" phx-value-tab="ranks">Рейтинг</button>
      </nav>

      <div class="ac-body">
        <%= case @tab do %>
          <% "court" -> %>
            <.court buildings={@buildings} />
          <% "schedule" -> %>
            <.schedule courses={@courses} />
          <% "clubs" -> %>
            <.clubs events={@upcoming_events} />
          <% "ranks" -> %>
            <.ranks leaderboard={@leaderboard} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :buildings, :list, required: true

  defp court(assigns) do
    ~H"""
    <div>
      <div class="ac-ornament">Факультеты</div>
      <%= for b <- @buildings do %>
        <button class="ac-building" type="button">
          <div class="ac-building__icon">{b.glyph}</div>
          <div class="ac-building__text">
            <div class="ac-building__name">{b.name}</div>
            <div class="ac-building__sub">{b.sub}</div>
          </div>
          <div class="ac-building__chevron">›</div>
        </button>
      <% end %>
    </div>
    """
  end

  attr :courses, :list, required: true

  defp schedule(assigns) do
    ~H"""
    <div>
      <div class="ac-ornament">Курсы семестра</div>
      <%= if @courses == [] do %>
        <div class="ac-empty">Курсов в этом семестре пока нет.</div>
      <% else %>
        <div class="ac-schedule">
          <%= for {course, i} <- Enum.with_index(@courses) do %>
            <div class={"ac-schedule__row #{if rem(i, 2) == 0, do: "", else: ""}"}>
              <span class="ac-schedule__day">—</span>
              <span class="ac-schedule__slot">{roman(i + 1)}</span>
              <div>
                <div class="ac-schedule__subj">{course.title}</div>
                <div class="ac-schedule__meta">
                  {course.track || "—"} · {course.npc_professor_code || "Игрок"}
                </div>
              </div>
              <span class="ac-chip">{course.source}</span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :events, :list, required: true

  defp clubs(assigns) do
    ~H"""
    <div>
      <div class="ac-ornament">Объявления</div>
      <%= if @events == [] do %>
        <div class="ac-corkboard">
          <div class="ac-notice" style="grid-column: span 2;">
            <div class="ac-notice__pin"></div>
            <div class="ac-notice__name" style="text-align:center; margin-top:0.5rem;">Пусто</div>
            <div class="ac-notice__note" style="text-align:center;">Мероприятий пока нет</div>
          </div>
        </div>
      <% else %>
        <div class="ac-corkboard">
          <%= for event <- @events do %>
            <div class="ac-notice">
              <div class="ac-notice__pin"></div>
              <div class="ac-notice__name">{event.club && event.club.name}</div>
              <div class="ac-notice__meta">{event.kind}</div>
              <div class="ac-notice__note">
                {Calendar.strftime(event.scheduled_at, "%d.%m %H:%M")}
              </div>
              <div style="margin-top:0.4rem;">
                <.link navigate={~p"/academy/club-events/#{event.id}"} class="inkbtn" style="font-size:0.68rem;padding:0.28rem 0.6rem;">
                  Участвовать
                </.link>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :leaderboard, :list, required: true

  defp ranks(assigns) do
    ~H"""
    <div>
      <div class="ac-ornament">Когорта</div>
      <%= if @leaderboard == [] do %>
        <div class="ac-empty">Рейтинга пока нет.</div>
      <% else %>
        <div class="ac-schedule">
          <%= for {_enrollment, gpa, rank} <- @leaderboard do %>
            <div class="ac-rank-row">
              <span class="ac-rank-row__num">#{rank}</span>
              <span class="ac-rank-row__name">Персонаж</span>
              <span class="ac-rank-row__gpa">GPA {format_gpa(gpa)}</span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

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

  defp format_gpa(nil), do: "—"
  defp format_gpa(gpa), do: :erlang.float_to_binary(gpa, decimals: 2)

  defp roman(n) do
    ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"] |> Enum.at(n - 1, to_string(n))
  end
end
