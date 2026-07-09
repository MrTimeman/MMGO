defmodule MMGOWeb.MapLive do
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Travel
  alias MMGO.Worlds

  # Deterministic palette for org overlays on the political map filter.
  @org_colors ~w(#e05252 #529ee0 #58c470 #c9a227 #9a6ae0 #e0762e #3ec9b8 #d05a9e)

  # ── Personal-overlay demo data (design pass, no backend — see UI_DESIGN_BRIEF).
  # GDD §4: 13 months × 28 days = 364-day year; 1 game-day ≈ 4 real minutes.
  # A coherent 13-month cycle turning through the four seasons.
  @ovl_months [
    {"Месяц Семян", :spring},
    {"Месяц Трав", :spring},
    {"Месяц Цветения", :spring},
    {"Месяц Ливней", :summer},
    {"Месяц Долгих Дней", :summer},
    {"Месяц Зноя", :summer},
    {"Месяц Жатвы", :autumn},
    {"Месяц Листопада", :autumn},
    {"Месяц Туманов", :autumn},
    {"Месяц Первых Морозов", :winter},
    {"Месяц Долгой Ночи", :winter},
    {"Месяц Стужи", :winter},
    {"Месяц Талых Вод", :winter}
  ]

  # Where the party is right now on the world clock.
  @ovl_today %{month_index: 6, day: 14, year: 847}

  @ovl_seasons [
    {:spring, "Весна", "❀"},
    {:summer, "Лето", "☀"},
    {:autumn, "Осень", "❧"},
    {:winter, "Зима", "❄"}
  ]

  # Personal events pinned to days of the current month (Месяц Жатвы).
  @ovl_month_events %{
    16 => {:exam, "Итоговый экзамен"},
    19 => {:club, "Собрание клуба"},
    21 => {:thesis, "Защита диссертации"},
    26 => {:rent, "Срок аренды"}
  }

  @impl true
  def mount(_params, session, socket) do
    realm = Worlds.get_default_realm!()
    locations = Play.list_locations_with_routes(realm.id)
    character = load_character(session)

    socket =
      socket
      |> assign(:page_title, "World Map")
      |> assign(:realm, realm)
      |> assign(:locations, locations)
      |> assign(:organizations, Organizations.list_active_organizations_for_realm(realm.id))
      |> assign_character_state(character)
      |> assign_overlay_demo()

    {:ok, socket}
  end

  # Personal overlay widgets (calendar / notifications / account) live only on
  # the map as corner chips that open bottom-sheets. All demo data below.
  defp assign_overlay_demo(socket) do
    socket
    |> assign(:open_sheet, nil)
    |> assign(:ovl_today, @ovl_today)
    |> assign(:notifications, ovl_demo_notifications())
  end

  defp ovl_demo_notifications do
    [
      %{
        id: "duel",
        kind: :duel,
        icon: "⚔",
        title: "Вызов на дуэль",
        from: "Мирослав Тень",
        body: "Требую поединка у подножия Башни. Docta manu, не иначе.",
        read: false,
        status: :pending
      },
      %{
        id: "org",
        kind: :org,
        icon: "❦",
        title: "Приглашение в организацию",
        from: "Орден Багрового Пламени",
        body: "Ваше мастерство в школе Огня замечено. Врата ложи открыты.",
        read: false,
        status: :pending
      },
      %{
        id: "exam",
        kind: :exam,
        icon: "✒",
        title: "Напоминание об экзамене",
        from: "Академия · Врата Зари",
        body: "Итоговый экзамен по Хаосу — 16 Жатвы, аудитория III.",
        read: false,
        status: nil
      },
      %{
        id: "trade",
        kind: :trade,
        icon: "✦",
        title: "Торговая весть",
        from: "Гильдейский рынок",
        body: "Ваш лот «Пепельный кристалл» продан. +85 монет.",
        read: true,
        status: nil
      },
      %{
        id: "dungeon",
        kind: :dungeon,
        icon: "◈",
        title: "Смена хода подземелья",
        from: "Провалы Эленвира",
        body: "Третий ярус сместился. Прежние проходы обвалились.",
        read: true,
        status: nil
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="game-root">
        <div
          id="world-map"
          phx-hook="HexMap"
          phx-update="ignore"
          class="absolute inset-0"
        />

        <div class="pointer-events-none absolute inset-x-0 top-0 z-20 bg-gradient-to-b from-stone-950/90 via-stone-950/35 to-transparent px-3 pb-10 pt-3 text-stone-100">
          <div class="pointer-events-auto flex items-start justify-between gap-2">
            <div class="flex items-start gap-2">
              <button
                type="button"
                class="ovl-chip ovl-clock"
                phx-click="ovl_open"
                phx-value-sheet="calendar"
                aria-label="Календарь и время мира"
              >
                <span class="ovl-clock__dial" aria-hidden="true">
                  <span class="ovl-clock__arc"></span>
                  <span class="ovl-clock__glyph">{ovl_season_glyph(@ovl_today.month_index)}</span>
                </span>
                <span class="ovl-clock__text">
                  <span class="ovl-clock__date">
                    {@ovl_today.day} {ovl_month_short(@ovl_today.month_index)}
                  </span>
                  <span class="ovl-clock__year">{@ovl_today.year} год</span>
                </span>
              </button>
              <div id="map-character-panel" class="ovl-chip ovl-status">
                <%= if @character do %>
                  <strong class="ovl-status__place">
                    {location_name(@current_location)}
                  </strong>
                  <span class="ovl-status__food">Еда {@food_units}</span>
                <% else %>
                  <span class="ovl-status__place">Мир спит</span>
                  <.link
                    id="map-continue-play-link"
                    navigate={~p"/play/continue"}
                    class="ovl-status__continue"
                  >
                    Продолжить
                  </.link>
                <% end %>
              </div>
            </div>
            <button
              type="button"
              class="ovl-chip ovl-bell"
              phx-click="ovl_open"
              phx-value-sheet="notifications"
              aria-label={"Вести (#{ovl_unread_count(@notifications)} непрочитанных)"}
            >
              <svg class="ovl-bell__icon" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M12 3a5 5 0 0 0-5 5c0 4-1.4 6-3 7h16c-1.6-1-3-3-3-7a5 5 0 0 0-5-5Z" />
                <path d="M10.2 20.2a2 2 0 0 0 3.6 0" />
              </svg>
              <span :if={ovl_unread_count(@notifications) > 0} class="ovl-bell__count">
                {ovl_unread_count(@notifications)}
              </span>
            </button>
          </div>
        </div>

        <button
          type="button"
          class="ovl-portrait"
          phx-click="ovl_open"
          phx-value-sheet="account"
          aria-label="Профиль · Альберт Северин"
          style="--ovl-xp: 68%;"
        >
          <span class="ovl-portrait__ring" aria-hidden="true"></span>
          <span class="ovl-portrait__art" aria-hidden="true">
            <.art_slot
              w={96}
              h={96}
              label="Портрет: Альберт Северин"
              class="ovl-portrait__slot"
            />
          </span>
          <span class="ovl-portrait__level">12</span>
        </button>

        <.ovl_sheets open_sheet={@open_sheet} today={@ovl_today} notifications={@notifications} />

        <%= if @character && @active_journey do %>
          <div
            id="active-journey-card"
            class="absolute bottom-3 left-3 z-20 w-[min(20rem,calc(100vw-1.5rem))] rounded-md border border-amber-500/45 bg-stone-950/88 px-3 py-2 text-sm text-stone-100 shadow-xl shadow-black/40 backdrop-blur"
          >
            <p class="font-semibold text-amber-200">
              {location_name(@active_journey.from_location)}
              <span class="text-stone-500">→</span>
              {location_name(@active_journey.to_location)}
            </p>
            <p class="mt-0.5 text-xs text-stone-400">
              Arrival {format_datetime(@active_journey.arrival_at)} · food {@active_journey.food_units_consumed}
            </p>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("location_clicked", %{"slug" => slug}, socket) do
    start_journey(socket, slug)
  end

  @impl true
  def handle_event("start_journey", %{"slug" => slug}, socket) do
    start_journey(socket, slug)
  end

  @impl true
  def handle_event("preview_path", %{"slug" => slug}, socket) do
    {:noreply, push_path_preview(socket, slug)}
  end

  # ── Personal overlay events (demo only — TODO: wire to real state) ──────────
  @impl true
  def handle_event("ovl_open", %{"sheet" => sheet}, socket) do
    {:noreply, assign(socket, :open_sheet, ovl_sheet_atom(sheet))}
  end

  @impl true
  def handle_event("ovl_close", _params, socket) do
    {:noreply, assign(socket, :open_sheet, nil)}
  end

  @impl true
  def handle_event("ovl_notif_read", %{"id" => id}, socket) do
    {:noreply, update(socket, :notifications, &ovl_mark_read(&1, id))}
  end

  @impl true
  def handle_event("ovl_notif_read_all", _params, socket) do
    {:noreply, update(socket, :notifications, fn list -> Enum.map(list, &%{&1 | read: true}) end)}
  end

  @impl true
  def handle_event("ovl_notif_act", %{"id" => id, "action" => action}, socket) do
    status = if action == "accept", do: :accepted, else: :declined

    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if n.id == id, do: %{n | status: status, read: true}, else: n
      end)

    {:noreply, assign(socket, :notifications, notifications)}
  end

  # Settings / logout stubs — TODO: wire.
  @impl true
  def handle_event("ovl_stub", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:push_map_state, socket) do
    {:noreply, push_map_state(socket)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      if connected?(socket) do
        push_map_state(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  defp start_journey(%{assigns: %{character: nil}} = socket, _slug) do
    {:noreply, push_navigate(socket, to: ~p"/play/continue")}
  end

  defp start_journey(%{assigns: %{active_journey: %Travel.Journey{}}} = socket, _slug) do
    {:noreply, put_flash(socket, :error, "You already have an active journey.")}
  end

  defp start_journey(socket, slug) do
    with {:ok, %{journey: journey, character: character}} <-
           Play.start_journey(socket.assigns.character, slug) do
      {:noreply,
       socket
       |> assign_character_state(character)
       |> put_flash(:info, "Journey started to #{destination_name(journey)}.")
       |> push_map_state()}
    else
      {:error, :no_direct_route} ->
        {:noreply, put_flash(socket, :error, "No direct route to that location.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}

      {:error, :missing_destination} ->
        {:noreply, put_flash(socket, :error, "No destination selected.")}
    end
  end

  defp push_path_preview(%{assigns: %{character: nil}} = socket, _slug), do: socket

  defp push_path_preview(socket, slug) do
    case Play.path_preview(socket.assigns.character, slug) do
      {:ok, %{hexes: hexes, travel_days: travel_days, food_units: food_units}} ->
        push_event(socket, "path_preview", %{
          slug: slug,
          hexes: hexes,
          travel_days: travel_days,
          food_units: food_units
        })

      {:error, reason} ->
        push_event(socket, "path_preview_error", %{slug: slug, reason: inspect(reason)})
    end
  end

  defp push_map_state(socket) do
    %{
      locations: locations,
      character: character,
      current_location: current_location,
      reachable_routes: reachable_routes,
      active_journey: active_journey
    } = socket.assigns

    reachable_slugs =
      reachable_routes
      |> Enum.map(&Play.route_destination(&1, current_location && current_location.id).slug)
      |> MapSet.new()

    player =
      if character && current_location do
        %{
          location_slug: current_location.slug,
          name: character.name,
          travelling: not is_nil(active_journey)
        }
      end

    push_event(socket, "map_state", %{
      locations:
        Enum.map(
          locations,
          &format_location(&1, reachable_slugs, active_journey, current_location)
        ),
      player: player,
      others: [],
      filters: %{orgs: format_orgs(socket.assigns.organizations, locations)}
    })
  end

  defp format_orgs(organizations, locations) do
    slug_by_id = Map.new(locations, &{&1.id, &1.slug})

    organizations
    |> Enum.with_index()
    |> Enum.map(fn {org, index} ->
      %{
        id: org.id,
        name: org.name,
        kind: org.kind,
        color: Enum.at(@org_colors, rem(index, length(@org_colors))),
        location_slugs:
          org.linked_location_ids
          |> Enum.map(&Map.get(slug_by_id, &1))
          |> Enum.reject(&is_nil/1)
      }
    end)
  end

  # GDD §5: the map is the interface — activities are offered on the sheet of
  # the location the character is physically at, never through global nav.
  defp location_actions(%{kind: :city}),
    do: [
      %{label: "Visit Academy", href: "/academy/bulletin-board"},
      %{label: "Organisations", href: "/orgs"}
    ]

  defp location_actions(%{kind: :tower}),
    do: [
      %{label: "Duels", href: "/pvp"},
      %{label: "Spellbook", href: "/spellbook"}
    ]

  defp location_actions(_location), do: []

  defp assign_character_state(socket, nil) do
    socket
    |> assign(:character, nil)
    |> assign(:current_location, nil)
    |> assign(:reachable_routes, [])
    |> assign(:active_journey, nil)
    |> assign(:food_units, 0)
  end

  defp assign_character_state(socket, character) do
    state = Play.state_for_character(character)

    socket
    |> assign(:character, state.character)
    |> assign(:current_location, state.current_location)
    |> assign(:reachable_routes, state.routes)
    |> assign(:active_journey, state.active_journey)
    |> assign(:food_units, state.food_units)
  end

  defp format_location(loc, reachable_slugs, active_journey, current_location) do
    here? =
      not is_nil(current_location) and current_location.id == loc.id and is_nil(active_journey)

    %{
      slug: loc.slug,
      name: loc.name,
      kind: loc.kind,
      x: loc.x,
      y: loc.y,
      safe_zone: loc.safe_zone,
      can_travel: is_nil(active_journey) and MapSet.member?(reachable_slugs, loc.slug),
      actions: if(here?, do: location_actions(loc), else: []),
      description: loc.metadata["description"],
      routes:
        Enum.map(loc.routes || [], fn route ->
          destination = Play.route_destination(route, loc.id)

          %{
            destination_slug: destination.slug,
            risk_level: route.risk_level,
            travel_days: route.travel_days
          }
        end)
    }
  end

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    case Play.load_demo_state(id) do
      {:ok, %{character: character}} -> character
      {:error, _reason} -> nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

  defp destination_name(journey) do
    location_name(journey.to_location)
  end

  defp location_name(nil), do: "Unplaced"
  defp location_name(location), do: location.name

  defp format_datetime(nil), do: "unknown"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  # ── Personal overlay sheets (design pass — all demo data) ───────────────────

  attr :open_sheet, :atom, required: true
  attr :today, :map, required: true
  attr :notifications, :list, required: true

  defp ovl_sheets(assigns) do
    ~H"""
    <div :if={@open_sheet} class="ovl-overlay">
      <button type="button" class="ovl-scrim" phx-click="ovl_close" aria-label="Закрыть">
      </button>

      <%= case @open_sheet do %>
        <% :calendar -> %>
          <section class="ovl-sheet ovl-cal" role="dialog" aria-label="Календарь">
            <span class="ovl-sheet__grip" aria-hidden="true"></span>
            <div class="ovl-sheet__head">
              <div>
                <p class="ovl-sheet__eyebrow">Время мира</p>
                <h2 class="ovl-sheet__title">
                  {ovl_month_full(@today.month_index)} · {@today.year}
                </h2>
              </div>
              <button
                type="button"
                class="ovl-sheet__close"
                phx-click="ovl_close"
                aria-label="Закрыть"
              >
                ✕
              </button>
            </div>

            <div class="ovl-cal__seasons">
              <span
                :for={{key, name, glyph} <- ovl_seasons()}
                class={["ovl-cal__season", key == ovl_season_of(@today.month_index) && "is-now"]}
              >
                <span class="ovl-cal__season-glyph">{glyph}</span>
                <span>{name}</span>
              </span>
            </div>
            <p class="ovl-cal__position">
              Месяц {@today.month_index + 1} из 13 · день {@today.day} из 28
            </p>

            <div class="ovl-cal__grid" role="grid" aria-label="Месяц">
              <span
                :for={cell <- ovl_calendar_days(@today.day)}
                class={["ovl-cal__day", cell.today && "is-today", cell.event_kind && "has-event"]}
              >
                <span class="ovl-cal__num">{cell.day}</span>
                <span :if={cell.event_kind} class="ovl-cal__dot" data-kind={cell.event_kind}></span>
              </span>
            </div>

            <div class="ovl-cal__pins">
              <p class="ovl-sheet__eyebrow">Личные события</p>
              <ul>
                <li :for={ev <- ovl_upcoming(@today.day)} class="ovl-cal__pin">
                  <span class="ovl-cal__pin-glyph" data-kind={ev.kind}>
                    {ovl_event_glyph(ev.kind)}
                  </span>
                  <span class="ovl-cal__pin-body">
                    <span class="ovl-cal__pin-label">{ev.label}</span>
                    <span class="ovl-cal__pin-when">
                      {ev.day} {ovl_month_short(@today.month_index)}{ovl_event_where(ev.kind)}
                    </span>
                  </span>
                </li>
              </ul>
            </div>

            <p class="ovl-cal__note">
              <span class="ovl-cal__note-glyph">✧</span>
              Время мира: 1 день = 4 минуты · 28 дней = месяц · 13 месяцев = год
            </p>
          </section>
        <% :notifications -> %>
          <section class="ovl-sheet ovl-notif" role="dialog" aria-label="Вести">
            <span class="ovl-sheet__grip" aria-hidden="true"></span>
            <div class="ovl-sheet__head">
              <div>
                <p class="ovl-sheet__eyebrow">Вести</p>
                <h2 class="ovl-sheet__title">Почтовый ларь</h2>
              </div>
              <button
                type="button"
                class="ovl-sheet__close"
                phx-click="ovl_close"
                aria-label="Закрыть"
              >
                ✕
              </button>
            </div>

            <div class="ovl-notif__bar">
              <span>{ovl_unread_count(@notifications)} непрочитанных</span>
              <button type="button" class="ovl-notif__readall" phx-click="ovl_notif_read_all">
                прочитать все
              </button>
            </div>

            <ul class="ovl-notif__list">
              <li
                :for={n <- @notifications}
                class={[
                  "ovl-note",
                  !n.read && "is-unread",
                  n.status == :accepted && "is-accepted",
                  n.status == :declined && "is-declined"
                ]}
                phx-click="ovl_notif_read"
                phx-value-id={n.id}
              >
                <span class="ovl-note__seal" data-kind={n.kind} aria-hidden="true">{n.icon}</span>
                <div class="ovl-note__body">
                  <div class="ovl-note__top">
                    <span class="ovl-note__title">{n.title}</span>
                    <span
                      :if={!n.read}
                      class="ovl-note__unread-dot"
                      aria-label="непрочитано"
                    >
                    </span>
                  </div>
                  <p class="ovl-note__from">{n.from}</p>
                  <p class="ovl-note__text">{n.body}</p>

                  <div :if={n.status == :pending} class="ovl-note__actions">
                    <button
                      type="button"
                      class="ovl-btn ovl-btn--accept"
                      phx-click="ovl_notif_act"
                      phx-value-id={n.id}
                      phx-value-action="accept"
                    >
                      Принять
                    </button>
                    <button
                      type="button"
                      class="ovl-btn ovl-btn--decline"
                      phx-click="ovl_notif_act"
                      phx-value-id={n.id}
                      phx-value-action="decline"
                    >
                      Отклонить
                    </button>
                  </div>

                  <p :if={n.status == :accepted} class="ovl-note__stamp ovl-note__stamp--accept">
                    Принято
                  </p>
                  <p :if={n.status == :declined} class="ovl-note__stamp ovl-note__stamp--decline">
                    Отклонено
                  </p>
                </div>
              </li>
            </ul>
          </section>
        <% :account -> %>
          <section class="ovl-sheet ovl-acct" role="dialog" aria-label="Профиль">
            <span class="ovl-sheet__grip" aria-hidden="true"></span>
            <div class="ovl-sheet__head">
              <div>
                <p class="ovl-sheet__eyebrow">Профиль</p>
                <h2 class="ovl-sheet__title">Альберт Северин</h2>
              </div>
              <button
                type="button"
                class="ovl-sheet__close"
                phx-click="ovl_close"
                aria-label="Закрыть"
              >
                ✕
              </button>
            </div>

            <div class="ovl-acct__hero">
              <span class="ovl-acct__portrait" style="--ovl-xp: 68%;">
                <.art_slot
                  w={96}
                  h={96}
                  label="Портрет: Альберт Северин"
                  class="ovl-acct__slot"
                />
                <span class="ovl-acct__lvl">12</span>
              </span>
              <div class="ovl-acct__ident">
                <p class="ovl-acct__class">Чародей · Огонь и Хаос</p>
                <p class="ovl-acct__realm">Княжество Эленвир · Врата Зари</p>
                <p class="ovl-acct__coins">2 340 монет</p>
              </div>
            </div>

            <div class="ovl-acct__xp">
              <div class="ovl-acct__xp-top">
                <span>Уровень 12</span>
                <span>12 400 / 18 000 XP</span>
              </div>
              <div class="ovl-acct__xp-bar"><span style="width: 68%;"></span></div>
              <p class="ovl-acct__xp-note">
                Кривая опыта логарифмическая — путь к сотому длиною в год (§11.1)
              </p>
            </div>

            <div class="ovl-acct__section">
              <p class="ovl-sheet__eyebrow">Школы</p>
              <div class="ovl-acct__chips">
                <span class="ovl-acct__chip" data-school="fire">Огонь</span>
                <span class="ovl-acct__chip" data-school="chaos">Хаос</span>
              </div>
            </div>

            <div class="ovl-acct__section">
              <p class="ovl-sheet__eyebrow">Титулы</p>
              <div class="ovl-acct__chips">
                <span class="ovl-acct__title">Отличник Академии</span>
                <span class="ovl-acct__title ovl-acct__title--donor">❦ Хранитель очага</span>
              </div>
              <p class="ovl-acct__donor-note">
                Почётный титул мецената — украшение без игрового преимущества (§15)
              </p>
            </div>

            <div class="ovl-acct__section ovl-acct__settings">
              <button type="button" class="ovl-acct__row" phx-click="ovl_stub">
                <span>Звук</span><span class="ovl-acct__val">вкл</span>
              </button>
              <button type="button" class="ovl-acct__row" phx-click="ovl_stub">
                <span>Язык</span><span class="ovl-acct__val">русский</span>
              </button>
            </div>

            <button type="button" class="ovl-acct__leave" phx-click="ovl_stub">Выйти из мира</button>
          </section>
      <% end %>
    </div>
    """
  end

  defp ovl_sheet_atom("calendar"), do: :calendar
  defp ovl_sheet_atom("notifications"), do: :notifications
  defp ovl_sheet_atom("account"), do: :account
  defp ovl_sheet_atom(_), do: nil

  defp ovl_unread_count(notifications), do: Enum.count(notifications, &(not &1.read))

  defp ovl_mark_read(notifications, id) do
    Enum.map(notifications, fn n -> if n.id == id, do: %{n | read: true}, else: n end)
  end

  defp ovl_seasons, do: @ovl_seasons

  defp ovl_month_full(idx), do: elem(Enum.at(@ovl_months, idx), 0)

  defp ovl_month_short(idx), do: String.replace_prefix(ovl_month_full(idx), "Месяц ", "")

  defp ovl_season_of(idx), do: elem(Enum.at(@ovl_months, idx), 1)

  defp ovl_season_glyph(idx) do
    season = ovl_season_of(idx)
    {_key, _name, glyph} = Enum.find(@ovl_seasons, fn {key, _, _} -> key == season end)
    glyph
  end

  defp ovl_calendar_days(today_day) do
    for day <- 1..28 do
      event = Map.get(@ovl_month_events, day)

      %{
        day: day,
        today: day == today_day,
        event_kind: event && elem(event, 0),
        event_label: event && elem(event, 1)
      }
    end
  end

  defp ovl_upcoming(today_day) do
    @ovl_month_events
    |> Enum.filter(fn {day, _} -> day >= today_day end)
    |> Enum.sort_by(fn {day, _} -> day end)
    |> Enum.map(fn {day, {kind, label}} -> %{day: day, kind: kind, label: label} end)
  end

  defp ovl_event_glyph(:exam), do: "✒"
  defp ovl_event_glyph(:thesis), do: "❦"
  defp ovl_event_glyph(:rent), do: "⌂"
  defp ovl_event_glyph(:club), do: "✧"
  defp ovl_event_glyph(_), do: "✦"

  defp ovl_event_where(:exam), do: " · аудитория III"
  defp ovl_event_where(:thesis), do: " · аудитория Свода"
  defp ovl_event_where(:rent), do: " · Врата Зари"
  defp ovl_event_where(_), do: ""
end
