defmodule MMGOWeb.ClubsLive do
  @moduledoc """
  Scoped Academy-club registry, membership, invitations, and event controls.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGOWeb.LocationGate

  @club_type_options [
    {"Общий круг", "general_interest"},
    {"Дуэльный клуб", "dueling"},
    {"Исследовательское общество", "research"},
    {"Экспедиционный стол", "expedition_planning"}
  ]

  @event_kind_options [
    {"Общая встреча", "general_meeting"},
    {"Дуэльный турнир", "duel_tournament"},
    {"Исследовательская сессия", "research_session"},
    {"Экспедиционный разбор", "expedition_briefing"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    character = socket.assigns.current_scope.character

    case LocationGate.gate(socket, character, :city) do
      {:halt, socket} -> {:ok, socket}
      {:ok, socket} -> {:ok, socket |> assign(:page_title, "Клубы") |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    club_id = params["id"]

    case load_clubs(socket, club_id) do
      {:ok, socket} ->
        socket =
          if socket.assigns.live_action == :manage and not socket.assigns.state.can_manage? do
            push_navigate(socket, to: ~p"/academy/clubs/#{club_id}")
          else
            socket
          end

        {:noreply, socket}

      {:error, socket} ->
        {:noreply, push_navigate(socket, to: ~p"/academy/clubs")}
    end
  end

  @impl true
  def handle_event("create", %{"club_create" => attrs}, socket) do
    case Play.create_scoped_club(socket.assigns.character, attrs) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Клуб основан.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("accept", %{"invitation-id" => invitation_id}, socket) do
    case Play.accept_scoped_club_invitation(socket.assigns.character, invitation_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы вступили в клуб.")
         |> assign_state(state)
         |> push_navigate(to: ~p"/academy/clubs/#{state.selected_club.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("reject", %{"invitation-id" => invitation_id}, socket) do
    case Play.reject_scoped_club_invitation(socket.assigns.character, invitation_id) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Приглашение отклонено.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("invite", %{"club_invite" => %{"handle" => handle}}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.invite_to_scoped_club(socket.assigns.character, club_id, handle) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Приглашение отправлено.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("leave", _params, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.leave_scoped_club(socket.assigns.character, club_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы покинули клуб.")
         |> assign_state(state)
         |> push_navigate(to: ~p"/academy/clubs")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("schedule", %{"club_event" => attrs}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.schedule_scoped_club_event(socket.assigns.character, club_id, attrs) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Событие опубликовано.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("appoint_officer", %{"character-id" => character_id}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.appoint_scoped_club_officer(socket.assigns.character, club_id, character_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Офицер клуба назначен.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("revoke_officer", %{"character-id" => character_id}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.revoke_scoped_club_officer(socket.assigns.character, club_id, character_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Офицер вернулся к роли участника.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("nominate_president", %{"character-id" => character_id}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.nominate_scoped_club_president(socket.assigns.character, club_id, character_id) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Выборы президента открыты для действующего состава клуба.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event(
        "vote_president",
        %{"proposal-id" => proposal_id, "vote" => vote},
        socket
      ) do
    club_id = socket.assigns.state.selected_club.id

    case Play.vote_for_scoped_club_president(
           socket.assigns.character,
           club_id,
           proposal_id,
           vote
         ) do
      {:ok, state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Голос записан в клубный реестр.")
         |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("attend", %{"event-id" => event_id}, socket) do
    club_id = socket.assigns.state.selected_club.id

    case Play.attend_scoped_club_event(socket.assigns.character, club_id, event_id) do
      {:ok, state} ->
        {:noreply, socket |> put_flash(:info, "Посещение записано.") |> assign_state(state)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    club_id = socket.assigns.state.selected_club && socket.assigns.state.selected_club.id

    case load_clubs(socket, club_id) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def render(%{live_action: :show} = assigns), do: club_show(assigns)
  def render(%{live_action: :manage} = assigns), do: manage(assigns)
  def render(assigns), do: index(assigns)

  defp index(assigns) do
    member_ids = MapSet.new(Enum.map(assigns.state.member_clubs, & &1.id))

    assigns = assign(assigns, :member_ids, member_ids)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="clubs-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-5xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="clubs-back-academy"
              navigate={~p"/academy"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← Академия
            </.link>
            <button
              id="clubs-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200"
            >
              Обновить
            </button>
          </div>
          <header class="rounded-2xl border border-sky-400/25 bg-sky-950/20 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.24em] text-sky-200/75">клубное окно</p>
            <h1 class="mt-2 font-serif text-3xl text-sky-100">Круги Академии</h1>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Клубы, приглашения и события существуют в realm; вступление остаётся добровольным.
            </p>
          </header>

          <div
            :if={@error}
            id="clubs-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section
            :if={@state.pending_invitations != []}
            id="clubs-invitations"
            class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-emerald-100">Приглашения</h2>
            <article
              :for={invitation <- @state.pending_invitations}
              id={"club-invitation-#{invitation.id}"}
              class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 p-3 text-sm"
            >
              <span>{invitation.club.name} · зовёт {invitation.inviter_character.name}</span>
              <div class="flex gap-2">
                <button
                  id={"club-accept-#{invitation.id}"}
                  type="button"
                  phx-click="accept"
                  phx-value-invitation-id={invitation.id}
                  class="rounded bg-emerald-300 px-3 py-2 font-semibold text-stone-950"
                >
                  Принять
                </button>
                <button
                  id={"club-reject-#{invitation.id}"}
                  type="button"
                  phx-click="reject"
                  phx-value-invitation-id={invitation.id}
                  class="rounded border border-stone-600 px-3 py-2 text-stone-200"
                >
                  Отклонить
                </button>
              </div>
            </article>
          </section>

          <section
            id="clubs-create"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-6"
          >
            <h2 class="font-serif text-xl text-violet-100">Основать клуб</h2>
            <.form
              for={@create_form}
              id="club-create-form"
              phx-submit="create"
              class="mt-3 grid gap-3 md:grid-cols-2"
            >
              <.input
                field={@create_form[:name]}
                type="text"
                label="Название"
                placeholder="Круг рассвета"
              />
              <.input
                field={@create_form[:club_type]}
                type="select"
                label="Направление"
                options={@club_type_options}
              />
              <button
                id="club-create-submit"
                type="submit"
                class="rounded bg-violet-300 px-4 py-3 text-sm font-semibold text-stone-950"
              >
                Основать
              </button>
            </.form>
          </section>

          <section
            id="clubs-registry"
            class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 shadow-lg"
          >
            <h2 class="font-serif text-2xl text-stone-100">Клубы realm</h2>
            <div class="mt-4 grid gap-3 md:grid-cols-2">
              <.link
                :for={club <- @state.realm_clubs}
                id={"club-card-#{club.id}"}
                navigate={~p"/academy/clubs/#{club.id}"}
                class="rounded-xl border border-stone-700 bg-stone-950/55 p-4 transition hover:border-sky-300/50"
              >
                <p class="text-xs uppercase tracking-[0.18em] text-stone-500">
                  {club_type_label(club.club_type)}
                </p>
                <h3 class="mt-1 font-serif text-xl text-stone-100">{club.name}</h3>
                <p class="mt-3 text-sm text-stone-400">
                  {if MapSet.member?(@member_ids, club.id),
                    do: "Вы состоите в этом круге",
                    else: "Вступление по приглашению"}
                </p>
              </.link>
              <p :if={@state.realm_clubs == []} id="clubs-empty" class="text-sm text-stone-400">
                В этом realm ещё не основано ни одного клуба.
              </p>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp club_show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="club-detail-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-4xl space-y-5">
          <.link
            id="club-detail-back"
            navigate={~p"/academy/clubs"}
            class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
          >
            ← Все клубы
          </.link>
          <header class="rounded-2xl border border-sky-400/25 bg-sky-950/20 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-sky-200/75">
              {club_type_label(@state.selected_club.club_type)}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-sky-100">{@state.selected_club.name}</h1>
            <p class="mt-2 text-sm text-stone-300">
              Участников: {length(@state.selected_club.memberships)}
            </p>
          </header>

          <div
            :if={@error}
            id="club-detail-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>

          <section id="club-members" class="rounded-2xl border border-stone-700 bg-stone-900/80 p-5">
            <h2 class="font-serif text-xl text-stone-100">Состав</h2>
            <ul class="mt-3 space-y-2">
              <li
                :for={membership <- @state.selected_club.memberships}
                id={"club-member-#{membership.character_id}"}
                class="flex items-center justify-between rounded-lg bg-stone-950/55 px-3 py-2 text-sm"
              >
                <span>{membership.character.name}</span>
                <span class="text-stone-400">{club_role_label(membership.role)}</span>
              </li>
            </ul>
          </section>

          <section
            :if={@state.selected_membership}
            id="club-governance"
            class="rounded-2xl border border-sky-400/25 bg-sky-950/15 p-5"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="font-serif text-xl text-sky-100">Устройство клуба</h2>
              <p class="text-xs uppercase tracking-[0.16em] text-sky-200/65">выборы участников</p>
            </div>
            <p id="club-president" class="mt-2 text-sm text-stone-200">
              Президент: {club_member_name(@state.club_governance.president)}
            </p>
            <div id="club-officer-roster" class="mt-3">
              <p class="text-sm font-medium text-stone-200">Офицеры</p>
              <ul class="mt-2 space-y-1 text-sm text-stone-300">
                <li
                  :for={officer <- @state.club_governance.officers}
                  id={"club-officer-#{officer.character_id}"}
                >
                  {club_member_name(officer)}
                </li>
              </ul>
              <p :if={@state.club_governance.officers == []} class="mt-1 text-sm text-stone-400">
                Офицеры пока не назначены.
              </p>
            </div>

            <%= if @state.club_governance.open_election do %>
              <div id="club-open-election" class="mt-4 border-t border-sky-300/20 pt-4">
                <p id="club-election-candidate" class="text-sm text-stone-200">
                  Кандидат: {club_member_name(@state.club_governance.open_election.candidate)}
                </p>
                <p id="club-election-tally" class="mt-1 text-sm text-stone-300">
                  Голоса: {@state.club_governance.open_election.votes_cast}/ {@state.club_governance.open_election.voter_count}; поддержка {@state.club_governance.open_election.approve_votes}, отклонение {@state.club_governance.open_election.reject_votes}; для решения нужно {@state.club_governance.open_election.votes_needed}.
                </p>
                <div
                  :if={@state.club_governance.open_election.can_vote?}
                  class="mt-3 flex flex-wrap gap-2"
                >
                  <button
                    id="club-election-approve"
                    type="button"
                    phx-click="vote_president"
                    phx-value-proposal-id={@state.club_governance.open_election.id}
                    phx-value-vote="approve"
                    class="rounded border border-emerald-300/50 px-3 py-2 text-sm text-emerald-100"
                  >
                    Поддержать
                  </button>
                  <button
                    id="club-election-reject"
                    type="button"
                    phx-click="vote_president"
                    phx-value-proposal-id={@state.club_governance.open_election.id}
                    phx-value-vote="reject"
                    class="rounded border border-rose-300/50 px-3 py-2 text-sm text-rose-100"
                  >
                    Отклонить
                  </button>
                </div>
                <p
                  :if={not @state.club_governance.open_election.can_vote?}
                  id="club-election-vote-recorded"
                  class="mt-3 text-sm text-stone-400"
                >
                  Ваш голос уже учтён или вы не входили в состав клуба при открытии выборов.
                </p>
              </div>
            <% else %>
              <div id="club-president-nominations" class="mt-4 border-t border-sky-300/20 pt-4">
                <p class="text-sm text-stone-300">
                  Любой действующий участник может открыть выборы и предложить кандидата.
                </p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <button
                    :for={membership <- @state.club_governance.candidate_memberships}
                    :if={membership.character_id != club_member_id(@state.club_governance.president)}
                    id={"club-nominate-#{membership.character_id}"}
                    type="button"
                    phx-click="nominate_president"
                    phx-value-character-id={membership.character_id}
                    class="rounded border border-sky-300/50 px-3 py-2 text-sm text-sky-100"
                  >
                    Предложить {club_member_name(membership)}
                  </button>
                </div>
              </div>
            <% end %>
          </section>

          <section
            :if={@state.selected_club.club_type == :dueling}
            id="club-duel-ladder"
            class="rounded-2xl border border-amber-400/25 bg-amber-950/15 p-5"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="font-serif text-xl text-amber-100">Табель дуэльного круга</h2>
              <p class="text-xs uppercase tracking-[0.16em] text-amber-200/65">текущий игровой год</p>
            </div>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              В зачёт попадают только завершённые дружеские поединки между отметившимися участниками турнира.
            </p>
            <ol class="mt-4 space-y-2">
              <li
                :for={entry <- @state.duel_ladder}
                id={"club-duel-ladder-entry-#{entry.character_id}"}
                class="flex items-center justify-between gap-3 rounded-lg bg-stone-950/55 px-3 py-2 text-sm"
              >
                <span class="min-w-0 truncate">
                  <span class="mr-2 font-semibold text-amber-200">#{entry.rank}</span>{entry.character.name}
                </span>
                <span class="shrink-0 tabular-nums text-stone-300">
                  {entry.wins}–{entry.losses}–{entry.draws}
                </span>
              </li>
            </ol>
            <p
              :if={@state.duel_ladder == []}
              id="club-duel-ladder-empty"
              class="mt-3 text-sm text-stone-400"
            >
              В этом круге пока нет действующих участников.
            </p>
          </section>

          <section
            :if={@state.selected_club.club_type == :research && @state.selected_membership}
            id="club-research-contribution"
            class="rounded-2xl border border-cyan-400/25 bg-cyan-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-cyan-100">Общие заметки</h2>
            <p id="club-research-note-credits" class="mt-2 text-sm text-stone-200">
              Непогашенные заметки: {@state.research_contribution.credits}
            </p>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Каждая исследовательская сессия добавляет заметку. Когда другой участник этого круга завершит исследовательский проект, заметки дадут вам ретроактивную долю его XP и будут погашены.
            </p>
          </section>

          <section
            :if={@state.selected_club.club_type == :expedition_planning && @state.selected_membership}
            id="club-expedition-plan"
            class="rounded-2xl border border-lime-400/25 bg-lime-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-lime-100">Маршрутные разборы</h2>
            <p id="club-expedition-plan-credits" class="mt-2 text-sm text-stone-200">
              Готовых маршрутных заметок: {@state.expedition_plan.credits}
            </p>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Если у каждого участника отряда есть заметка из экспедиционного разбора, при старте общего похода они соберутся в маршрутный план. Он добавит 10% XP за первую победу в Подземелье и погасится.
            </p>
          </section>

          <section
            :if={@state.selected_club.club_type == :general_interest && @state.selected_membership}
            id="club-social-connections"
            class="rounded-2xl border border-rose-400/20 bg-rose-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-rose-100">Круг знакомых</h2>
            <p id="club-social-companions" class="mt-2 text-sm text-stone-200">
              Знакомых в этом круге: {@state.social_connections.companions}
            </p>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Совместные встречи сохраняют связи между участниками. Эти связи уже принадлежат вашему клубному членству и будут доступны будущим групповым механикам.
            </p>
          </section>

          <section
            :if={@state.selected_membership}
            id="club-member-actions"
            class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-5"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="font-serif text-xl text-emerald-100">Ваше участие</h2>
                <p class="mt-1 text-sm text-stone-300">
                  Роль: {club_role_label(@state.selected_membership.role)}
                </p>
              </div>
              <button
                id="club-leave"
                type="button"
                phx-click="leave"
                class="rounded border border-stone-500 px-3 py-2 text-sm text-stone-200"
              >
                Покинуть клуб
              </button>
            </div>
            <.link
              :if={@state.can_manage?}
              id="club-manage"
              navigate={~p"/academy/clubs/#{@state.selected_club.id}/manage"}
              class="mt-4 inline-flex rounded bg-sky-300 px-3 py-2 text-sm font-semibold text-stone-950"
            >
              Управление
            </.link>
          </section>

          <section
            id="club-events"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-violet-100">События</h2>
            <article
              :for={event <- @state.selected_events}
              id={"club-event-#{event.id}"}
              class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 p-3 text-sm"
            >
              <span>{event_kind_label(event.kind)} · {event_status_label(event.status)}</span>
              <button
                :if={@state.selected_membership && event.status in [:scheduled, :active]}
                id={"club-attend-#{event.id}"}
                type="button"
                phx-click="attend"
                phx-value-event-id={event.id}
                class="rounded border border-violet-300/50 px-3 py-2 text-violet-100"
              >
                Отметиться
              </button>
            </article>
            <p
              :if={@state.selected_events == []}
              id="club-events-empty"
              class="mt-3 text-sm text-stone-400"
            >
              Событий пока нет.
            </p>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp manage(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="club-manage-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link
            id="club-manage-back"
            navigate={~p"/academy/clubs/#{@state.selected_club.id}"}
            class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
          >
            ← К клубу
          </.link>
          <header class="rounded-2xl border border-sky-400/25 bg-sky-950/20 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-sky-200/75">
              {club_management_role_label(@state)}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-sky-100">
              Управление {@state.selected_club.name}
            </h1>
          </header>
          <div
            :if={@error}
            id="club-manage-error"
            class="rounded-xl border border-rose-500/45 bg-rose-950/30 px-4 py-3 text-sm text-rose-100"
          >
            {@error}
          </div>
          <section
            :if={@state.can_invite?}
            id="club-invite-controls"
            class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-emerald-100">Пригласить участника</h2>
            <.form
              for={@invite_form}
              id="club-invite-form"
              phx-submit="invite"
              class="mt-3 flex flex-wrap items-end gap-3"
            >
              <.input
                field={@invite_form[:handle]}
                type="text"
                label="Handle в этом realm"
                placeholder="wanderer"
              />
              <button
                id="club-send-invite"
                type="submit"
                class="mb-4 rounded bg-emerald-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Отправить
              </button>
            </.form>
          </section>
          <section
            :if={@state.can_schedule_events?}
            id="club-schedule-controls"
            class="rounded-2xl border border-violet-400/20 bg-violet-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-violet-100">Опубликовать событие</h2>
            <.form
              for={@event_form}
              id="club-event-form"
              phx-submit="schedule"
              class="mt-3 flex flex-wrap items-end gap-3"
            >
              <.input
                field={@event_form[:kind]}
                type="select"
                label="Вид"
                options={@event_kind_options}
              />
              <button
                id="club-schedule-event"
                type="submit"
                class="mb-4 rounded bg-violet-300 px-3 py-2 text-sm font-semibold text-stone-950"
              >
                Опубликовать
              </button>
            </.form>
          </section>
          <section
            :if={@state.can_manage_officers?}
            id="club-officer-controls"
            class="rounded-2xl border border-sky-400/25 bg-sky-950/15 p-5"
          >
            <h2 class="font-serif text-xl text-sky-100">Офицеры</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Офицеры могут приглашать участников и публиковать события, но не назначают друг друга.
            </p>
            <ul class="mt-4 space-y-2">
              <li
                :for={membership <- @state.selected_club.memberships}
                :if={membership.character_id != club_member_id(@state.club_governance.president)}
                id={"club-officer-control-#{membership.character_id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-stone-950/55 px-3 py-2 text-sm"
              >
                <span>{club_member_name(membership)}</span>
                <button
                  :if={membership.role == :member}
                  id={"club-appoint-officer-#{membership.character_id}"}
                  type="button"
                  phx-click="appoint_officer"
                  phx-value-character-id={membership.character_id}
                  class="rounded border border-sky-300/50 px-3 py-2 text-sky-100"
                >
                  Назначить офицером
                </button>
                <button
                  :if={membership.role == :officer}
                  id={"club-revoke-officer-#{membership.character_id}"}
                  type="button"
                  phx-click="revoke_officer"
                  phx-value-character-id={membership.character_id}
                  class="rounded border border-rose-300/50 px-3 py-2 text-rose-100"
                >
                  Снять полномочия
                </button>
              </li>
            </ul>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_clubs(socket, club_id) do
    case Play.clubs_state(socket.assigns.current_scope.character, club_id) do
      {:ok, state} -> {:ok, assign_state(socket, state)}
      {:error, _reason} -> {:error, socket}
    end
  end

  defp assign_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:state, state)
    |> assign(:error, nil)
    |> assign(
      :create_form,
      to_form(%{"name" => "", "club_type" => "general_interest"}, as: :club_create)
    )
    |> assign(:invite_form, to_form(%{"handle" => ""}, as: :club_invite))
    |> assign(
      :event_form,
      to_form(%{"kind" => default_event_kind(state.selected_club)}, as: :club_event)
    )
    |> assign(:club_type_options, @club_type_options)
    |> assign(:event_kind_options, event_kind_options_for(state.selected_club))
  end

  defp event_kind_options_for(%{club_type: :general_interest}),
    do: [{"Общая встреча", "general_meeting"}]

  defp event_kind_options_for(%{club_type: :dueling}),
    do: [{"Дуэльный турнир", "duel_tournament"}]

  defp event_kind_options_for(%{club_type: :research}),
    do: [{"Исследовательская сессия", "research_session"}]

  defp event_kind_options_for(%{club_type: :expedition_planning}),
    do: [{"Экспедиционный разбор", "expedition_briefing"}]

  defp event_kind_options_for(_club), do: @event_kind_options
  defp default_event_kind(club), do: event_kind_options_for(club) |> List.first() |> elem(1)

  defp club_type_label(:general_interest), do: "общий круг"
  defp club_type_label(:dueling), do: "дуэльный клуб"
  defp club_type_label(:research), do: "исследовательский клуб"
  defp club_type_label(:expedition_planning), do: "экспедиционный стол"
  defp club_type_label(_type), do: "клуб"
  defp club_role_label(:leader), do: "президент"
  defp club_role_label(:officer), do: "офицер"
  defp club_role_label(:member), do: "участник"
  defp club_role_label(_role), do: "участник"
  defp club_member_name(%{character: %{name: name}}) when is_binary(name), do: name
  defp club_member_name(_membership), do: "неизвестный участник"

  defp club_member_id(%{character_id: character_id}) when is_binary(character_id),
    do: character_id

  defp club_member_id(_membership), do: nil
  defp club_management_role_label(%{president?: true}), do: "президент клуба"
  defp club_management_role_label(_state), do: "офицер клуба"
  defp event_kind_label(:general_meeting), do: "общая встреча"
  defp event_kind_label(:duel_tournament), do: "дуэльный турнир"
  defp event_kind_label(:research_session), do: "исследовательская сессия"
  defp event_kind_label(:expedition_briefing), do: "экспедиционный разбор"
  defp event_kind_label(_kind), do: "событие"
  defp event_status_label(:scheduled), do: "назначено"
  defp event_status_label(:active), do: "идёт"
  defp event_status_label(:completed), do: "завершено"
  defp event_status_label(_status), do: "закрыто"
  defp error_message(:academy_location_unavailable), do: "Клубные дела доступны только в городе."
  defp error_message(:not_club_leader), do: "Это действие доступно только лидеру клуба."

  defp error_message(:not_club_manager),
    do: "Для этого действия нужны полномочия офицера или президента."

  defp error_message(:not_club_president), do: "Офицеров назначает только президент клуба."
  defp error_message(:club_invitee_not_found), do: "Подходящий участник в этом realm не найден."
  defp error_message(:club_invitation_not_found), do: "Приглашение больше недоступно."
  defp error_message(:club_membership_not_found), do: "Вы не состоите в этом клубе."
  defp error_message(:club_event_unavailable), do: "Это событие недоступно для посещения."

  defp error_message(:club_officer_candidate_unavailable),
    do: "Этого участника нельзя назначить офицером."

  defp error_message(:club_president_candidate_unavailable),
    do: "Кандидат в президенты недоступен."

  defp error_message(:club_president_election_unavailable), do: "Эти выборы уже нельзя провести."
  defp error_message(:invalid_club_vote), do: "Выберите поддержку или отклонение."
  defp error_message(_reason), do: "Клуб отклонил действие: состояние или права изменились."
end
