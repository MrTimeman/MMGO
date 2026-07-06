defmodule MMGOWeb.MapLive do
  use MMGOWeb, :live_view

  alias MMGO.Organizations
  alias MMGO.Play
  alias MMGO.Travel
  alias MMGO.Worlds

  # Deterministic palette for org overlays on the political map filter.
  @org_colors ~w(#e05252 #529ee0 #58c470 #c9a227 #9a6ae0 #e0762e #3ec9b8 #d05a9e)

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

    {:ok, socket}
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
            <div
              id="map-character-panel"
              class="max-w-[calc(100vw-1.5rem)] rounded-md border border-stone-700/70 bg-stone-950/80 px-3 py-2 shadow-xl shadow-black/30 backdrop-blur"
            >
              <%= if @character do %>
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
                  <strong class="font-semibold text-white">{location_name(@current_location)}</strong>
                  <span class="text-stone-400">Food {@food_units}</span>
                </div>
              <% else %>
                <p class="text-sm text-stone-300">No local play session is active.</p>
                <.link
                  id="map-continue-play-link"
                  navigate={~p"/play/continue"}
                  class="mt-3 inline-flex rounded-md bg-amber-500 px-4 py-2 text-sm font-semibold text-stone-950 transition hover:bg-amber-300"
                >
                  Continue
                </.link>
              <% end %>
            </div>
          </div>
        </div>

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
end
