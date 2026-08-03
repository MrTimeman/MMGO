defmodule MMGOWeb.MapLive do
  @moduledoc """
  The scoped player's live world map.

  The map renderer receives a small presentation payload, while every value in
  that payload comes from `MMGO.Play.world_hub_state/1` and therefore from the
  signed current scope rather than a default realm or browser parameter.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGO.Travel

  @org_colors ~w(#e05252 #529ee0 #58c470 #c9a227 #9a6ae0 #e0762e #3ec9b8 #d05a9e)
  @world_seasons [
    %{key: :spring, name: "Весна", glyph: "❀", months: "I—III"},
    %{key: :summer, name: "Лето", glyph: "☀", months: "IV—VI"},
    %{key: :autumn, name: "Осень", glyph: "❧", months: "VII—IX"},
    %{key: :winter, name: "Зима", glyph: "❄", months: "X—XIII"}
  ]
  @legacy_location_names %{
    "capital-city" => "Столица",
    "amber-harbor" => "Янтарная Гавань",
    "ash-crossing" => "Пепельный Перекрёсток",
    "watchpoint" => "Дозорный Пост",
    "the-tower" => "Башня",
    "northeast-city" => "Восточный Предел",
    "south-town" => "Южный Форт",
    "far-south-village" => "Дальняя Слобода",
    "mountain-watchtower" => "Горная Стража"
  }
  @refresh_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Карта мира")
      |> assign(:map_location_selected?, false)
      |> assign(:account_menu_open?, false)
      |> assign(:calendar_open?, false)
      |> refresh_world()
      |> schedule_refresh()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket = if connected?(socket), do: push_map_state(socket), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_world, socket) do
    socket =
      socket
      |> refresh_world()
      |> push_map_state()
      |> schedule_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_event("location_clicked", %{"slug" => slug}, socket), do: start_journey(socket, slug)

  @impl true
  def handle_event("start_journey", %{"slug" => slug}, socket), do: start_journey(socket, slug)

  @impl true
  def handle_event("preview_path", %{"slug" => slug}, socket) do
    {:noreply, push_path_preview(socket, slug)}
  end

  @impl true
  def handle_event("map_location_selected", %{"selected" => selected}, socket)
      when is_boolean(selected) do
    {:noreply, assign(socket, :map_location_selected?, selected)}
  end

  @impl true
  def handle_event("toggle_world_calendar", _params, socket) do
    if socket.assigns.calendar_open? do
      {:noreply, assign(socket, :calendar_open?, false)}
    else
      {:noreply,
       socket
       |> assign(:calendar_open?, true)
       |> assign(:account_menu_open?, false)
       |> push_event("close_map_sheet", %{})
       |> push_event("close_map_layer_menu", %{})}
    end
  end

  @impl true
  def handle_event("close_world_calendar", _params, socket) do
    {:noreply, assign(socket, :calendar_open?, false)}
  end

  @impl true
  def handle_event("toggle_account_menu", _params, socket) do
    opening? = not socket.assigns.account_menu_open?

    socket =
      socket
      |> assign(:account_menu_open?, opening?)
      |> then(fn socket ->
        if opening?, do: push_event(socket, "close_map_layer_menu", %{}), else: socket
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_account_menu", _params, socket) do
    {:noreply, assign(socket, :account_menu_open?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main class="game-root game-root--viewport" aria-label="Карта мира">
        <div
          id="world-map"
          phx-hook="HexMap"
          phx-update="ignore"
          class="absolute inset-0"
        />

        <header class="map-overlay-header pointer-events-none absolute inset-x-0 top-0 z-20 px-3 pb-14 pt-3">
          <div class="pointer-events-auto mx-auto flex max-w-5xl items-start justify-between gap-3">
            <button
              id="map-world-clock"
              type="button"
              phx-click="toggle_world_calendar"
              class="ovl-chip ovl-clock"
              aria-label="Открыть календарь мира"
              aria-haspopup="dialog"
              aria-expanded={to_string(@calendar_open?)}
              aria-controls="map-world-calendar"
            >
              <span class="ovl-clock__dial" aria-hidden="true">
                <span class="ovl-clock__arc"></span>
                <span class="ovl-clock__glyph">{@world_time.season_glyph}</span>
              </span>
              <span class="ovl-clock__text">
                <span class="ovl-clock__date">{@world_time.day} {@world_time.month_name}</span>
                <span class="ovl-clock__year">
                  {@world_time.year} год · {@world_time.season_name}
                </span>
              </span>
            </button>

            <div class="map-account relative" phx-click-away="close_account_menu">
              <button
                id="map-account-menu-toggle"
                type="button"
                phx-click="toggle_account_menu"
                aria-haspopup="menu"
                aria-expanded={to_string(@account_menu_open?)}
                aria-controls="map-account-menu"
                class="map-account-trigger group flex min-h-11 items-center gap-2 px-3 py-2 text-right"
              >
                <span>
                  <span class="map-account-trigger__name block">
                    {@character.name}
                  </span>
                  <span class="map-account-trigger__level block">
                    уровень {@character.level}
                  </span>
                </span>
                <.icon
                  name="hero-chevron-down"
                  class={[
                    "map-account-trigger__chevron size-3.5",
                    @account_menu_open? && "rotate-180"
                  ]}
                />
              </button>

              <div
                :if={@account_menu_open?}
                id="map-account-menu"
                role="menu"
                class="map-account-menu absolute right-0 top-[calc(100%+0.5rem)] w-48 overflow-hidden p-1.5 text-left"
              >
                <p class="map-account-menu__heading">Личный дорожный журнал</p>
                <.link
                  id="map-account-inventory"
                  navigate={~p"/inventory"}
                  role="menuitem"
                  class="map-account-menu__item flex min-h-11 items-center gap-2.5 px-3"
                >
                  <.icon name="hero-archive-box" class="size-4" /> Инвентарь
                </.link>
              </div>
            </div>
          </div>
        </header>

        <div :if={@calendar_open?} id="map-world-calendar-overlay" class="ovl-overlay">
          <button
            type="button"
            class="ovl-scrim"
            phx-click="close_world_calendar"
            aria-label="Закрыть календарь"
          >
          </button>

          <section
            id="map-world-calendar"
            class="ovl-sheet ovl-cal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="map-world-calendar-title"
          >
            <span class="ovl-sheet__grip" aria-hidden="true"></span>

            <div class="ovl-sheet__head">
              <div>
                <p class="ovl-sheet__eyebrow">Мировой альманах</p>
                <h2 id="map-world-calendar-title" class="ovl-sheet__title">
                  {@world_time.month_name} · {@world_time.year}
                </h2>
              </div>
              <button
                id="map-world-calendar-close"
                type="button"
                class="ovl-sheet__close"
                phx-click="close_world_calendar"
                aria-label="Закрыть календарь"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="ovl-cal__seasons" aria-label="Круг времён года">
              <span
                :for={season <- world_seasons()}
                class={["ovl-cal__season", season.key == @world_time.season && "is-now"]}
              >
                <span class="ovl-cal__season-glyph" aria-hidden="true">{season.glyph}</span>
                <span>{season.name}</span>
                <small>{season.months}</small>
              </span>
            </div>

            <div class="ovl-cal__month-ring" aria-label="Тринадцать месяцев года">
              <span
                :for={month <- 1..13}
                class={["ovl-cal__month-mark", month == @world_time.month_number && "is-now"]}
                aria-current={if(month == @world_time.month_number, do: "true", else: nil)}
              >
                {month}
              </span>
            </div>

            <p class="ovl-cal__position">
              {@world_time.month_number}-й месяц из 13 · {@world_time.day}-й день из 28 · день {@world_time.day_of_year} года
            </p>

            <div class="ovl-cal__grid" role="grid" aria-label={@world_time.month_name}>
              <span
                :for={day <- 1..28}
                class={["ovl-cal__day", day == @world_time.day && "is-today"]}
                role="gridcell"
                aria-label={"#{day}-й день"}
                aria-current={if(day == @world_time.day, do: "date", else: nil)}
              >
                <span class="ovl-cal__num">{day}</span>
              </span>
            </div>

            <p class="ovl-cal__note">
              <span class="ovl-cal__note-glyph" aria-hidden="true">✧</span>
              Один день мира проходит примерно за четыре минуты. В месяце 28 дней, в году — 13 месяцев.
            </p>
          </section>
        </div>

        <aside
          :if={is_nil(@active_journey) and not @map_location_selected? and not @calendar_open?}
          id="map-character-panel"
          class="map-journal absolute bottom-3 left-1/2 z-20 w-[min(24rem,calc(100vw-1.5rem))] -translate-x-1/2 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="map-journal__eyebrow">
                Вы сейчас
              </p>
              <h1 id="map-current-location" class="map-journal__title mt-1">
                {location_name(@current_location)}
              </h1>
            </div>
            <span class="map-journal__food shrink-0 px-2.5 py-1">
              Еда: {@survival.food_units}
            </span>
          </div>

          <p class="map-journal__copy mt-2">
            Нажмите соседнее место, чтобы увидеть маршрут. Нажмите место под своим маркером, чтобы осмотреться.
          </p>

          <span
            :if={@nearby_characters != []}
            id="map-nearby-count"
            class="map-journal__nearby mt-3 block"
          >
            Рядом: {length(@nearby_characters)}
          </span>

          <.link
            :if={@notifications != []}
            id="map-notifications-history"
            navigate={~p"/notifications"}
            class="map-journal__news mt-3 inline-flex items-center gap-1.5"
          >
            <.icon name="hero-bell" class="size-3.5" /> Новые вести: {length(@notifications)}
          </.link>
        </aside>

        <.link
          :if={not is_nil(@active_journey) and not @calendar_open?}
          id="active-journey-card"
          navigate={~p"/travel"}
          class="map-journey-slip absolute bottom-3 left-1/2 z-20 w-[min(24rem,calc(100vw-1.5rem))] -translate-x-1/2 px-4 py-3"
        >
          <p class="map-journey-slip__route">
            <span class="map-journey-slip__place">
              <small>Откуда</small>
              {location_name(@active_journey.from_location)}
            </span>
            <span class="map-journey-slip__arrow" aria-hidden="true">→</span>
            <span class="map-journey-slip__place map-journey-slip__place--destination">
              <small>Куда</small>
              {location_name(@active_journey.to_location)}
            </span>
          </p>
          <p id="map-travel-state" class="map-journey-slip__note mt-0.5">
            Прибытие {format_datetime(@active_journey.arrival_at)} · запас пищи {@active_journey.food_units_consumed}
          </p>
        </.link>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_world(socket) do
    case Play.world_hub_state(socket.assigns.current_scope.character) do
      {:ok, world} ->
        socket
        |> assign(:realm, world.realm)
        |> assign(:locations, world.locations)
        |> assign(:organizations, world.organizations)
        |> assign(:organization_economic_activity, world.organization_economic_activity)
        |> assign(:world_time, world.world_time)
        |> assign(:character, world.character)
        |> assign(:current_location, world.current_location)
        |> assign(:reachable_routes, world.routes)
        |> assign(:active_journey, world.active_journey)
        |> assign(:survival, world.survival)
        |> assign(:atmosphere, world.atmosphere)
        |> assign(:notifications, world.notifications)
        |> assign(:nearby_characters, world.nearby_characters)
        |> assign(:open_encounters, world.open_encounters)

      {:error, _reason} ->
        push_navigate(socket, to: ~p"/play")
    end
  end

  defp schedule_refresh(socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_world, @refresh_interval)
    socket
  end

  defp start_journey(%{assigns: %{active_journey: %Travel.Journey{}}} = socket, _slug) do
    {:noreply, put_flash(socket, :error, "Переход уже идёт.")}
  end

  defp start_journey(socket, slug) do
    case Play.start_journey(socket.assigns.character, slug) do
      {:ok, %{journey: journey}} ->
        {:noreply,
         socket
         |> refresh_world()
         |> put_flash(:info, "Путь к #{location_name(journey.to_location)} начался.")
         |> push_map_state()}

      {:error, :no_direct_route} ->
        {:noreply, put_flash(socket, :error, "Прямого пути к этому месту нет.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Не удалось начать переход.")}
    end
  end

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
    reachable_slugs =
      socket.assigns.reachable_routes
      |> Enum.map(&Play.route_destination(&1, socket.assigns.current_location.id).slug)
      |> MapSet.new()

    player = %{
      location_slug: socket.assigns.current_location.slug,
      name: socket.assigns.character.name,
      travelling: not is_nil(socket.assigns.active_journey)
    }

    push_event(socket, "map_state", %{
      locations:
        Enum.map(socket.assigns.locations, fn location ->
          format_location(
            location,
            reachable_slugs,
            socket.assigns.active_journey,
            socket.assigns.current_location
          )
        end),
      player: player,
      others:
        Enum.map(socket.assigns.nearby_characters, fn nearby ->
          %{id: nearby.id, name: nearby.name, location_slug: socket.assigns.current_location.slug}
        end),
      filters: %{
        orgs: format_orgs(socket.assigns.organizations, socket.assigns.locations),
        economic:
          format_economic_activity(
            socket.assigns.organizations,
            socket.assigns.organization_economic_activity,
            socket.assigns.locations
          ),
        diplomacy: format_diplomacy(socket.assigns.organizations)
      }
    })
  end

  defp format_location(location, reachable_slugs, active_journey, current_location) do
    here? = location.id == current_location.id and is_nil(active_journey)

    %{
      slug: location.slug,
      name: location_name(location),
      kind: location.kind,
      x: location.x,
      y: location.y,
      safe_zone: location.safe_zone,
      can_travel: is_nil(active_journey) and MapSet.member?(reachable_slugs, location.slug),
      actions: if(here?, do: [%{label: "Осмотреться", href: "/event"}], else: []),
      description: location.metadata["description"],
      routes:
        Enum.map(location.routes || [], fn route ->
          destination = Play.route_destination(route, location.id)

          %{
            destination_slug: destination.slug,
            risk_level: route.risk_level,
            travel_days: route.travel_days
          }
        end)
    }
  end

  defp format_orgs(organizations, locations) do
    slug_by_id = Map.new(locations, &{&1.id, &1.slug})

    organizations
    |> Enum.with_index()
    |> Enum.map(fn {organization, index} ->
      %{
        id: organization.id,
        name: organization.name,
        kind: organization.kind,
        color: Enum.at(@org_colors, rem(index, length(@org_colors))),
        location_slugs:
          organization.linked_location_ids
          |> Enum.map(&Map.get(slug_by_id, &1))
          |> Enum.reject(&is_nil/1)
      }
    end)
  end

  # Economic visibility uses only the recent count of real organization-ledger
  # movements. It intentionally omits treasury balances and amounts; the map
  # can show activity at a linked location without disclosing private funds.
  defp format_economic_activity(organizations, activity_by_organization_id, locations)
       when is_map(activity_by_organization_id) do
    slug_by_id = Map.new(locations, &{&1.id, &1.slug})

    organizations
    |> Enum.flat_map(fn organization ->
      activity_count = Map.get(activity_by_organization_id, organization.id, 0)

      location_slugs =
        organization.linked_location_ids
        |> Enum.map(&Map.get(slug_by_id, &1))
        |> Enum.reject(&is_nil/1)

      if is_integer(activity_count) and activity_count > 0 and location_slugs != [] do
        [
          %{
            organization_id: organization.id,
            organization_name: organization.name,
            activity_level: economic_activity_level(activity_count),
            location_slugs: location_slugs
          }
        ]
      else
        []
      end
    end)
  end

  defp format_economic_activity(_organizations, _activity_by_organization_id, _locations), do: []

  defp economic_activity_level(activity_count) when activity_count >= 12, do: 4
  defp economic_activity_level(activity_count) when activity_count >= 6, do: 3
  defp economic_activity_level(activity_count) when activity_count >= 2, do: 2
  defp economic_activity_level(_activity_count), do: 1

  defp format_diplomacy(organizations) do
    organizations
    |> Enum.flat_map(fn organization ->
      case Map.get(organization.metadata || %{}, "diplomacy_relationships", []) do
        relationships when is_list(relationships) ->
          Enum.flat_map(relationships, fn relationship ->
            target_organization_id = Map.get(relationship, "organization_id")
            relationship_kind = Map.get(relationship, "kind")

            if is_binary(target_organization_id) and
                 relationship_kind in ["alliance", "rivalry", "war"] do
              [
                %{
                  source_organization_id: organization.id,
                  target_organization_id: target_organization_id,
                  kind: relationship_kind
                }
              ]
            else
              []
            end
          end)

        _other ->
          []
      end
    end)
    |> Enum.uniq_by(fn relationship ->
      [relationship.source_organization_id, relationship.target_organization_id]
      |> Enum.sort()
      |> then(&{&1, relationship.kind})
    end)
  end

  defp location_name(nil), do: "неизвестное место"

  defp location_name(location) do
    Map.get(@legacy_location_names, location.slug, location.name)
  end

  defp format_datetime(nil), do: "неизвестно"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m · %H:%M UTC")

  defp world_seasons, do: @world_seasons

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
