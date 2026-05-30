defmodule MMGOWeb.MapLive do
  use MMGOWeb, :live_view

  import Ecto.Query, warn: false

  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Route}

  @impl true
  def mount(_params, _session, socket) do
    realm = Worlds.get_default_realm!()
    locations = load_locations_with_routes(realm.id)

    # Placeholder player — replace with real session character later
    player = %{
      location_slug: "capital-city",
      name: "Игрок"
    }

    {:ok, assign(socket, realm: realm, locations: locations, player: player)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-root">
      <div
        id="world-map"
        phx-hook="Map"
        phx-update="ignore"
        style="position:absolute;inset:0"
      />
    </div>
    """
  end

  @impl true
  def handle_event("location_clicked", %{"slug" => slug}, socket) do
    loc = Enum.find(socket.assigns.locations, &(&1.slug == slug))

    if loc do
      # TODO: initiate journey via Travel context
      {:noreply, put_flash(socket, :info, "Путешествие в «#{loc.name}» начато")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:push_map_state, socket) do
    push_map_state(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      push_map_state(socket)
    end

    {:noreply, socket}
  end

  defp push_map_state(socket) do
    %{locations: locations, player: player} = socket.assigns

    others = []  # TODO: load other characters' positions from presence

    push_event(socket, "map_state", %{
      locations: Enum.map(locations, &format_location/1),
      player: player,
      others: others
    })
  end

  defp format_location(loc) do
    %{
      slug: loc.slug,
      name: loc.name,
      kind: loc.kind,
      x: loc.x,
      y: loc.y,
      safe_zone: loc.safe_zone,
      description: loc.metadata["description"],
      routes: Enum.map(loc.routes || [], fn r ->
        dest_slug =
          if r.origin_location_id == loc.id,
            do: r.destination_location.slug,
            else: r.origin_location.slug

        %{destination_slug: dest_slug, risk_level: r.risk_level, travel_days: r.travel_days}
      end)
    }
  end

  defp load_locations_with_routes(realm_id) do
    locations = Worlds.list_locations_for_realm(realm_id)

    routes =
      Repo.all(
        from r in Route,
          where: r.realm_id == ^realm_id,
          preload: [:origin_location, :destination_location]
      )

    Enum.map(locations, fn loc ->
      loc_routes =
        Enum.filter(routes, fn r ->
          r.origin_location_id == loc.id or
            (r.bidirectional and r.destination_location_id == loc.id)
        end)

      Map.put(loc, :routes, loc_routes)
    end)
  end
end
