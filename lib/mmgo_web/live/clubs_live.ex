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
      <main id="clubs-screen" class="acd-screen acd-clubs-fair">
        <div class="acd-clubs-shell">
          <nav class="acd-clubs-nav" aria-label="Клубная ярмарка">
            <.link
              id="clubs-back-academy"
              navigate={~p"/academy"}
              class="acd-exit acd-clubs-back"
            >
              ← В холл
            </.link>
            <button
              id="clubs-refresh"
              type="button"
              phx-click="refresh"
              class="acd-clubs-bell"
            >
              <span aria-hidden="true">↻</span> Сверить доску
            </button>
          </nav>

          <header class="acd-fair-marquee">
            <div class="acd-fair-marquee__crest" aria-hidden="true">
              <span>А</span>
            </div>
            <div class="acd-fair-marquee__copy">
              <p class="acd-eyebrow">Внутренний двор · клубное окно</p>
              <h1>Ярмарка кругов</h1>
              <p>
                Гербы на стенах, уставы на бумаге. Вступление добровольно, а каждый круг принадлежит этому миру.
              </p>
            </div>
            <div class="acd-fair-marquee__tassel" aria-hidden="true"></div>
          </header>

          <div
            :if={@error}
            id="clubs-error"
            class="acd-clubs-error"
          >
            {@error}
          </div>

          <section
            :if={@state.pending_invitations != []}
            id="clubs-invitations"
            class="acd-invitation-rail"
          >
            <div class="acd-section__head">
              <h2 class="acd-section__title">Письма, оставленные для вас</h2>
              <span class="acd-section__aside">под печатью</span>
            </div>
            <div class="acd-invitation-rail__letters">
              <article
                :for={invitation <- @state.pending_invitations}
                id={"club-invitation-#{invitation.id}"}
                class="acd-invitation"
              >
                <span class="acd-invitation__pin" aria-hidden="true"></span>
                <p class="acd-invitation__overline">Приглашение в круг</p>
                <h3>{invitation.club.name}</h3>
                <p class="acd-invitation__from">
                  От имени клуба: {invitation.inviter_character.name}
                </p>
                <div class="acd-invitation__actions">
                  <button
                    id={"club-accept-#{invitation.id}"}
                    type="button"
                    phx-click="accept"
                    phx-value-invitation-id={invitation.id}
                    class="acd-btn acd-btn--primary"
                  >
                    Скрепить подписью
                  </button>
                  <button
                    id={"club-reject-#{invitation.id}"}
                    type="button"
                    phx-click="reject"
                    phx-value-invitation-id={invitation.id}
                    class="acd-btn acd-btn--danger"
                  >
                    Отклонить
                  </button>
                </div>
              </article>
            </div>
          </section>

          <section id="clubs-create" class="acd-charter-desk">
            <div class="acd-charter-desk__leather" aria-hidden="true"></div>
            <div class="acd-charter">
              <p class="acd-charter__folio">Форма Ⅳ · Канцелярия Академии</p>
              <span class="acd-charter__seal" aria-hidden="true">А</span>
              <h2>Устав нового круга</h2>
              <p class="acd-charter__intro">
                Назовите общество и выберите его ремесло. После подписи устав появится на общей доске.
              </p>
              <.form
                for={@create_form}
                id="club-create-form"
                phx-submit="create"
                class="acd-charter__form"
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
                  class="acd-charter__submit"
                >
                  Подписать устав
                </button>
              </.form>
            </div>
          </section>

          <section id="clubs-registry" class="acd-club-board">
            <div class="acd-club-board__header">
              <span class="acd-club-board__nail" aria-hidden="true"></span>
              <div>
                <p>Клубный регистр мира</p>
                <h2>Объявления и гербы</h2>
              </div>
              <span class="acd-club-board__chalk">вступление по приглашению</span>
            </div>
            <div class="acd-club-board__grid">
              <.link
                :for={club <- @state.realm_clubs}
                id={"club-card-#{club.id}"}
                navigate={~p"/academy/clubs/#{club.id}"}
                class="acd-club-notice"
                data-club-type={club.club_type}
              >
                <span class="acd-club-notice__pin" aria-hidden="true"></span>
                <span class="acd-club-notice__crest" aria-hidden="true">
                  {club_type_sigil(club.club_type)}
                </span>
                <p class="acd-club-notice__type">
                  {club_type_label(club.club_type)}
                </p>
                <h3>{club.name}</h3>
                <span class="acd-club-notice__rule"></span>
                <p class="acd-club-notice__status">
                  {if MapSet.member?(@member_ids, club.id),
                    do: "Ваше имя уже в списке",
                    else: "Обратитесь за приглашением"}
                </p>
              </.link>
              <p :if={@state.realm_clubs == []} id="clubs-empty" class="acd-club-board__empty">
                В этом мире ещё не основано ни одного клуба.
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
      <main
        id="club-detail-screen"
        class="acd-screen acd-society-room"
        data-club-type={@state.selected_club.club_type}
      >
        <div class="acd-clubs-shell">
          <.link
            id="club-detail-back"
            navigate={~p"/academy/clubs"}
            class="acd-exit acd-clubs-back"
          >
            ← К ярмарке
          </.link>

          <header class="acd-society-banner">
            <span class="acd-society-banner__cord acd-society-banner__cord--left" aria-hidden="true">
            </span>
            <span class="acd-society-banner__cord acd-society-banner__cord--right" aria-hidden="true">
            </span>
            <div class="acd-society-banner__crest" aria-hidden="true">
              {club_type_sigil(@state.selected_club.club_type)}
            </div>
            <div>
              <p>{club_type_label(@state.selected_club.club_type)}</p>
              <h1>{@state.selected_club.name}</h1>
              <span>{length(@state.selected_club.memberships)} имён в клубной книге</span>
            </div>
          </header>

          <div
            :if={@error}
            id="club-detail-error"
            class="acd-clubs-error"
          >
            {@error}
          </div>

          <div class="acd-society-table">
            <div class="acd-society-table__lamp" aria-hidden="true"></div>
            <section id="club-members" class="acd-members-ledger">
              <div class="acd-ledger-heading">
                <div>
                  <p>Книга присутствия</p>
                  <h2>Состав круга</h2>
                </div>
                <span>{length(@state.selected_club.memberships)} записей</span>
              </div>
              <ul class="acd-members-ledger__rows">
                <li
                  :for={membership <- @state.selected_club.memberships}
                  id={"club-member-#{membership.character_id}"}
                  class="acd-members-ledger__row"
                >
                  <span class="acd-members-ledger__mark" aria-hidden="true">
                    {String.first(membership.character.name)}
                  </span>
                  <span class="acd-members-ledger__name">{membership.character.name}</span>
                  <span class="acd-members-ledger__role">{club_role_label(membership.role)}</span>
                </li>
              </ul>
            </section>

            <section
              :if={@state.selected_membership}
              id="club-governance"
              class="acd-minutes"
            >
              <div class="acd-minutes__masthead">
                <p>Протокол управления</p>
                <h2>Должности и выборы</h2>
                <span>решает действующий состав</span>
              </div>
              <p id="club-president" class="acd-minutes__president">
                <span>Президент</span>
                {club_member_name(@state.club_governance.president)}
              </p>
              <div id="club-officer-roster" class="acd-minutes__officers">
                <p>Офицеры клуба</p>
                <ul>
                  <li
                    :for={officer <- @state.club_governance.officers}
                    id={"club-officer-#{officer.character_id}"}
                  >
                    {club_member_name(officer)}
                  </li>
                </ul>
                <p :if={@state.club_governance.officers == []} class="acd-minutes__empty">
                  Офицеры пока не назначены.
                </p>
              </div>

              <%= if @state.club_governance.open_election do %>
                <div id="club-open-election" class="acd-ballot">
                  <span class="acd-ballot__stamp" aria-hidden="true">ГОЛОС</span>
                  <p id="club-election-candidate" class="acd-ballot__candidate">
                    <span>Кандидат</span>
                    {club_member_name(@state.club_governance.open_election.candidate)}
                  </p>
                  <p id="club-election-tally" class="acd-ballot__tally">
                    Голоса: {@state.club_governance.open_election.votes_cast}/ {@state.club_governance.open_election.voter_count}; поддержка {@state.club_governance.open_election.approve_votes}, отклонение {@state.club_governance.open_election.reject_votes}; для решения нужно {@state.club_governance.open_election.votes_needed}.
                  </p>
                  <div
                    :if={@state.club_governance.open_election.can_vote?}
                    class="acd-ballot__actions"
                  >
                    <button
                      id="club-election-approve"
                      type="button"
                      phx-click="vote_president"
                      phx-value-proposal-id={@state.club_governance.open_election.id}
                      phx-value-vote="approve"
                      class="acd-btn acd-btn--on"
                    >
                      Поддержать
                    </button>
                    <button
                      id="club-election-reject"
                      type="button"
                      phx-click="vote_president"
                      phx-value-proposal-id={@state.club_governance.open_election.id}
                      phx-value-vote="reject"
                      class="acd-btn acd-btn--danger"
                    >
                      Отклонить
                    </button>
                  </div>
                  <p
                    :if={not @state.club_governance.open_election.can_vote?}
                    id="club-election-vote-recorded"
                    class="acd-ballot__recorded"
                  >
                    Ваш голос уже учтён или вы не входили в состав клуба при открытии выборов.
                  </p>
                </div>
              <% else %>
                <div id="club-president-nominations" class="acd-nominations">
                  <p class="acd-nominations__note">
                    Любой действующий участник может открыть выборы и предложить кандидата.
                  </p>
                  <div class="acd-nominations__names">
                    <button
                      :for={membership <- @state.club_governance.candidate_memberships}
                      :if={
                        membership.character_id != club_member_id(@state.club_governance.president)
                      }
                      id={"club-nominate-#{membership.character_id}"}
                      type="button"
                      phx-click="nominate_president"
                      phx-value-character-id={membership.character_id}
                      class="acd-nominations__name"
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
              class="acd-club-sheet acd-club-sheet--ladder"
            >
              <div class="acd-club-sheet__heading">
                <div>
                  <p>Текущий игровой год</p>
                  <h2>Табель дуэльного круга</h2>
                </div>
                <span aria-hidden="true">⚔</span>
              </div>
              <p class="acd-club-sheet__intro">
                В зачёт попадают только завершённые дружеские поединки между отметившимися участниками турнира.
              </p>
              <ol class="acd-duel-ledger">
                <li
                  :for={entry <- @state.duel_ladder}
                  id={"club-duel-ladder-entry-#{entry.character_id}"}
                  class="acd-duel-ledger__row"
                >
                  <span>
                    <strong>#{entry.rank}</strong>
                    {entry.character.name}
                  </span>
                  <span class="acd-duel-ledger__score">
                    {entry.wins}–{entry.losses}–{entry.draws}
                  </span>
                </li>
              </ol>
              <p
                :if={@state.duel_ladder == []}
                id="club-duel-ladder-empty"
                class="acd-club-sheet__empty"
              >
                В этом круге пока нет действующих участников.
              </p>
            </section>

            <section
              :if={@state.selected_club.club_type == :research && @state.selected_membership}
              id="club-research-contribution"
              class="acd-club-sheet acd-club-sheet--research"
            >
              <div class="acd-club-sheet__heading">
                <h2>Общие заметки</h2>
                <span aria-hidden="true">✎</span>
              </div>
              <p id="club-research-note-credits" class="acd-club-sheet__credit">
                Непогашенные заметки: {@state.research_contribution.credits}
              </p>
              <p class="acd-club-sheet__copy">
                Каждая исследовательская сессия добавляет заметку. Когда другой участник этого круга завершит исследовательский проект, заметки дадут вам долю его опыта и будут погашены.
              </p>
            </section>

            <section
              :if={
                @state.selected_club.club_type == :expedition_planning && @state.selected_membership
              }
              id="club-expedition-plan"
              class="acd-club-sheet acd-club-sheet--expedition"
            >
              <div class="acd-club-sheet__heading">
                <h2>Маршрутные разборы</h2>
                <span aria-hidden="true">◇</span>
              </div>
              <p id="club-expedition-plan-credits" class="acd-club-sheet__credit">
                Готовых маршрутных заметок: {@state.expedition_plan.credits}
              </p>
              <p class="acd-club-sheet__copy">
                Если у каждого участника отряда есть заметка из экспедиционного разбора, при старте общего похода они соберутся в маршрутный план. Он добавит 10% опыта за первую победу в Подземелье и погасится.
              </p>
            </section>

            <section
              :if={@state.selected_club.club_type == :general_interest && @state.selected_membership}
              id="club-social-connections"
              class="acd-club-sheet acd-club-sheet--social"
            >
              <div class="acd-club-sheet__heading">
                <h2>Круг знакомых</h2>
                <span aria-hidden="true">☙</span>
              </div>
              <p id="club-social-companions" class="acd-club-sheet__credit">
                Знакомых в этом круге: {@state.social_connections.companions}
              </p>
              <p class="acd-club-sheet__copy">
                Совместные встречи сохраняют связи между участниками. Эти связи уже принадлежат вашему клубному членству и будут доступны будущим групповым механикам.
              </p>
            </section>

            <section
              :if={@state.selected_membership}
              id="club-member-actions"
              class="acd-membership-card"
            >
              <span class="acd-membership-card__seal" aria-hidden="true">
                {club_type_sigil(@state.selected_club.club_type)}
              </span>
              <div class="acd-membership-card__copy">
                <p>Членский билет</p>
                <h2>Ваше участие</h2>
                <span>Роль: {club_role_label(@state.selected_membership.role)}</span>
              </div>
              <div class="acd-membership-card__actions">
                <.link
                  :if={@state.can_manage?}
                  id="club-manage"
                  navigate={~p"/academy/clubs/#{@state.selected_club.id}/manage"}
                  class="acd-btn acd-btn--primary"
                >
                  Открыть канцелярию
                </.link>
                <button
                  id="club-leave"
                  type="button"
                  phx-click="leave"
                  class="acd-btn acd-btn--danger"
                >
                  Покинуть клуб
                </button>
              </div>
            </section>

            <section id="club-events" class="acd-programme-board">
              <div>
                <p class="acd-programme-board__overline">На этой неделе</p>
                <h2>Программы событий</h2>
              </div>
              <div class="acd-programme-board__sheets">
                <article
                  :for={event <- @state.selected_events}
                  id={"club-event-#{event.id}"}
                  class="acd-event-slip"
                >
                  <span class="acd-event-slip__clip" aria-hidden="true"></span>
                  <p>{event_status_label(event.status)}</p>
                  <h3>{event_kind_label(event.kind)}</h3>
                  <button
                    :if={@state.selected_membership && event.status in [:scheduled, :active]}
                    id={"club-attend-#{event.id}"}
                    type="button"
                    phx-click="attend"
                    phx-value-event-id={event.id}
                    class="acd-event-slip__sign"
                  >
                    Вписать своё имя
                  </button>
                </article>
                <p
                  :if={@state.selected_events == []}
                  id="club-events-empty"
                  class="acd-programme-board__empty"
                >
                  Событий пока нет.
                </p>
              </div>
            </section>
          </div>
          <footer class="acd-society-room__footer" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
          </footer>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp manage(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="club-manage-screen" class="acd-screen acd-registry-room">
        <div class="acd-clubs-shell">
          <.link
            id="club-manage-back"
            navigate={~p"/academy/clubs/#{@state.selected_club.id}"}
            class="acd-exit acd-clubs-back"
          >
            ← В комнату клуба
          </.link>

          <header class="acd-registry-room__header">
            <span class="acd-registry-room__key" aria-hidden="true"></span>
            <p>{club_management_role_label(@state)}</p>
            <h1>Клубная канцелярия</h1>
            <span>{@state.selected_club.name}</span>
          </header>

          <div
            :if={@error}
            id="club-manage-error"
            class="acd-clubs-error"
          >
            {@error}
          </div>

          <div class="acd-registry-desk">
            <span class="acd-registry-desk__ink" aria-hidden="true"></span>
            <div class="acd-registry-book">
              <section
                :if={@state.can_invite?}
                id="club-invite-controls"
                class="acd-registry-page acd-registry-page--left"
              >
                <p class="acd-registry-page__folio">Регистр I</p>
                <h2>Пригласительное письмо</h2>
                <p class="acd-registry-page__intro">
                  Найдите жителя мира по имени учётной записи и оставьте письмо под клубной печатью.
                </p>
                <.form
                  for={@invite_form}
                  id="club-invite-form"
                  phx-submit="invite"
                  class="acd-registry-form"
                >
                  <.input
                    field={@invite_form[:handle]}
                    type="text"
                    label="Имя учётной записи в этом мире"
                    placeholder="strannik"
                  />
                  <button id="club-send-invite" type="submit" class="acd-registry-form__seal">
                    Запечатать письмо
                  </button>
                </.form>
              </section>

              <section
                :if={@state.can_schedule_events?}
                id="club-schedule-controls"
                class="acd-registry-page acd-registry-page--right"
              >
                <p class="acd-registry-page__folio">Регистр II</p>
                <h2>Программа события</h2>
                <p class="acd-registry-page__intro">
                  Выберите подходящую клубу встречу. Афиша появится в общей программе.
                </p>
                <.form
                  for={@event_form}
                  id="club-event-form"
                  phx-submit="schedule"
                  class="acd-registry-form"
                >
                  <.input
                    field={@event_form[:kind]}
                    type="select"
                    label="Вид события"
                    options={@event_kind_options}
                  />
                  <button id="club-schedule-event" type="submit" class="acd-registry-form__seal">
                    Внести в афишу
                  </button>
                </.form>
              </section>
            </div>

            <section
              :if={@state.can_manage_officers?}
              id="club-officer-controls"
              class="acd-officer-register"
            >
              <div class="acd-officer-register__heading">
                <p>Список доверенных лиц</p>
                <h2>Офицеры</h2>
                <span>
                  Могут приглашать участников и публиковать события, но не назначают друг друга.
                </span>
              </div>
              <ul class="acd-officer-register__rows">
                <li
                  :for={membership <- @state.selected_club.memberships}
                  :if={membership.character_id != club_member_id(@state.club_governance.president)}
                  id={"club-officer-control-#{membership.character_id}"}
                  class="acd-officer-register__row"
                >
                  <span>
                    <i aria-hidden="true">{String.first(club_member_name(membership))}</i>
                    {club_member_name(membership)}
                  </span>
                  <button
                    :if={membership.role == :member}
                    id={"club-appoint-officer-#{membership.character_id}"}
                    type="button"
                    phx-click="appoint_officer"
                    phx-value-character-id={membership.character_id}
                    class="acd-officer-register__action"
                  >
                    Выдать полномочия
                  </button>
                  <button
                    :if={membership.role == :officer}
                    id={"club-revoke-officer-#{membership.character_id}"}
                    type="button"
                    phx-click="revoke_officer"
                    phx-value-character-id={membership.character_id}
                    class="acd-officer-register__action acd-officer-register__action--revoke"
                  >
                    Снять полномочия
                  </button>
                </li>
              </ul>
            </section>
            <span class="acd-registry-desk__quill" aria-hidden="true"></span>
          </div>
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

  defp club_type_sigil(:general_interest), do: "☙"
  defp club_type_sigil(:dueling), do: "⚔"
  defp club_type_sigil(:research), do: "✎"
  defp club_type_sigil(:expedition_planning), do: "◇"
  defp club_type_sigil(_type), do: "◈"

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

  defp error_message(:club_invitee_not_found),
    do: "Подходящий участник в этом мире не найден."

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
