defmodule MMGOWeb.ArenaLive do
  @moduledoc """
  Combat-first Arena hub, ranked queue, friendly rooms, and rankings.

  All room and queue mutations cross the `MMGO.Arena` transaction boundary;
  the LiveView never trusts a client-provided profile, participant, team slot,
  event effect, or combat identifier.
  """

  use MMGOWeb, :live_view

  alias MMGO.Arena
  alias MMGO.Arena.{Match, Profile}
  alias MMGO.Combat.ArenaEvents

  @room_refresh_interval 2_000

  @rank_labels %{
    initiate: "Посвящённый",
    bronze: "Бронза",
    silver: "Серебро",
    gold: "Золото",
    platinum: "Платина",
    diamond: "Алмаз",
    archmage: "Архимаг"
  }

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
        Map.take(params, ["room_name", "description", "turn_seconds"])
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
      _missing_combat -> {:noreply, assign(socket, :arena_error, "Боевой круг ещё не готов.")}
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

          <nav aria-label="Разделы Арены">
            <.link id="arena-nav-fights" navigate={~p"/arena"}>Бои</.link>
            <.link id="arena-nav-spellbook" navigate={~p"/arena/spellbook"}>Гримуары</.link>
            <.link id="arena-nav-rankings" navigate={~p"/arena/rankings"}>Рейтинг</.link>
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
            <.home profile={@profile} current_match={@current_match} streams={@streams} />
          <% :queue -> %>
            <.queue profile={@profile} current_match={@current_match} />
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
        <% end %>
      </main>
    </Layouts.app>
    """
  end

  attr :profile, Profile, required: true
  attr :current_match, :any, required: true
  attr :streams, :map, required: true

  defp home(assigns) do
    ~H"""
    <div id="arena-home" class="arena-page">
      <section class="arena-hero">
        <div class="arena-hero__copy">
          <p class="arena-kicker">Бой начинается сейчас</p>
          <h1>Испытывайте заклинания.<br />Поднимайтесь в рейтинге.</h1>
          <p>
            Без похода за зельями и экипировкой: только три выбранные школы,
            ограниченный гримуар и поле, которое отвечает на вашу магию.
          </p>
          <div class="arena-school-row" aria-label="Выбранные школы">
            <span :for={school <- @profile.schools}>{school_label(school)}</span>
          </div>
        </div>

        <aside id="arena-profile-card" class="arena-rank-card">
          <span class="arena-rank-card__seal">{rank_glyph(@profile)}</span>
          <p>{rank_label(@profile)}</p>
          <strong>{@profile.rating}</strong>
          <small>рейтинг сезона {@profile.season}</small>
          <dl>
            <div>
              <dt>Победы</dt>
              <dd>{@profile.wins}</dd>
            </div>
            <div>
              <dt>Поражения</dt>
              <dd>{@profile.losses}</dd>
            </div>
            <div>
              <dt>Опыт</dt>
              <dd>{@profile.season_xp}</dd>
            </div>
          </dl>
        </aside>
      </section>

      <section :if={@current_match} id="arena-active-match" class="arena-active-match">
        <div>
          <p>Незавершённый круг</p>
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

      <section id="arena-play-modes" class="arena-mode-grid">
        <article class="arena-play-card arena-play-card--ranked">
          <span class="arena-play-card__icon"><.icon name="hero-trophy" /></span>
          <p>Соревновательный · 1v1</p>
          <h2>Ранговый поединок</h2>
          <span>Равные уровни, ваш активный гримуар и случайное событие среды.</span>
          <.link id="arena-ranked-queue" navigate={~p"/arena/queue"} class="arena-button">
            Найти соперника <.icon name="hero-bolt" />
          </.link>
        </article>

        <article class="arena-play-card arena-play-card--custom">
          <span class="arena-play-card__icon"><.icon name="hero-user-group" /></span>
          <p>Дружеский · без рейтинга</p>
          <h2>Свой боевой круг</h2>
          <span>1v1, 2v2 или до 5v5. Выберите размер команд и колоду событий.</span>
          <.link id="arena-create-room" navigate={~p"/arena/rooms/new"} class="arena-button">
            Создать комнату <.icon name="hero-plus" />
          </.link>
        </article>
      </section>

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
            </div>
            <span>{length(room.members)} / {room.team_size * 2} бойцов</span>
            <.link id={"join-open-room-#{room.id}"} navigate={~p"/arena/rooms/#{room.code}"}>
              Войти <.icon name="hero-arrow-right" />
            </.link>
          </article>
        </div>
      </section>

      <section id="arena-system-highlights" class="arena-section arena-section--events">
        <div class="arena-section__head">
          <div>
            <p>Поле — часть формулы</p>
            <h2>События меняют правила хода</h2>
          </div>
          <span>По умолчанию включены</span>
        </div>
        <div id="arena-event-catalog" phx-update="stream" class="arena-event-grid">
          <article :for={{id, event} <- @streams.arena_events} id={id} class="arena-event-card">
            <span>{event_glyph(event["code"])}</span>
            <div>
              <strong>{event["name"]}</strong>
              <p>{event["description"]}</p>
            </div>
            <small>{Enum.join(event["tags"], " · ")}</small>
          </article>
        </div>
      </section>

      <section id="arena-summon-highlight" class="arena-summons">
        <div class="arena-summons__art" aria-hidden="true">♞</div>
        <div>
          <p>Новая ветвь spellcraft</p>
          <h2>Призывайте то, чего не нужно носить</h2>
          <p>
            Создайте заклинание щита, оружия или существа-союзника. Щит перехватывает удары,
            клинок открывает отдельную атаку, а существо имеет здоровье, защищает хозяина и
            действует само.
          </p>
        </div>
        <.link id="arena-create-summon-spell" navigate={~p"/arena/spellbook"} class="arena-button">
          Открыть круг заклинаний <.icon name="hero-sparkles" />
        </.link>
      </section>
    </div>
    """
  end

  attr :profile, Profile, required: true
  attr :current_match, :any, required: true

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

        <%= if @current_match && @current_match.status == :queued do %>
          <div id="arena-searching" class="arena-searching">
            <span class="arena-searching__orb"><.icon name="hero-sparkles" /></span>
            <h2>Круг ищет равного соперника</h2>
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
        <h1>Настройте боевой круг</h1>
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
          <h2>II · События поля</h2>
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
            Открыть боевой круг <.icon name="hero-bolt" />
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
    |> assign(:current_match, Arena.active_match_for_profile(profile))
    |> stream(:open_rooms, Arena.list_open_rooms(), reset: true)
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
        "room_name" => "Дружеский круг",
        "description" => "Экспериментируем с формулами и событиями поля.",
        "team_size" => "1",
        "turn_seconds" => "45",
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

  defp rank_label(profile), do: Map.fetch!(@rank_labels, Arena.rank(profile))

  defp rank_glyph(profile) do
    case Arena.rank(profile) do
      :initiate -> "◇"
      :bronze -> "◆"
      :silver -> "✦"
      :gold -> "✺"
      :platinum -> "✧"
      :diamond -> "◈"
      :archmage -> "✹"
    end
  end

  defp school_label(school), do: Map.get(@school_labels, school, to_string(school))

  defp schools_short(profile),
    do: profile.schools |> Enum.map(&school_label/1) |> Enum.join(" · ")

  defp room_name(%Match{settings: settings}),
    do: Map.get(settings || %{}, "room_name", "Дружеский круг")

  defp room_description(%Match{settings: settings}),
    do: Map.get(settings || %{}, "description", "Свободный тренировочный бой.")

  defp room_turn_seconds(%Match{settings: settings}),
    do: Map.get(settings || %{}, "turn_seconds", 45)

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

  defp arena_error(:profile_busy), do: "Вы уже состоите в другом боевом круге."
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
