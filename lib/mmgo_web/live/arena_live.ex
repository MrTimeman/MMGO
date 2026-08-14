defmodule MMGOWeb.ArenaLive do
  @moduledoc """
  Combat-first Arena hub, ranked queue, friendly rooms, and rankings.

  All room and queue mutations cross the `MMGO.Arena` transaction boundary;
  the LiveView never trusts a client-provided profile, participant, team slot,
  event effect, or combat identifier.
  """

  use MMGOWeb, :live_view

  alias MMGO.Arena
  alias MMGO.Arena.{History, Ladder, Match, Profile, Quests, RoomRules, Titles}
  alias MMGO.Combat.ArenaEvents

  @room_refresh_interval 2_000

  @school_labels %{
    fire: "Огонь",
    water: "Вода",
    earth: "Земля",
    air: "Воздух",
    life: "Жизнь",
    death: "Смерть",
    chaos: "Хаос",
    order: "Порядок"
  }

  @impl true
  def mount(_params, _session, socket) do
    profile = Arena.get_profile_by_character(socket.assigns.current_scope.character.id)

    if profile do
      if connected?(socket) do
        Arena.subscribe_profile(profile.id)
        Arena.subscribe_queue(profile.season)
      end

      {:ok,
       socket
       |> assign(:profile, profile)
       |> assign(:current_match, nil)
       |> assign(:room, nil)
       |> assign(:arena_error, nil)
       |> assign(:selected_event_codes, ArenaEvents.event_codes())
       |> assign(:room_form, room_form())
       |> stream(:arena_events, ArenaEvents.catalog(), dom_id: &"arena-event-#{&1["code"]}")
       |> stream(:open_rooms, [])
       |> stream(:rankings, [])
       |> stream(:team_a, [])
       |> stream(:team_b, [])}
    else
      {:ok,
       socket
       |> put_flash(:error, "Профиль Арены не найден.")
       |> push_navigate(to: ~p"/mode")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :arena_error, nil)

    case socket.assigns.live_action do
      :home -> {:noreply, load_home(socket)}
      :queue -> {:noreply, load_queue(socket)}
      :profiles -> {:noreply, load_profiles(socket)}
      :seats -> {:noreply, load_seats(socket)}
      :result -> {:noreply, load_result(socket, params["match_id"])}
      :history -> {:noreply, load_history(socket)}
      :replay -> {:noreply, load_replay(socket, params["combat_id"])}
      :new_room -> {:noreply, load_new_room(socket)}
      :room -> {:noreply, load_room(socket, params["code"])}
      :rankings -> {:noreply, load_rankings(socket)}
    end
  end

  @impl true
  def handle_event("join_ranked", _params, socket) do
    case Arena.queue_ranked(socket.assigns.profile) do
      {:ok, %Match{status: :active, combat_id: combat_id}} when is_binary(combat_id) ->
        {:noreply, push_navigate(socket, to: ~p"/arena/combat/#{combat_id}")}

      {:ok, %Match{} = match} ->
        {:noreply,
         socket
         |> assign(:current_match, match)
         |> assign(:arena_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("start_training", _params, socket) do
    case Arena.start_training(socket.assigns.profile) do
      {:ok, %Match{combat_id: combat_id}} when is_binary(combat_id) ->
        {:noreply, push_navigate(socket, to: ~p"/arena/combat/#{combat_id}")}

      {:ok, _match} ->
        {:noreply, assign(socket, :arena_error, "Зал не открылся. Попробуйте ещё раз.")}

      {:error, reason} ->
        {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("cancel_ranked", _params, socket) do
    case Arena.cancel_ranked_queue(socket.assigns.profile) do
      {:ok, _match} ->
        {:noreply,
         socket
         |> assign(:current_match, nil)
         |> put_flash(:info, "Поиск соперника остановлен.")}

      {:error, reason} ->
        {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("validate_room", %{"arena_room" => params}, socket) do
    selected_codes = normalize_event_codes(params["event_codes"])
    params = Map.put(params, "event_codes", selected_codes)

    {:noreply,
     socket
     |> assign(:selected_event_codes, selected_codes)
     |> assign(:room_form, to_form(params, as: :arena_room))}
  end

  def handle_event("create_room", %{"arena_room" => params}, socket) do
    params =
      params
      |> Map.put("event_codes", normalize_event_codes(params["event_codes"]))
      |> Map.put(
        "settings",
        params
        |> Map.take(["room_name", "description", "turn_seconds"])
        |> Map.put("rules", Map.take(params, ["grimoire", "mana", "rank", "rank_cap"]))
      )

    case Arena.create_custom_room(socket.assigns.profile, params) do
      {:ok, %Match{} = room} ->
        {:noreply, push_navigate(socket, to: ~p"/arena/rooms/#{room.code}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:room_form, to_form(params, as: :arena_room))
         |> assign(:arena_error, arena_error(reason))}
    end
  end

  def handle_event("create_room", _params, socket) do
    {:noreply, assign(socket, :arena_error, "Проверьте настройки комнаты.")}
  end

  def handle_event("replay_step", %{"to" => to}, socket) do
    turn =
      to
      |> to_string()
      |> Integer.parse()
      |> case do
        {parsed, ""} -> parsed
        _unparsable -> 1
      end
      |> max(1)
      |> min(length(socket.assigns.replay.turns))

    {:noreply, assign(socket, :replay_turn, turn)}
  end

  def handle_event("join_room", %{"code" => code} = params, socket) do
    team = Map.get(params, "team")

    case Arena.join_custom_room(code, socket.assigns.profile, %{"team" => team}) do
      {:ok, %Match{} = room} ->
        {:noreply, socket |> assign(:room, room) |> assign_room_members(room)}

      {:error, reason} ->
        {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("switch_team", %{"team" => team}, socket) do
    with %Match{} = room <- socket.assigns.room,
         {:ok, %Match{} = room} <- Arena.switch_team(room, socket.assigns.profile, team) do
      {:noreply, socket |> assign(:room, room) |> assign_room_members(room)}
    else
      nil -> {:noreply, assign(socket, :arena_error, "Комната больше не открыта.")}
      {:error, reason} -> {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("toggle_ready", _params, socket) do
    with %Match{} = room <- socket.assigns.room,
         {:ok, %Match{} = room} <- Arena.toggle_ready(room, socket.assigns.profile) do
      {:noreply, socket |> assign(:room, room) |> assign_room_members(room)}
    else
      nil -> {:noreply, assign(socket, :arena_error, "Комната больше не открыта.")}
      {:error, reason} -> {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("leave_room", _params, socket) do
    with %Match{} = room <- socket.assigns.room,
         {:ok, %Match{status: status}} <-
           Arena.leave_custom_room(room, socket.assigns.profile) do
      message =
        if status == :cancelled,
          do: "Комната закрыта.",
          else: "Вы покинули комнату."

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> push_navigate(to: ~p"/arena")}
    else
      nil -> {:noreply, push_navigate(socket, to: ~p"/arena")}
      {:error, reason} -> {:noreply, assign(socket, :arena_error, arena_error(reason))}
    end
  end

  def handle_event("start_room", _params, socket) do
    with %Match{} = room <- socket.assigns.room,
         {:ok, %Match{} = started} <- Arena.start_custom_room(room, socket.assigns.profile),
         combat_id when is_binary(combat_id) <- started.combat_id do
      {:noreply, push_navigate(socket, to: ~p"/arena/combat/#{combat_id}")}
    else
      nil -> {:noreply, assign(socket, :arena_error, "Комната больше не открыта.")}
      {:error, reason} -> {:noreply, assign(socket, :arena_error, arena_error(reason))}
      _missing_combat -> {:noreply, assign(socket, :arena_error, "Бой ещё не готов.")}
    end
  end

  @impl true
  def handle_info({_event, %Match{} = match}, socket) do
    cond do
      match.status == :active and is_binary(match.combat_id) and
          member?(match, socket.assigns.profile) ->
        {:noreply, push_navigate(socket, to: ~p"/arena/combat/#{match.combat_id}")}

      ((socket.assigns.live_action == :room and socket.assigns.room) &&
         socket.assigns.room.id == match.id) and match.status != :forming ->
        {:noreply,
         socket
         |> put_flash(:info, "Комната закрыта.")
         |> push_navigate(to: ~p"/arena")}

      (socket.assigns.live_action == :room and socket.assigns.room) &&
          socket.assigns.room.id == match.id ->
        room = Arena.get_match!(match.id)
        {:noreply, socket |> assign(:room, room) |> assign_room_members(room)}

      socket.assigns.live_action == :queue ->
        {:noreply,
         assign(socket, :current_match, Arena.active_match_for_profile(socket.assigns.profile))}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info(:refresh_arena_room, socket) do
    case socket.assigns.room do
      %Match{id: id} ->
        room = Arena.get_match!(id)

        cond do
          room.status == :active and is_binary(room.combat_id) ->
            {:noreply, push_navigate(socket, to: ~p"/arena/combat/#{room.combat_id}")}

          room.status != :forming ->
            {:noreply,
             socket
             |> put_flash(:info, "Комната закрыта.")
             |> push_navigate(to: ~p"/arena")}

          true ->
            {:noreply,
             socket
             |> assign(:room, room)
             |> assign_room_members(room)
             |> schedule_room_refresh()}
        end

      _none ->
        {:noreply, socket}
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Комната закрыта.")
       |> push_navigate(to: ~p"/arena")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="arena-screen" class="arena-shell">
        <header class="arena-nav">
          <.link id="arena-brand" navigate={~p"/arena"} class="arena-nav__brand">
            <span class="arena-nav__mark">A</span>
            <span><small>MMGO</small><strong>Арена</strong></span>
          </.link>

          <%!-- The only navigation in the Arena. On a phone this becomes the
                bottom bar, so nothing else may repeat its destinations, and the
                section you are already in reads as a place rather than as a
                button that does nothing. --%>
          <nav aria-label="Разделы Арены">
            <.link
              :for={{id, path, label, sections} <- arena_sections()}
              id={id}
              navigate={path}
              aria-current={arena_section_current(@live_action, sections)}
              class={arena_section_current(@live_action, sections) && "is-current"}
            >
              {label}
            </.link>
          </nav>

          <div class="arena-nav__profile">
            <span>{rank_label(@profile)}</span>
            <strong>{@profile.rating}</strong>
            <.link id="arena-switch-mode" navigate={~p"/mode"} title="Сменить режим">
              <.icon name="hero-arrows-right-left" />
            </.link>
          </div>
        </header>

        <p :if={@arena_error} id="arena-error" class="arena-alert" role="alert">
          <.icon name="hero-exclamation-triangle" /> {@arena_error}
        </p>

        <%= case @live_action do %>
          <% :home -> %>
            <.home
              profile={@profile}
              profile_count={@profile_count}
              quests={@quests}
              current_match={@current_match}
              streams={@streams}
            />
          <% :queue -> %>
            <.queue profile={@profile} current_match={@current_match} queue={@queue_snapshot} />
          <% :new_room -> %>
            <.new_room
              form={@room_form}
              selected_event_codes={@selected_event_codes}
              streams={@streams}
            />
          <% :room -> %>
            <.room room={@room} profile={@profile} streams={@streams} />
          <% :rankings -> %>
            <.rankings profile={@profile} streams={@streams} />
          <% :profiles -> %>
            <.profiles profile={@profile} profiles={@profiles} />
          <% :result -> %>
            <.result profile={@profile} settlement={@settlement} />
          <% :history -> %>
            <.history history={@history} />
          <% :replay -> %>
            <.replay replay={@replay} turn={@replay_turn} />
          <% :seats -> %>
            <.seats
              profile={@profile}
              champion={@champion}
              deputy={@deputy}
              champion_challenge={@champion_challenge}
              deputy_challenge={@deputy_challenge}
              own_seat={@own_seat}
            />
        <% end %>
      </main>
    </Layouts.app>
    """
  end

  attr :profile, Profile, required: true
  attr :profile_count, :integer, required: true
  attr :quests, :list, required: true
  attr :current_match, :any, required: true
  attr :streams, :map, required: true

  defp home(assigns) do
    ~H"""
    <div id="arena-home" class="arena-page">
      <%!--
      The Arena opens on the thing players came to do. Standing, then the queue
      button, then everything else: at 375px the primary action must be reachable
      without a scroll. See the Arena exception in docs/UI_DESIGN_BRIEF.md.
      --%>
      <section :if={@current_match} id="arena-active-match" class="arena-active-match">
        <div>
          <p>Незавершённый бой</p>
          <h2>{active_match_title(@current_match)}</h2>
        </div>
        <.link
          id="arena-resume-match"
          navigate={active_match_path(@current_match)}
          class="arena-button arena-button--gold"
        >
          Продолжить <.icon name="hero-arrow-right" />
        </.link>
      </section>

      <section id="arena-launch" class="arena-launch">
        <div id="arena-profile-card" class="arena-launch__standing">
          <span class="arena-launch__seal">{rank_glyph(@profile)}</span>
          <div class="arena-launch__figures">
            <p>{rank_label(@profile)} · сезон {@profile.season}</p>
            <strong>{@profile.rating}</strong>
            <small>
              {@profile.wins}–{@profile.losses} · опыт {@profile.season_xp}
            </small>
            <%!-- While placements last the ladder moves twice as hard: say so. --%>
            <small :if={@profile.placements_remaining > 0} id="arena-placements">
              Калибровка · осталось боёв: {@profile.placements_remaining}
            </small>
          </div>
          <.link
            :if={@profile_count > 1}
            id="arena-profile-switch"
            navigate={~p"/arena/profiles"}
            class="arena-launch__switch"
            title="Сменить профиль Арены"
          >
            <.icon name="hero-arrows-right-left" />
          </.link>
        </div>

        <.link id="arena-ranked-queue" navigate={~p"/arena/queue"} class="arena-launch__primary">
          Найти соперника <.icon name="hero-bolt" />
        </.link>

        <%!-- Only what the bar does not already reach. The grimoire lives in the
              bar, so a second button for it here was two doors to one room. --%>
        <%!-- The Arena is unplayable alone: a queue needs someone else in it
              and a room needs someone to join. This needs neither. --%>
        <button
          id="arena-training"
          type="button"
          phx-click="start_training"
          class="arena-launch__secondary"
        >
          Тренировочный зал
        </button>

        <nav class="arena-launch__shortcuts" aria-label="Быстрые действия">
          <.link id="arena-create-room" navigate={~p"/arena/rooms/new"}>Своя комната</.link>
          <.link id="arena-launch-seats" navigate={~p"/arena/seats"}>Титулы</.link>
          <.link id="arena-launch-history" navigate={~p"/arena/history"}>История</.link>
        </nav>

        <div class="arena-school-row" aria-label="Выбранные школы">
          <span :for={school <- @profile.schools}>{school_label(school)}</span>
        </div>
      </section>

      <%!--
      Standing reasons to come back, right under the button that takes you back
      in. Nothing here is claimed: a reward that waits behind a button is a chore.
      --%>
      <%!--
      Quests are a reason to come back, not the point of the screen. One line
      each, folded away by default: the fight button must stay the tallest thing
      on the page.
      --%>
      <details id="arena-quests" class="arena-quests">
        <summary>
          <span class="arena-quests__label">Задачи</span>
          <span id="arena-quests-progress" class="arena-quests__tally">
            {quests_done(@quests)}/{length(@quests)}
          </span>
          <span :if={@profile.streak_days > 0} id="arena-streak" class="arena-quests__streak">
            {@profile.streak_days} дн. подряд
          </span>
        </summary>

        <ul class="arena-quest-list">
          <li
            :for={quest <- @quests}
            id={"arena-quest-#{quest.code}"}
            class={["arena-quest", quest.completed? && "is-done"]}
          >
            <span class="arena-quest__name">{quest.name}</span>
            <span class="arena-quest__meter" aria-hidden="true">
              <span style={"width: #{quest_percent(quest)}%"} />
            </span>
            <span class="arena-quest__count">
              {min(quest.progress, quest.goal)}/{quest.goal} · +{quest.reward_xp}
            </span>
          </li>
        </ul>
      </details>

      <section id="arena-open-rooms-section" class="arena-section">
        <div class="arena-section__head">
          <div>
            <p>Открытые комнаты</p>
            <h2>Войти в дружеский бой</h2>
          </div>
        </div>
        <div id="arena-open-rooms" phx-update="stream" class="arena-room-list">
          <p id="arena-open-rooms-empty" class="arena-empty hidden only:block">
            Пока никто не собирает команду.
          </p>
          <article :for={{id, room} <- @streams.open_rooms} id={id} class="arena-room-row">
            <div>
              <strong>{room_name(room)}</strong><span>{room.team_size}v{room.team_size}</span>
              <em :if={room_rules_summary(room)} class="arena-room-row__rules">
                {room_rules_summary(room)}
              </em>
            </div>
            <span>{length(room.members)} / {room.team_size * 2} бойцов</span>
            <.link id={"join-open-room-#{room.id}"} navigate={~p"/arena/rooms/#{room.code}"}>
              Войти <.icon name="hero-arrow-right" />
            </.link>
          </article>
        </div>
      </section>

      <%!--
      What was here — an eight-card catalogue of arena events, a block
      advertising summons, and a paragraph explaining what the Arena is — told
      the player things rather than letting them do anything. A player who has
      arrived does not need to be sold the room they are standing in.
      --%>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :profiles, :list, required: true

  defp profiles(assigns) do
    ~H"""
    <div id="arena-profiles" class="arena-page arena-page--narrow">
      <.link id="arena-profiles-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <section class="arena-section">
        <div class="arena-section__head">
          <div>
            <p>Профили Арены</p>
            <h2>Кем вы выходите на бой</h2>
          </div>
        </div>
        <p class="arena-room-form__hint">
          Каждый профиль — свои три школы, свой гримуар и своё место в рейтинге.
          Титул при этом один на игрока: два ваших профиля не займут оба места.
        </p>

        <div class="arena-room-list">
          <article
            :for={profile <- @profiles}
            id={"arena-profile-#{profile.id}"}
            class={["arena-room-row", profile.id == @profile.id && "is-current"]}
          >
            <div>
              <strong>{profile.character.name}</strong>
              <span>{rank_label(profile)} · {profile.rating}</span>
              <em class="arena-room-row__rules">
                {Enum.map_join(profile.schools, " · ", &school_label/1)}
              </em>
            </div>
            <span>{profile.wins}–{profile.losses}</span>
            <span :if={profile.id == @profile.id} class="arena-profile-current">Вы играете им</span>
            <.form
              :if={profile.id != @profile.id}
              for={%{}}
              action={~p"/arena/profiles/switch"}
              method="post"
              id={"arena-switch-profile-#{profile.id}"}
            >
              <input type="hidden" name="profile_id" value={profile.id} />
              <button type="submit">Играть им <.icon name="hero-arrow-right" /></button>
            </.form>
          </article>
        </div>
      </section>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :settlement, :map, required: true

  defp result(assigns) do
    ~H"""
    <div id="arena-result" class={["arena-page", "arena-page--narrow"]}>
      <section class={["arena-result", "arena-result--#{@settlement.outcome}"]}>
        <p class="arena-kicker">{match_mode_label(@settlement.mode)} бой</p>
        <h1>{outcome_label(@settlement.outcome)}</h1>
        <p class="arena-result__against">{opponents_label(@settlement.opponents)}</p>

        <%!-- The rank-up moment: the one thing on this screen that gets to glow. --%>
        <div
          :if={@settlement.promoted? or @settlement.demoted?}
          id="arena-result-rank-change"
          class={[
            "arena-result__rank",
            @settlement.promoted? && "arena-result__rank--up",
            @settlement.demoted? && "arena-result__rank--down"
          ]}
        >
          <span class="arena-result__rank-seal">{Ladder.glyph(@settlement.division_after)}</span>
          <div>
            <p>{if @settlement.promoted?, do: "Повышение", else: "Понижение"}</p>
            <strong>{Ladder.label(@settlement.division_after)}</strong>
            <small>было — {Ladder.label(@settlement.division_before)}</small>
          </div>
        </div>

        <dl class="arena-result__ledger">
          <div>
            <dt>Рейтинг</dt>
            <dd id="arena-result-rating">
              {@settlement.rating_before} → {@settlement.rating_after}
              <em>{rating_delta_label(@settlement.rating_delta)}</em>
            </dd>
          </div>
          <div>
            <dt>Опыт сезона</dt>
            <dd>+{@settlement.season_xp_gained || 0}</dd>
          </div>
          <div>
            <dt>Всего опыта</dt>
            <dd>{@profile.season_xp}</dd>
          </div>
        </dl>

        <%!-- Straight back into a fight: the queue is one tap from the result. --%>
        <button
          id="arena-result-requeue"
          type="button"
          phx-click="join_ranked"
          class="arena-launch__primary"
        >
          Ещё бой <.icon name="hero-bolt" />
        </button>

        <div class="arena-launch__shortcuts">
          <.link
            :if={@settlement.replayable?}
            id="arena-result-replay"
            navigate={~p"/arena/history/#{@settlement.combat_id}"}
          >
            Запись боя
          </.link>
          <.link id="arena-result-home" navigate={~p"/arena"}>На Арену</.link>
        </div>
      </section>
    </div>
    """
  end

  attr :history, :list, required: true

  defp history(assigns) do
    ~H"""
    <div id="arena-history" class="arena-page arena-page--narrow">
      <.link id="arena-history-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <section class="arena-section">
        <div class="arena-section__head">
          <div>
            <p>Прошедшие бои</p>
            <h2>Чем всё закончилось</h2>
          </div>
          <span>хранится {History.retention_days()} дней</span>
        </div>

        <p :if={@history == []} id="arena-history-empty" class="arena-empty">
          Вы ещё не провели ни одного боя.
        </p>

        <div class="arena-room-list">
          <article
            :for={entry <- @history}
            id={"arena-history-#{entry.match_id}"}
            class={["arena-room-row", "arena-history-row--#{entry.outcome}"]}
          >
            <div>
              <strong>{outcome_label(entry.outcome)}</strong>
              <span>{opponents_label(entry.opponents)}</span>
              <em class="arena-room-row__rules">{match_mode_label(entry.mode)}</em>
            </div>
            <span class="arena-history-delta">{rating_delta_label(entry.rating_delta)}</span>
            <.link
              :if={entry.replayable?}
              id={"arena-replay-#{entry.match_id}"}
              navigate={~p"/arena/history/#{entry.combat_id}"}
            >
              Запись <.icon name="hero-arrow-right" />
            </.link>
          </article>
        </div>
      </section>
    </div>
    """
  end

  attr :replay, :map, required: true
  attr :turn, :integer, required: true

  defp replay(assigns) do
    ~H"""
    <div id="arena-replay" class="arena-page arena-page--narrow">
      <.link id="arena-replay-back" navigate={~p"/arena/history"} class="arena-back">
        <.icon name="hero-arrow-left" /> К истории
      </.link>

      <section class="arena-section">
        <div class="arena-section__head">
          <div>
            <p>Запись боя · зерно {@replay.seed}</p>
            <h2>Ход {@turn} из {length(@replay.turns)}</h2>
          </div>
        </div>

        <%= if current_turn(@replay, @turn) do %>
          <article id="arena-replay-turn" class="arena-replay-turn">
            <p class="arena-replay-turn__narration">
              {current_turn(@replay, @turn).narration || "Хроника этого хода не сохранилась."}
            </p>

            <ol class="arena-replay-events">
              <li :for={event <- current_turn(@replay, @turn).events} id={"replay-event-#{event.id}"}>
                <span>{event.sequence}</span>
                <strong>{replay_event_label(event.event_type)}</strong>
              </li>
            </ol>
          </article>
        <% end %>

        <div class="arena-replay-controls">
          <button
            id="arena-replay-prev"
            type="button"
            phx-click="replay_step"
            phx-value-to={@turn - 1}
            disabled={@turn <= 1}
          >
            <.icon name="hero-arrow-left" /> Назад
          </button>
          <button
            id="arena-replay-next"
            type="button"
            phx-click="replay_step"
            phx-value-to={@turn + 1}
            disabled={@turn >= length(@replay.turns)}
          >
            Вперёд <.icon name="hero-arrow-right" />
          </button>
        </div>
      </section>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :champion, :any, required: true
  attr :deputy, :any, required: true
  attr :champion_challenge, :any, required: true
  attr :deputy_challenge, :any, required: true
  attr :own_seat, :any, required: true

  defp seats(assigns) do
    ~H"""
    <div id="arena-seats" class="arena-page arena-page--narrow">
      <.link id="arena-seats-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <section class="arena-section">
        <div class="arena-section__head">
          <div>
            <p>Вершина лестницы</p>
            <h2>Чемпион и его наместник</h2>
          </div>
        </div>
        <p class="arena-room-form__hint">
          Наверху не разряд, а два места. Наместника вызывают первым: победа над ним
          открывает право вызвать чемпиона, и это право сгорает через {Titles.gauntlet_right_days()} дня.
          Вызов на титул нельзя отклонить — оставленный без ответа {Titles.unanswered_challenge_days()} дней,
          он засчитывается вызывающему.
        </p>

        <div class="arena-seat-grid">
          <article id="arena-seat-champion" class="arena-seat-card arena-seat-card--champion">
            <span class="arena-seat-card__seal">{Ladder.glyph(:champion)}</span>
            <p>Чемпион</p>
            <strong>{seat_holder_name(@champion)}</strong>
            <small>{seat_note(@champion, @champion_challenge)}</small>
          </article>

          <article id="arena-seat-deputy" class="arena-seat-card">
            <span class="arena-seat-card__seal">{Ladder.glyph(:archmage)}</span>
            <p>Наместник</p>
            <strong>{seat_holder_name(@deputy)}</strong>
            <small>{seat_note(@deputy, @deputy_challenge)}</small>
          </article>
        </div>

        <p :if={@own_seat} id="arena-own-seat" class="arena-alert">
          <.icon name="hero-sparkles" /> Вы держите место: {seat_label(@own_seat)}.
        </p>

        <p :if={is_nil(@own_seat)} id="arena-gauntlet-eligibility" class="arena-room-form__hint">
          <%= if Titles.eligible_to_challenge?(@profile) do %>
            Ваш разряд открывает путь к титулу: вызов начинается с наместника.
          <% else %>
            Путь к титулу открыт с разряда «{Ladder.label(Titles.eligible_division())}».
            Сейчас ваш — «{rank_label(@profile)}».
          <% end %>
        </p>
      </section>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :current_match, :any, required: true
  attr :queue, :map, required: true

  defp queue(assigns) do
    ~H"""
    <div id="arena-queue" class="arena-page arena-page--narrow">
      <.link id="arena-queue-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <section class="arena-queue-stage">
        <div class="arena-queue-stage__runes" aria-hidden="true"><span>ᛟ</span><span>ᚨ</span></div>
        <p>Ранговый поединок · сезон {@profile.season}</p>
        <h1>{rank_label(@profile)} · {@profile.rating}</h1>

        <%!--
        A silent queue looks broken. These are measured numbers, not comfort:
        who is waiting, who is already fighting, and how long the last pairings
        actually took.
        --%>
        <p id="arena-queue-population" class="arena-queue-population">
          Ждут: {@queue.waiting} · В бою: {@queue.fighting} · {wait_estimate_label(@queue)}
        </p>

        <%= if @current_match && @current_match.status == :queued do %>
          <div id="arena-searching" class="arena-searching">
            <span class="arena-searching__orb"><.icon name="hero-sparkles" /></span>
            <h2>Ищем равного соперника</h2>
            <p>Можно закрыть экран — очередь сохранена на сервере.</p>
            <button id="arena-cancel-queue" type="button" phx-click="cancel_ranked">
              Остановить поиск
            </button>
          </div>
        <% else %>
          <div id="arena-queue-ready" class="arena-queue-ready">
            <dl>
              <div>
                <dt>Формат</dt>
                <dd>1 на 1</dd>
              </div>
              <div>
                <dt>События</dt>
                <dd>Случайная колода</dd>
              </div>
              <div>
                <dt>Предметы</dt>
                <dd>Отключены</dd>
              </div>
              <div>
                <dt>Нагрузка</dt>
                <dd>Активный гримуар</dd>
              </div>
            </dl>
            <button
              id="arena-join-queue"
              type="button"
              phx-click="join_ranked"
              class="arena-button arena-button--gold"
            >
              Начать поиск <.icon name="hero-bolt" />
            </button>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :selected_event_codes, :list, required: true
  attr :streams, :map, required: true

  defp new_room(assigns) do
    ~H"""
    <div id="arena-new-room" class="arena-page arena-page--narrow">
      <.link id="arena-new-room-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <header class="arena-page-title">
        <p>Дружеский бой · без изменения рейтинга</p>
        <h1>Настройте комнату</h1>
        <span>Все исполняемые эффекты событий принадлежат серверу; вы выбираете только колоду.</span>
      </header>

      <.form
        for={@form}
        id="arena-room-form"
        phx-change="validate_room"
        phx-submit="create_room"
        class="arena-room-form"
      >
        <section class="arena-room-form__panel">
          <h2>I · Команды</h2>
          <div class="arena-form-grid">
            <.input
              field={@form[:room_name]}
              id="arena-room-name"
              type="text"
              label="Название комнаты"
              maxlength="60"
            />
            <.input
              field={@form[:team_size]}
              id="arena-team-size"
              type="select"
              label="Размер каждой команды"
              options={Enum.map(1..5, &{"#{&1}v#{&1}", &1})}
            />
            <.input
              field={@form[:turn_seconds]}
              id="arena-turn-seconds"
              type="select"
              label="Время на ход"
              options={[
                {"30 секунд · блиц", 30},
                {"45 секунд · быстро", 45},
                {"60 секунд · обычно", 60},
                {"90 секунд · вдумчиво", 90},
                {"120 секунд · ритуал", 120}
              ]}
            />
          </div>
          <.input
            field={@form[:description]}
            id="arena-room-description"
            type="textarea"
            label="Заметка для участников"
            maxlength="180"
          />
        </section>

        <section class="arena-room-form__panel">
          <h2>II · Особые правила</h2>
          <p class="arena-room-form__hint">
            Дружеская комната — единственное место, где ограничения Арены можно снять
            намеренно. В ранговых боях они действуют всегда.
          </p>
          <div class="arena-form-grid">
            <.input
              field={@form[:grimoire]}
              id="arena-rule-grimoire"
              type="select"
              label="Гримуар"
              options={[
                {"Как обычно · только подготовленное", "prepared"},
                {"Без гримуара · любое своё заклинание", "free"}
              ]}
            />
            <.input
              field={@form[:mana]}
              id="arena-rule-mana"
              type="select"
              label="Мана"
              options={[
                {"Как обычно · запас и восстановление", "standard"},
                {"Без маны · ничего не тратится", "unlimited"}
              ]}
            />
            <.input
              field={@form[:rank]}
              id="arena-rule-rank"
              type="select"
              label="Ранг"
              options={[
                {"Без ограничений · любое своё заклинание", "free"},
                {"Как в ранговом бою · по своему рангу", "own"}
              ]}
            />
            <.input
              field={@form[:rank_cap]}
              id="arena-rule-rank-cap"
              type="select"
              label="Потолок ранга заклинаний"
              options={rank_cap_options()}
            />
          </div>
        </section>

        <section class="arena-room-form__panel">
          <h2>III · События поля</h2>
          <.input
            field={@form[:event_policy]}
            id="arena-event-policy"
            type="select"
            label="Режим событий"
            options={[
              {"Случайная ротация", "random"},
              {"По порядку колоды", "fixed"},
              {"Без событий", "none"}
            ]}
          />

          <div id="arena-room-event-deck" phx-update="stream" class="arena-event-picker">
            <label
              :for={{id, event} <- @streams.arena_events}
              id={id}
              class={[
                "arena-event-choice",
                event["code"] in @selected_event_codes && "arena-event-choice--selected"
              ]}
            >
              <input
                type="checkbox"
                name="arena_room[event_codes][]"
                value={event["code"]}
                checked={event["code"] in @selected_event_codes}
              />
              <span>{event_glyph(event["code"])}</span>
              <div>
                <strong>{event["name"]}</strong><small>{Enum.join(event["tags"], " · ")}</small>
              </div>
              <.icon name="hero-check" />
            </label>
          </div>
        </section>

        <button id="arena-submit-room" type="submit" class="arena-button arena-button--gold">
          Создать комнату <.icon name="hero-arrow-right" />
        </button>
      </.form>
    </div>
    """
  end

  attr :room, :any, required: true
  attr :profile, Profile, required: true
  attr :streams, :map, required: true

  defp room(assigns) do
    assigns =
      assigns
      |> assign(:membership, membership(assigns.room, assigns.profile))
      |> assign(:host?, assigns.room && assigns.room.host_profile_id == assigns.profile.id)

    ~H"""
    <div id="arena-room" class="arena-page">
      <.link id="arena-room-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>

      <%= if @room do %>
        <header class="arena-room-head">
          <div>
            <p>Дружеская комната · код <strong id="arena-room-code">{@room.code}</strong></p>
            <h1>{room_name(@room)}</h1>
            <span>{room_description(@room)}</span>
          </div>
          <dl>
            <div>
              <dt>Формат</dt>
              <dd>{@room.team_size}v{@room.team_size}</dd>
            </div>
            <div>
              <dt>События</dt>
              <dd>{event_policy_label(@room.event_policy)}</dd>
            </div>
            <div>
              <dt>Ход</dt>
              <dd>{room_turn_seconds(@room)} сек.</dd>
            </div>
            <div>
              <dt>Рейтинг</dt>
              <dd>Не меняется</dd>
            </div>
            <div :if={room_rules_summary(@room)} id="arena-room-rules">
              <dt>Особые правила</dt>
              <dd>{room_rules_summary(@room)}</dd>
            </div>
          </dl>
        </header>

        <section id="arena-room-teams" class="arena-teams">
          <article class="arena-team arena-team--a">
            <header>
              <span>Команда A</span><strong>{team_count(@room, :a)} / {@room.team_size}</strong>
            </header>
            <div id="arena-team-a" phx-update="stream" class="arena-team__members">
              <p id="arena-team-a-empty" class="arena-empty hidden only:block">Свободные места</p>
              <div :for={{id, member} <- @streams.team_a} id={id} class="arena-member">
                <span>{member_initial(member)}</span>
                <div>
                  <strong>{member.profile.character.name}</strong><small>{member_rank(member)}</small>
                </div>
                <em class={member.ready && "is-ready"}>
                  {if(member.ready, do: "готов", else: "собирается")}
                </em>
              </div>
            </div>
            <button
              :if={is_nil(@membership) and team_count(@room, :a) < @room.team_size}
              id="arena-join-team-a"
              type="button"
              phx-click="join_room"
              phx-value-code={@room.code}
              phx-value-team="a"
            >
              Войти в A
            </button>
            <button
              :if={
                (@membership && @membership.team != :a) and team_count(@room, :a) < @room.team_size
              }
              id="arena-switch-team-a"
              type="button"
              phx-click="switch_team"
              phx-value-team="a"
            >
              Перейти в A
            </button>
          </article>

          <div class="arena-teams__versus">VS</div>

          <article class="arena-team arena-team--b">
            <header>
              <span>Команда B</span><strong>{team_count(@room, :b)} / {@room.team_size}</strong>
            </header>
            <div id="arena-team-b" phx-update="stream" class="arena-team__members">
              <p id="arena-team-b-empty" class="arena-empty hidden only:block">Свободные места</p>
              <div :for={{id, member} <- @streams.team_b} id={id} class="arena-member">
                <span>{member_initial(member)}</span>
                <div>
                  <strong>{member.profile.character.name}</strong><small>{member_rank(member)}</small>
                </div>
                <em class={member.ready && "is-ready"}>
                  {if(member.ready, do: "готов", else: "собирается")}
                </em>
              </div>
            </div>
            <button
              :if={is_nil(@membership) and team_count(@room, :b) < @room.team_size}
              id="arena-join-team-b"
              type="button"
              phx-click="join_room"
              phx-value-code={@room.code}
              phx-value-team="b"
            >
              Войти в B
            </button>
            <button
              :if={
                (@membership && @membership.team != :b) and team_count(@room, :b) < @room.team_size
              }
              id="arena-switch-team-b"
              type="button"
              phx-click="switch_team"
              phx-value-team="b"
            >
              Перейти в B
            </button>
          </article>
        </section>

        <section id="arena-room-event-summary" class="arena-room-events">
          <p>Колода событий</p>
          <span :for={code <- @room.event_codes}>{event_name(code)}</span>
          <span :if={@room.event_codes == []}>События отключены</span>
        </section>

        <footer class="arena-room-actions">
          <button
            :if={@membership}
            id="arena-toggle-ready"
            type="button"
            phx-click="toggle_ready"
            class={["arena-button", @membership.ready && "arena-button--ready"]}
          >
            {if(@membership.ready, do: "Снять готовность", else: "Я готов")}
          </button>
          <button
            :if={@host?}
            id="arena-start-room"
            type="button"
            phx-click="start_room"
            disabled={not room_startable?(@room)}
            class="arena-button arena-button--gold"
          >
            Начать бой <.icon name="hero-bolt" />
          </button>
          <button
            :if={@membership}
            id="arena-leave-room"
            type="button"
            phx-click="leave_room"
            class="arena-button arena-button--quiet"
          >
            <.icon name="hero-arrow-left-start-on-rectangle" />
            {if(@host?, do: "Закрыть комнату", else: "Покинуть комнату")}
          </button>
          <p :if={@host? and not room_startable?(@room)}>
            Заполните обе команды и дождитесь готовности каждого бойца.
          </p>
        </footer>
      <% else %>
        <section id="arena-room-missing" class="arena-empty-state">
          <h1>Комната не найдена</h1>
          <.link navigate={~p"/arena"}>Вернуться к боям</.link>
        </section>
      <% end %>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :streams, :map, required: true

  defp rankings(assigns) do
    ~H"""
    <div id="arena-rankings" class="arena-page arena-page--narrow">
      <.link id="arena-rankings-back" navigate={~p"/arena"} class="arena-back">
        <.icon name="hero-arrow-left" /> К боям
      </.link>
      <header class="arena-page-title">
        <p>Сезон {@profile.season}</p>
        <h1>Рейтинг Арены</h1>
        <span>Дружеские комнаты дают сезонный опыт, но не меняют рейтинг.</span>
      </header>

      <div id="arena-ranking-list" phx-update="stream" class="arena-ranking-list">
        <p id="arena-ranking-empty" class="arena-empty hidden only:block">
          Сезон ещё ждёт первого бойца.
        </p>
        <article
          :for={{id, ranked_profile} <- @streams.rankings}
          id={id}
          class={[
            "arena-ranking-row",
            ranked_profile.id == @profile.id && "arena-ranking-row--self"
          ]}
        >
          <span class="arena-ranking-row__place">{ranked_profile.metadata["ranking_position"]}</span>
          <span class="arena-ranking-row__seal">{rank_glyph(ranked_profile)}</span>
          <div>
            <strong>{ranked_profile.character.name}</strong><small>{rank_label(ranked_profile)} · {schools_short(ranked_profile)}</small>
          </div>
          <dl>
            <div>
              <dt>В</dt>
              <dd>{ranked_profile.wins}</dd>
            </div>
            <div>
              <dt>П</dt>
              <dd>{ranked_profile.losses}</dd>
            </div>
          </dl>
          <em>{ranked_profile.rating}</em>
        </article>
      </div>
    </div>
    """
  end

  defp load_home(socket) do
    profile = Arena.get_profile!(socket.assigns.profile.id)

    socket
    |> assign(:page_title, "Арена")
    |> assign(:profile, profile)
    |> assign(:profile_count, length(account_profiles(profile)))
    |> assign(:quests, Quests.board_for(profile))
    |> assign(:current_match, Arena.active_match_for_profile(profile))
    |> stream(:open_rooms, Arena.list_open_rooms(), reset: true)
  end

  defp load_profiles(socket) do
    socket
    |> assign(:page_title, "Профили Арены")
    |> assign(:profiles, account_profiles(socket.assigns.profile))
  end

  defp load_seats(socket) do
    season = socket.assigns.profile.season

    socket
    |> assign(:page_title, "Титулы Арены")
    |> assign(:champion, Titles.holder(:champion, season))
    |> assign(:deputy, Titles.holder(:deputy, season))
    |> assign(:champion_challenge, Titles.open_challenge(:champion, season))
    |> assign(:deputy_challenge, Titles.open_challenge(:deputy, season))
    |> assign(:own_seat, Titles.seat_held_by(socket.assigns.profile, season))
  end

  defp account_profiles(%Profile{account_id: account_id}),
    do: Arena.list_profiles_for_account(account_id)

  defp load_result(socket, match_id) do
    case History.settlement(socket.assigns.profile, match_id) do
      nil ->
        socket
        |> put_flash(:error, "Этот бой ещё не подведён.")
        |> push_navigate(to: ~p"/arena")

      settlement ->
        socket
        |> assign(:page_title, "Итог боя")
        |> assign(:settlement, settlement)
        |> assign(:profile, Arena.get_profile!(socket.assigns.profile.id))
    end
  end

  defp load_history(socket) do
    socket
    |> assign(:page_title, "История боёв")
    |> assign(:history, History.list_for_profile(socket.assigns.profile))
  end

  # A replay is only readable by someone who fought it: the record of a match is
  # not public, and a combat id from elsewhere must not open one.
  defp load_replay(socket, combat_id) do
    own? =
      socket.assigns.profile
      |> History.list_for_profile(100)
      |> Enum.any?(&(&1.combat_id == combat_id))

    case own? && History.replay(combat_id) do
      nil ->
        socket
        |> put_flash(:error, "Этот бой больше не хранится.")
        |> push_navigate(to: ~p"/arena/history")

      false ->
        socket
        |> put_flash(:error, "Это не ваш бой.")
        |> push_navigate(to: ~p"/arena/history")

      replay ->
        socket
        |> assign(:page_title, "Запись боя")
        |> assign(:replay, replay)
        |> assign(:replay_turn, 1)
    end
  end

  defp load_queue(socket) do
    match = Arena.active_match_for_profile(socket.assigns.profile)

    cond do
      match && match.mode == :custom ->
        push_navigate(socket, to: ~p"/arena/rooms/#{match.code}")

      match && match.status == :active && is_binary(match.combat_id) ->
        push_navigate(socket, to: ~p"/arena/combat/#{match.combat_id}")

      true ->
        socket
        |> assign(:page_title, "Ранговый бой")
        |> assign(:current_match, match)
        |> assign(:queue_snapshot, Arena.queue_snapshot(socket.assigns.profile.season))
    end
  end

  defp load_new_room(socket) do
    case Arena.active_match_for_profile(socket.assigns.profile) do
      %Match{mode: :custom, code: code} ->
        push_navigate(socket, to: ~p"/arena/rooms/#{code}")

      %Match{status: :active, combat_id: combat_id} when is_binary(combat_id) ->
        push_navigate(socket, to: ~p"/arena/combat/#{combat_id}")

      %Match{} ->
        socket
        |> put_flash(:error, "Сначала покиньте ранговую очередь.")
        |> push_navigate(to: ~p"/arena/queue")

      nil ->
        socket
        |> assign(:page_title, "Новая комната")
        |> assign(:selected_event_codes, ArenaEvents.event_codes())
        |> assign(:room_form, room_form())
    end
  end

  defp load_room(socket, code) when is_binary(code) do
    case Arena.get_match_by_code(code) do
      %Match{status: :active, combat_id: combat_id} = room when is_binary(combat_id) ->
        if member?(room, socket.assigns.profile) do
          push_navigate(socket, to: ~p"/arena/combat/#{combat_id}")
        else
          socket
          |> put_flash(:error, "Этот бой уже начался.")
          |> push_navigate(to: ~p"/arena")
        end

      %Match{status: :forming} = room ->
        if connected?(socket), do: Arena.subscribe_room(room.id)

        socket
        |> assign(:page_title, room_name(room))
        |> assign(:room, room)
        |> assign_room_members(room)
        |> schedule_room_refresh()

      _missing_or_closed ->
        socket
        |> put_flash(:error, "Комната не найдена или уже закрыта.")
        |> push_navigate(to: ~p"/arena")
    end
  end

  defp load_room(socket, _code), do: push_navigate(socket, to: ~p"/arena")

  defp load_rankings(socket) do
    rankings =
      socket.assigns.profile.season
      |> Arena.list_rankings(50)
      |> Enum.with_index(1)
      |> Enum.map(fn {profile, position} ->
        %{profile | metadata: Map.put(profile.metadata || %{}, "ranking_position", position)}
      end)

    socket
    |> assign(:page_title, "Рейтинг Арены")
    |> stream(:rankings, rankings, reset: true)
  end

  defp assign_room_members(socket, room) do
    team_a = Enum.filter(room.members, &(&1.team == :a))
    team_b = Enum.filter(room.members, &(&1.team == :b))

    socket
    |> stream(:team_a, team_a, reset: true)
    |> stream(:team_b, team_b, reset: true)
  end

  defp schedule_room_refresh(socket) do
    if connected?(socket),
      do: Process.send_after(self(), :refresh_arena_room, @room_refresh_interval)

    socket
  end

  defp room_form do
    to_form(
      %{
        "room_name" => "Дружеская комната",
        "description" => "Экспериментируем с формулами и событиями поля.",
        "team_size" => "1",
        "turn_seconds" => "45",
        "grimoire" => "prepared",
        "mana" => "standard",
        "rank" => "free",
        "rank_cap" => "",
        "event_policy" => "random",
        "event_codes" => ArenaEvents.event_codes()
      },
      as: :arena_room
    )
  end

  defp normalize_event_codes(codes) do
    codes
    |> List.wrap()
    |> Enum.filter(&(&1 in ArenaEvents.event_codes()))
    |> Enum.uniq()
  end

  defp member?(%Match{} = match, %Profile{} = profile),
    do: Enum.any?(match.members, &(&1.profile_id == profile.id))

  defp membership(nil, _profile), do: nil
  defp membership(room, profile), do: Enum.find(room.members, &(&1.profile_id == profile.id))

  defp team_count(room, team), do: Enum.count(room.members, &(&1.team == team))

  defp room_startable?(room) do
    team_count(room, :a) == room.team_size and team_count(room, :b) == room.team_size and
      Enum.all?(room.members, & &1.ready)
  end

  # The Arena's three sections and every screen that lives inside one, so the
  # bar can say where you are instead of offering you a door you came through.
  defp arena_sections do
    [
      {"arena-nav-fights", ~p"/arena", "Бои",
       [:home, :queue, :new_room, :room, :result, :history, :replay, :seats]},
      {"arena-nav-spellbook", ~p"/arena/spellbook/books", "Гримуар",
       [:cast, :grimoires, :spells]},
      {"arena-nav-rankings", ~p"/arena/rankings", "Рейтинг", [:rankings, :profiles]}
    ]
  end

  defp arena_section_current(live_action, sections) do
    if live_action in sections, do: "page"
  end

  defp rank_label(profile), do: profile |> Arena.rank() |> Ladder.label()

  defp rank_glyph(profile), do: profile |> Arena.rank() |> Ladder.glyph()

  defp school_label(school), do: Map.get(@school_labels, school, to_string(school))

  defp schools_short(profile),
    do: profile.schools |> Enum.map(&school_label/1) |> Enum.join(" · ")

  defp room_name(%Match{settings: settings}),
    do: Map.get(settings || %{}, "room_name", "Дружеская комната")

  defp room_description(%Match{settings: settings}),
    do: Map.get(settings || %{}, "description", "Свободный тренировочный бой.")

  defp room_turn_seconds(%Match{settings: settings}),
    do: Map.get(settings || %{}, "turn_seconds", 45)

  defp current_turn(replay, number), do: Enum.find(replay.turns, &(&1.number == number))

  defp quest_percent(%{progress: progress, goal: goal}) when is_integer(goal) and goal > 0,
    do: progress |> Kernel./(goal) |> Kernel.*(100) |> round() |> min(100) |> max(0)

  defp quest_percent(_quest), do: 0

  defp quests_done(quests), do: Enum.count(quests, & &1.completed?)

  defp wait_estimate_label(%{estimated_wait_seconds: nil}), do: "Ожидание пока не измерено"

  defp wait_estimate_label(%{estimated_wait_seconds: seconds}) when seconds < 60,
    do: "Обычно ждут около #{seconds} сек."

  defp wait_estimate_label(%{estimated_wait_seconds: seconds}),
    do: "Обычно ждут около #{div(seconds, 60)} мин."

  defp outcome_label(:win), do: "Победа"
  defp outcome_label(:loss), do: "Поражение"
  defp outcome_label(_outcome), do: "Ничья"

  defp opponents_label([]), do: "соперник неизвестен"
  defp opponents_label(names), do: "против " <> Enum.join(names, ", ")

  defp match_mode_label(:ranked), do: "ранговый"
  defp match_mode_label(_mode), do: "дружеский"

  defp rating_delta_label(nil), do: "—"
  defp rating_delta_label(0), do: "±0"
  defp rating_delta_label(delta) when delta > 0, do: "+#{delta}"
  defp rating_delta_label(delta), do: to_string(delta)

  defp replay_event_label("spell_cast"), do: "заклинание сработало"
  defp replay_event_label("partial_spell_cast"), do: "заклинание сработало вполсилы"
  defp replay_event_label("spell_failed"), do: "заклинание сорвалось"
  defp replay_event_label("spell_negated"), do: "поле поглотило заклинание"
  defp replay_event_label("insufficient_mana"), do: "не хватило маны"
  defp replay_event_label("manifestation_strike"), do: "удар призванным оружием"
  defp replay_event_label("manifestation_strike_missed"), do: "промах призванным оружием"
  defp replay_event_label("manifestation_upkeep"), do: "проявления требуют маны"
  defp replay_event_label("guard_raised"), do: "защита выставлена"
  defp replay_event_label("parry_failed"), do: "парирование не удалось"
  defp replay_event_label("summon_action"), do: "призванный союзник атаковал"
  defp replay_event_label("summon_action_missed"), do: "призванный союзник промахнулся"
  defp replay_event_label("summon_destroyed"), do: "проявление рассеялось"
  defp replay_event_label("arena_event"), do: "поле Арены изменилось"
  defp replay_event_label("state_tick"), do: "состояние изменило поле боя"
  defp replay_event_label("environment_hazard_tick"), do: "опасная среда наносит урон"
  defp replay_event_label("action_blocked"), do: "действие сорвалось"
  defp replay_event_label("wait"), do: "сторона выждала"
  defp replay_event_label("fled"), do: "участник отступил"
  defp replay_event_label(event_type), do: event_type

  defp seat_holder_name(%{profile: %Profile{character: %{name: name}}}), do: name
  defp seat_holder_name(_seat), do: "место свободно"

  defp seat_note(nil, _challenge), do: "Никто не держит его в этом сезоне."

  defp seat_note(_seat, nil), do: "Вызова нет."

  defp seat_note(_seat, challenge),
    do: "Вызов принят: «#{challenge.challenger_profile.character.name}» ждёт боя."

  defp seat_label(:champion), do: "чемпион"
  defp seat_label(:deputy), do: "наместник"
  defp seat_label(_seat), do: "место"

  defp room_rules_summary(%Match{settings: settings}) do
    settings
    |> Kernel.||(%{})
    |> Map.get("rules", %{})
    |> RoomRules.normalize()
    |> RoomRules.summary()
  end

  defp rank_cap_options do
    [{"Без потолка", ""}] ++ Enum.map(Ladder.keys(), &{Ladder.label(&1), to_string(&1)})
  end

  defp event_policy_label(:random), do: "Случайно"
  defp event_policy_label(:fixed), do: "По колоде"
  defp event_policy_label(:none), do: "Отключены"

  defp event_name(code) do
    ArenaEvents.catalog()
    |> Enum.find(&(&1["code"] == code))
    |> case do
      nil -> code
      event -> event["name"]
    end
  end

  defp event_glyph("emberfall"), do: "✹"
  defp event_glyph("healing_rain"), do: "≋"
  defp event_glyph("verdant_upheaval"), do: "♧"
  defp event_glyph("grave_eclipse"), do: "◐"
  defp event_glyph("wind_shear"), do: "〰"
  defp event_glyph("chaos_surge"), do: "⌁"
  defp event_glyph("order_convergence"), do: "◇"
  defp event_glyph(_code), do: "✦"

  defp member_initial(member) do
    member.profile.character.name |> String.trim() |> String.first() || "?"
  end

  defp member_rank(member), do: "#{rank_label(member.profile)} · #{member.profile.rating}"

  defp active_match_title(%Match{mode: :ranked, status: :queued}), do: "Поиск рангового соперника"
  defp active_match_title(%Match{mode: :custom} = match), do: room_name(match)
  defp active_match_title(%Match{}), do: "Активный бой"

  defp active_match_path(%Match{status: :active, combat_id: combat_id}) when is_binary(combat_id),
    do: ~p"/arena/combat/#{combat_id}"

  defp active_match_path(%Match{mode: :custom, code: code}), do: ~p"/arena/rooms/#{code}"
  defp active_match_path(%Match{}), do: ~p"/arena/queue"

  defp arena_error(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :event_codes),
      do: "Колода содержит недоступное событие.",
      else: "Проверьте состав команд и настройки комнаты."
  end

  defp arena_error(:profile_busy), do: "Вы уже состоите в другом бою."
  defp arena_error(:already_joined), do: "Вы уже в этой комнате."
  defp arena_error(:room_full), do: "Все места в комнате заняты."
  defp arena_error(:team_full), do: "В этой команде больше нет мест."
  defp arena_error(:room_not_found), do: "Комната больше не существует."
  defp arena_error(:room_not_forming), do: "Комната уже закрыта для изменений."
  defp arena_error(:not_a_member), do: "Сначала войдите в одну из команд."
  defp arena_error(:host_only), do: "Открыть бой может только создатель комнаты."
  defp arena_error(:teams_not_full), do: "Обе команды должны быть полностью собраны."
  defp arena_error(:members_not_ready), do: "Не все участники подтвердили готовность."
  defp arena_error(:not_queued), do: "Вы уже не находитесь в очереди."

  defp arena_error({:active_grimoire_required, _profile_id}),
    do: "Каждому участнику нужен активный гримуар хотя бы с одним заклинанием."

  defp arena_error(_reason),
    do: "Арена не приняла действие. Обновите страницу и попробуйте снова."
end
