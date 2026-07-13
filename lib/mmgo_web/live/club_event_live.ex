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
      <main id="club-event-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="club-event-back"
              navigate={~p"/academy/clubs/#{@club.id}"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← К клубу
            </.link>
            <button
              id="club-event-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200 transition hover:border-stone-400"
            >
              Обновить
            </button>
          </div>

          <header class="rounded-2xl border border-emerald-400/25 bg-gradient-to-br from-emerald-950/30 via-stone-950 to-sky-950/20 p-7 shadow-xl">
            <p class="text-xs uppercase tracking-[0.24em] text-emerald-200/75">
              {@club.name} · {club_type_label(@club.club_type)}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-emerald-100">
              {event_kind_label(@event.kind)}
            </h1>
            <p class="mt-3 text-sm leading-6 text-stone-300">{event_description(@event.kind)}</p>
          </header>

          <div
            :if={@error}
            id="club-event-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section
            id="club-event-details"
            class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
          >
            <dl class="grid gap-4 text-sm sm:grid-cols-3">
              <div>
                <dt class="text-stone-500">Назначено</dt>
                <dd class="mt-1 text-stone-100">{format_time(@event.scheduled_at)}</dd>
              </div>
              <div>
                <dt class="text-stone-500">Статус</dt>
                <dd id="club-event-status" class="mt-1 text-stone-100">
                  {status_label(@event.status)}
                </dd>
              </div>
              <div>
                <dt class="text-stone-500">Ваш статус</dt>
                <dd class="mt-1 text-stone-100">{membership_label(@membership)}</dd>
              </div>
            </dl>
          </section>

          <section
            id="club-event-attendance"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-6 shadow-lg"
          >
            <%= cond do %>
              <% @attendance -> %>
                <div id="club-event-attended">
                  <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">
                    протокол принят
                  </p>
                  <h2 class="mt-2 font-serif text-2xl text-emerald-100">Вы уже присутствовали</h2>
                  <p id="club-event-xp" class="mt-3 text-sm text-stone-300">
                    Награда за это посещение: {attendance_xp(@attendance)} XP.
                  </p>
                  <p
                    :if={research_note_credit(@attendance) > 0}
                    id="club-event-research-note"
                    class="mt-2 text-sm text-cyan-100"
                  >
                    Заметка передана в общий архив: она даст долю XP, когда другой участник круга завершит исследование.
                  </p>
                  <p
                    :if={expedition_plan_credit(@attendance) > 0}
                    id="club-event-expedition-plan"
                    class="mt-2 text-sm text-lime-100"
                  >
                    Маршрутная заметка сохранена: она станет общим планом, если весь отряд подготовится перед походом.
                  </p>
                  <p
                    :if={social_ties_formed(@attendance) > 0}
                    id="club-event-social-ties"
                    class="mt-2 text-sm text-rose-100"
                  >
                    Встреча укрепила связей: {social_ties_formed(@attendance)}.
                  </p>
                </div>
              <% is_nil(@membership) -> %>
                <div id="club-event-membership-required">
                  <h2 class="font-serif text-2xl text-violet-100">Нужно состоять в клубе</h2>
                  <p class="mt-3 text-sm leading-6 text-stone-300">
                    Присутствие записывается только действующим участникам. Откройте карточку клуба, чтобы получить приглашение.
                  </p>
                </div>
              <% @event.status not in [:scheduled, :active] -> %>
                <div id="club-event-closed">
                  <h2 class="font-serif text-2xl text-stone-100">Протокол закрыт</h2>
                  <p class="mt-3 text-sm text-stone-400">
                    Это событие больше не принимает посещения.
                  </p>
                </div>
              <% @can_attend? -> %>
                <div>
                  <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">ваше действие</p>
                  <h2 class="mt-2 font-serif text-2xl text-violet-100">Внести себя в протокол</h2>
                  <p class="mt-3 text-sm leading-6 text-stone-300">
                    Награда за посещение сохранится на сервере и войдёт в клубную и академическую ведомость.
                  </p>
                  <button
                    id="club-event-attend"
                    type="button"
                    phx-click="attend"
                    class="mt-5 rounded-lg bg-violet-300 px-4 py-3 text-sm font-semibold text-stone-950 transition hover:bg-violet-200"
                  >
                    Присутствовать
                  </button>
                </div>
            <% end %>
          </section>

          <section
            :if={@event.kind == :duel_tournament && @attendance}
            id="club-event-duels"
            class="rounded-2xl border border-amber-400/25 bg-amber-950/15 p-6 shadow-lg"
          >
            <h2 class="font-serif text-2xl text-amber-100">Дружеские поединки</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Только отметившиеся участники могут отправлять и принимать приглашения. Поединки не используют ставку и не переносят добычу.
            </p>

            <div
              :if={@incoming_duel_challenges != []}
              id="club-event-incoming-duels"
              class="mt-4 space-y-3"
            >
              <article
                :for={challenge <- @incoming_duel_challenges}
                id={"club-event-duel-incoming-#{challenge["id"]}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 p-3 text-sm"
              >
                <span>Вас вызвали на дружеский поединок.</span>
                <div class="flex gap-2">
                  <button
                    id={"club-event-accept-duel-#{challenge["id"]}"}
                    type="button"
                    phx-click="accept_duel"
                    phx-value-challenge-id={challenge["id"]}
                    class="rounded bg-amber-300 px-3 py-2 font-semibold text-stone-950"
                  >
                    Принять
                  </button>
                  <button
                    id={"club-event-reject-duel-#{challenge["id"]}"}
                    type="button"
                    phx-click="reject_duel"
                    phx-value-challenge-id={challenge["id"]}
                    class="rounded border border-stone-600 px-3 py-2 text-stone-200"
                  >
                    Отказать
                  </button>
                </div>
              </article>
            </div>

            <div
              :if={@outgoing_duel_challenges != []}
              id="club-event-outgoing-duels"
              class="mt-4 space-y-2"
            >
              <p
                :for={challenge <- @outgoing_duel_challenges}
                class="rounded-lg bg-stone-950/55 px-3 py-2 text-sm text-stone-300"
              >
                Приглашение на поединок ожидает ответа.
              </p>
            </div>

            <div
              :if={@accepted_duel_challenges != []}
              id="club-event-active-duels"
              class="mt-4 space-y-2"
            >
              <.link
                :for={challenge <- @accepted_duel_challenges}
                id={"club-event-open-duel-#{challenge["id"]}"}
                navigate={~p"/combat/#{challenge["combat_id"]}"}
                class="inline-flex rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
              >
                Открыть текущий поединок
              </.link>
            </div>

            <div
              :if={@duel_opponents != []}
              id="club-event-duel-opponents"
              class="mt-5 grid gap-3 sm:grid-cols-2"
            >
              <article
                :for={opponent <- @duel_opponents}
                id={"club-event-duel-opponent-#{opponent.id}"}
                class="rounded-lg border border-amber-300/15 bg-stone-950/55 p-3"
              >
                <p class="font-medium text-stone-100">{opponent.name}</p>
                <button
                  id={"club-event-challenge-duel-#{opponent.id}"}
                  type="button"
                  phx-click="challenge_duel"
                  phx-value-opponent-id={opponent.id}
                  class="mt-3 rounded border border-amber-300/50 px-3 py-2 text-sm text-amber-100"
                >
                  Пригласить
                </button>
              </article>
            </div>
            <p
              :if={@duel_opponents == [] && @incoming_duel_challenges == []}
              id="club-event-duel-opponents-empty"
              class="mt-4 text-sm text-stone-400"
            >
              Другие отметившиеся дуэлянты пока не готовы к приглашению.
            </p>
          </section>
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

  defp event_description(_kind), do: "Клубное событие реалма."

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
