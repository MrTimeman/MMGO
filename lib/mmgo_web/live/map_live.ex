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
  @refresh_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Карта мира")
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} atmosphere={@atmosphere}>
      <main class="game-root" aria-label="Карта мира">
        <div
          id="world-map"
          phx-hook="HexMap"
          phx-update="ignore"
          class="absolute inset-0"
        />

        <header class="pointer-events-none absolute inset-x-0 top-0 z-20 bg-gradient-to-b from-stone-950/90 via-stone-950/50 to-transparent px-3 pb-14 pt-3 text-stone-100">
          <div class="pointer-events-auto mx-auto flex max-w-5xl items-start justify-between gap-3">
            <section id="map-world-clock" class="ovl-chip ovl-clock" aria-label="Время мира">
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
            </section>

            <section class="rounded-full border border-stone-700/70 bg-stone-950/80 px-3 py-2 text-right shadow-lg backdrop-blur">
              <p class="font-sans text-xs font-bold text-amber-100">{@character.name}</p>
              <p class="font-sans text-[0.65rem] text-stone-400">уровень {@character.level}</p>
            </section>
          </div>
        </header>

        <aside
          :if={is_nil(@active_journey)}
          id="map-character-panel"
          class="absolute bottom-3 left-1/2 z-20 w-[min(24rem,calc(100vw-1.5rem))] -translate-x-1/2 rounded-2xl border border-amber-500/25 bg-stone-950/92 p-4 text-stone-100 shadow-2xl shadow-black/50 backdrop-blur-xl"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="font-sans text-[0.65rem] font-bold uppercase tracking-[0.16em] text-stone-500">
                Вы сейчас
              </p>
              <h1 id="map-current-location" class="mt-1 font-serif text-xl text-amber-100">
                {location_name(@current_location)}
              </h1>
            </div>
            <span class="shrink-0 rounded-full border border-stone-700 bg-stone-900 px-2.5 py-1 font-sans text-xs text-stone-300">
              Еда: {@survival.food_units}
            </span>
          </div>

          <p class="mt-2 font-sans text-sm leading-5 text-stone-400">
            Чтобы отправиться в путь, выберите соседнее место на карте. Чтобы заняться делами здесь — откройте действия локации.
          </p>

          <div class="mt-4 flex items-center gap-3">
            <.link
              id="map-activity-link"
              navigate={~p"/event"}
              class="inline-flex min-h-11 flex-1 items-center justify-center gap-2 rounded-xl bg-amber-300 px-4 font-sans text-sm font-bold text-stone-950 transition hover:bg-amber-200"
            >
              <.icon name="hero-map-pin" class="size-4" /> Что здесь можно
            </.link>
            <span
              :if={@nearby_characters != []}
              id="map-nearby-count"
              class="font-sans text-xs text-stone-400"
            >
              Рядом: {length(@nearby_characters)}
            </span>
          </div>

          <.link
            :if={@notifications != []}
            id="map-notifications-history"
            navigate={~p"/notifications"}
            class="mt-3 inline-flex items-center gap-1.5 font-sans text-xs text-sky-200 underline decoration-sky-500/40 underline-offset-4"
          >
            <.icon name="hero-bell" class="size-3.5" /> Новые вести: {length(@notifications)}
          </.link>
        </aside>

        <.link
          :if={@active_journey}
          id="active-journey-card"
          navigate={~p"/travel"}
          class="absolute bottom-3 left-1/2 z-20 w-[min(24rem,calc(100vw-1.5rem))] -translate-x-1/2 rounded-2xl border border-amber-500/45 bg-stone-950/92 px-4 py-3 text-sm text-stone-100 shadow-xl shadow-black/40 backdrop-blur"
        >
          <p class="font-semibold text-amber-200">
            {location_name(@active_journey.from_location)}
            <span class="text-stone-500">→</span>
            {location_name(@active_journey.to_location)}
          </p>
          <p id="map-travel-state" class="mt-0.5 text-xs text-stone-400">
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
      name: location.name,
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
  defp location_name(location), do: location.name

  defp format_datetime(nil), do: "неизвестно"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m · %H:%M UTC")

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
