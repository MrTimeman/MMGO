defmodule MMGOWeb.ClubEventLive do
  @moduledoc """
  Scoped attendance surface for one real Academy-club event.

  The browser supplies only the event route. `MMGO.Play` verifies the event's
  realm, active club, membership, and prior attendance before exposing the
  attendance action.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @impl true
  def mount(%{"event_id" => event_id}, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        case Play.club_event_state(character, event_id) do
          {:ok, state} ->
            {:ok,
             socket
             |> assign(:page_title, "Клубное событие · #{event_kind_label(state.event.kind)}")
             |> assign(:error, nil)
             |> assign_state(state)}

          {:error, _reason} ->
            {:ok, push_navigate(socket, to: ~p"/academy/bulletin-board")}
        end
    end
  end

  @impl true
  def handle_event("attend", _params, socket) do
    case Play.attend_scoped_club_event(
           socket.assigns.character,
           socket.assigns.club.id,
           socket.assigns.event.id
         ) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Посещение внесено в протокол клуба.")
         |> assign(:error, nil)
         |> refresh_event()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("challenge_duel", %{"opponent-id" => opponent_id}, socket) do
    case Play.challenge_scoped_club_duel(
           socket.assigns.character,
           socket.assigns.event.id,
           opponent_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Приглашение на дружеский поединок отправлено.")
         |> assign(:error, nil)
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("accept_duel", %{"challenge-id" => challenge_id}, socket) do
    case Play.accept_scoped_club_duel(
           socket.assigns.character,
           socket.assigns.event.id,
           challenge_id
         ) do
      {:ok, %{combat: combat}} ->
        {:noreply, push_navigate(socket, to: ~p"/combat/#{combat.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("reject_duel", %{"challenge-id" => challenge_id}, socket) do
    case Play.reject_scoped_club_duel(
           socket.assigns.character,
           socket.assigns.event.id,
           challenge_id
         ) do
      {:ok, state} ->
        {:noreply,
         socket |> put_flash(:info, "Приглашение на поединок отклонено.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_event(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main
        id="club-event-screen"
        class="acd-screen acd-club-event-scene"
        data-event-kind={@event.kind}
      >
        <div class="acd-event-shell">
          <nav class="acd-event-nav" aria-label="Клубное событие">
            <.link
              id="club-event-back"
              navigate={~p"/academy/clubs/#{@club.id}"}
              class="acd-exit acd-clubs-back"
            >
              ← К клубу
            </.link>
            <button
              id="club-event-refresh"
              type="button"
              phx-click="refresh"
              class="acd-clubs-bell"
            >
              <span aria-hidden="true">↻</span> Сверить протокол
            </button>
          </nav>

          <header class="acd-event-hall">
            <div class="acd-event-hall__curtain acd-event-hall__curtain--left" aria-hidden="true">
            </div>
            <div class="acd-event-hall__curtain acd-event-hall__curtain--right" aria-hidden="true">
            </div>
            <div class="acd-event-hall__lamp" aria-hidden="true"></div>
            <div class="acd-event-hall__stage">
              <span class="acd-event-hall__crest" aria-hidden="true">
                {event_kind_sigil(@event.kind)}
              </span>
              <p>{@club.name}</p>
              <h1>{event_kind_label(@event.kind)}</h1>
              <span>{club_type_label(@club.club_type)}</span>
            </div>
          </header>

          <div
            :if={@error}
            id="club-event-error"
            class="acd-clubs-error"
          >
            {@error}
          </div>

          <div class="acd-event-table">
            <section class="acd-event-programme">
              <span class="acd-event-programme__fold" aria-hidden="true"></span>
              <header class="acd-event-programme__masthead">
                <p>Академическая программа</p>
                <h2>{event_kind_label(@event.kind)}</h2>
                <span>{@club.name}</span>
              </header>
              <p class="acd-event-programme__description">{event_description(@event.kind)}</p>

              <section id="club-event-details" class="acd-event-programme__details">
                <dl>
                  <div>
                    <dt>Назначено</dt>
                    <dd>{format_time(@event.scheduled_at)}</dd>
                  </div>
                  <div>
                    <dt>Статус</dt>
                    <dd id="club-event-status">{status_label(@event.status)}</dd>
                  </div>
                  <div>
                    <dt>Ваша запись</dt>
                    <dd>{membership_label(@membership)}</dd>
                  </div>
                </dl>
              </section>

              <section id="club-event-attendance" class="acd-event-attendance">
                <%= cond do %>
                  <% @attendance -> %>
                    <div
                      id="club-event-attended"
                      class="acd-attendance-entry acd-attendance-entry--signed"
                    >
                      <span class="acd-attendance-entry__stamp" aria-hidden="true">УЧТЕНО</span>
                      <p>Протокол принят</p>
                      <h2>Ваше имя уже внесено</h2>
                      <p id="club-event-xp">
                        Награда за это посещение: <strong>{attendance_xp(@attendance)} опыта</strong>.
                      </p>
                      <p
                        :if={research_note_credit(@attendance) > 0}
                        id="club-event-research-note"
                      >
                        Заметка передана в общий архив: она даст долю опыта, когда другой участник круга завершит исследование.
                      </p>
                      <p
                        :if={expedition_plan_credit(@attendance) > 0}
                        id="club-event-expedition-plan"
                      >
                        Маршрутная заметка сохранена: она станет общим планом, если весь отряд подготовится перед походом.
                      </p>
                      <p
                        :if={social_ties_formed(@attendance) > 0}
                        id="club-event-social-ties"
                      >
                        Встреча укрепила связей: {social_ties_formed(@attendance)}.
                      </p>
                    </div>
                  <% is_nil(@membership) -> %>
                    <div id="club-event-membership-required" class="acd-attendance-entry">
                      <p>Условия посещения</p>
                      <h2>Нужно состоять в клубе</h2>
                      <span>
                        Присутствие записывается только действующим участникам. Откройте карточку клуба, чтобы получить приглашение.
                      </span>
                    </div>
                  <% @event.status not in [:scheduled, :active] -> %>
                    <div id="club-event-closed" class="acd-attendance-entry">
                      <p>Архивная отметка</p>
                      <h2>Протокол закрыт</h2>
                      <span>Это событие больше не принимает посещения.</span>
                    </div>
                  <% @can_attend? -> %>
                    <div class="acd-attendance-entry acd-attendance-entry--open">
                      <p>Строка участника</p>
                      <h2>Внести себя в протокол</h2>
                      <span>
                        Награда за посещение сохранится на сервере и войдёт в клубную и академическую ведомость.
                      </span>
                      <button
                        id="club-event-attend"
                        type="button"
                        phx-click="attend"
                        class="acd-signature-button"
                      >
                        Поставить подпись
                      </button>
                    </div>
                <% end %>
              </section>
              <footer class="acd-event-programme__footer">
                <span>Печать клубной канцелярии</span>
                <i aria-hidden="true">{event_kind_sigil(@event.kind)}</i>
              </footer>
            </section>

            <section
              :if={@event.kind == :duel_tournament && @attendance}
              id="club-event-duels"
              class="acd-duel-tray"
            >
              <div class="acd-duel-tray__heading">
                <span aria-hidden="true">⚔</span>
                <div>
                  <p>После отметки</p>
                  <h2>Дружеские поединки</h2>
                </div>
              </div>
              <p class="acd-duel-tray__rules">
                Только отметившиеся участники могут отправлять и принимать приглашения. Поединки не используют ставку и не переносят добычу.
              </p>

              <div
                :if={@incoming_duel_challenges != []}
                id="club-event-incoming-duels"
                class="acd-duel-tray__letters"
              >
                <article
                  :for={challenge <- @incoming_duel_challenges}
                  id={"club-event-duel-incoming-#{challenge["id"]}"}
                  class="acd-duel-challenge"
                >
                  <span class="acd-duel-challenge__seal" aria-hidden="true">⚔</span>
                  <p>Вас вызвали на дружеский поединок.</p>
                  <div class="acd-duel-challenge__actions">
                    <button
                      id={"club-event-accept-duel-#{challenge["id"]}"}
                      type="button"
                      phx-click="accept_duel"
                      phx-value-challenge-id={challenge["id"]}
                      class="acd-btn acd-btn--primary"
                    >
                      Принять
                    </button>
                    <button
                      id={"club-event-reject-duel-#{challenge["id"]}"}
                      type="button"
                      phx-click="reject_duel"
                      phx-value-challenge-id={challenge["id"]}
                      class="acd-btn acd-btn--danger"
                    >
                      Отказать
                    </button>
                  </div>
                </article>
              </div>

              <div
                :if={@outgoing_duel_challenges != []}
                id="club-event-outgoing-duels"
                class="acd-duel-tray__outgoing"
              >
                <p :for={challenge <- @outgoing_duel_challenges}>
                  Приглашение на поединок ожидает ответа.
                </p>
              </div>

              <div
                :if={@accepted_duel_challenges != []}
                id="club-event-active-duels"
                class="acd-duel-tray__active"
              >
                <.link
                  :for={challenge <- @accepted_duel_challenges}
                  id={"club-event-open-duel-#{challenge["id"]}"}
                  navigate={~p"/combat/#{challenge["combat_id"]}"}
                  class="acd-btn acd-btn--primary"
                >
                  Открыть текущий поединок
                </.link>
              </div>

              <div
                :if={@duel_opponents != []}
                id="club-event-duel-opponents"
                class="acd-duel-roster"
              >
                <article
                  :for={opponent <- @duel_opponents}
                  id={"club-event-duel-opponent-#{opponent.id}"}
                  class="acd-duel-roster__entry"
                >
                  <span aria-hidden="true">{String.first(opponent.name)}</span>
                  <p>{opponent.name}</p>
                  <button
                    id={"club-event-challenge-duel-#{opponent.id}"}
                    type="button"
                    phx-click="challenge_duel"
                    phx-value-opponent-id={opponent.id}
                    class="acd-duel-roster__invite"
                  >
                    Послать вызов
                  </button>
                </article>
              </div>
              <p
                :if={@duel_opponents == [] && @incoming_duel_challenges == []}
                id="club-event-duel-opponents-empty"
                class="acd-duel-tray__empty"
              >
                Другие отметившиеся дуэлянты пока не готовы к приглашению.
              </p>
            </section>
          </div>
          <div class="acd-event-table__edge" aria-hidden="true"></div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_event(socket) do
    case Play.club_event_state(socket.assigns.character, socket.assigns.event.id) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_state(state)
      {:error, _reason} -> push_navigate(socket, to: ~p"/academy/clubs")
    end
  end

  defp assign_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:club, state.club)
    |> assign(:membership, state.membership)
    |> assign(:event, state.event)
    |> assign(:attendance, state.attendance)
    |> assign(:can_attend?, state.can_attend?)
    |> assign(:duel_opponents, state.duel_opponents)
    |> assign(:incoming_duel_challenges, state.incoming_duel_challenges)
    |> assign(:outgoing_duel_challenges, state.outgoing_duel_challenges)
    |> assign(:accepted_duel_challenges, state.accepted_duel_challenges)
  end

  defp event_description(:general_meeting),
    do: "Круг преданий и знакомство с будущими спутниками. Посещение даёт знания."

  defp event_description(:duel_tournament),
    do: "Дружеский турнир без ставок: посещение отмечается отдельно от результата поединка."

  defp event_description(:research_session),
    do: "Общий разбор заметок для исследовательской школы клуба."

  defp event_description(:expedition_briefing),
    do: "Сбор перед вылазкой: клуб фиксирует участие и подготовку группы."

  defp event_description(_kind), do: "Клубное событие этого мира."

  defp attendance_xp(attendance), do: Map.get(attendance.metadata || %{}, "xp_awarded", 0)

  defp research_note_credit(attendance),
    do: Map.get(attendance.metadata || %{}, "research_note_credit", 0)

  defp expedition_plan_credit(attendance),
    do: Map.get(attendance.metadata || %{}, "expedition_plan_credit", 0)

  defp social_ties_formed(attendance),
    do: Map.get(attendance.metadata || %{}, "social_ties_formed", 0)

  defp club_type_label(:general_interest), do: "общий круг"
  defp club_type_label(:dueling), do: "дуэльный клуб"
  defp club_type_label(:research), do: "исследовательское общество"
  defp club_type_label(:expedition_planning), do: "экспедиционный стол"
  defp club_type_label(_type), do: "клуб"
  defp event_kind_sigil(:general_meeting), do: "☙"
  defp event_kind_sigil(:duel_tournament), do: "⚔"
  defp event_kind_sigil(:research_session), do: "✎"
  defp event_kind_sigil(:expedition_briefing), do: "◇"
  defp event_kind_sigil(_kind), do: "◈"
  defp event_kind_label(:general_meeting), do: "Общий круг"
  defp event_kind_label(:duel_tournament), do: "Дуэльный турнир"
  defp event_kind_label(:research_session), do: "Исследовательская сессия"
  defp event_kind_label(:expedition_briefing), do: "Экспедиционный разбор"
  defp event_kind_label(_kind), do: "Клубное событие"
  defp membership_label(nil), do: "гость"
  defp membership_label(%{role: :leader}), do: "лидер"
  defp membership_label(%{role: :member}), do: "участник"
  defp membership_label(_membership), do: "участник"
  defp status_label(:scheduled), do: "назначено"
  defp status_label(:active), do: "идёт"
  defp status_label(:completed), do: "завершено"
  defp status_label(:cancelled), do: "отменено"
  defp status_label(_status), do: "неизвестно"
  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "не назначено"
  defp error_message(:club_event_unavailable), do: "Это событие уже недоступно для посещения."
  defp error_message(:club_membership_not_found), do: "Только участник клуба может отметиться."
  defp error_message(:club_duel_opponent_unavailable), do: "Этот дуэлянт сейчас недоступен."

  defp error_message(:club_duel_challenge_unavailable),
    do: "Приглашение на поединок больше недоступно."

  defp error_message(_reason), do: "Клуб не принял это посещение."
end
