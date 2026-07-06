defmodule MMGOWeb.MapEditorLive do
  @moduledoc """
  Dev-only hex-map editor at `/editor`.

  Lets a developer paint terrain, toggle roads, link locations to hexes, and
  manage the sprite manifest, then save straight back to the source
  `priv/static/maps/world.json` file (see `MMGO.WorldMap`).

  Not linked from the game UI and not gated behind auth — it only exists when
  `config :mmgo, dev_routes: true` (dev and test environments).
  """

  use MMGOWeb, :live_view

  alias MMGO.WorldMap
  alias MMGO.WorldMap.Editor
  alias MMGO.WorldMap.Hex
  alias MMGO.Worlds

  @max_sprite_bytes 2_000_000

  @impl true
  def mount(_params, _session, socket) do
    world_map = load_world_map()
    realm = Worlds.get_default_realm()
    locations = if realm, do: Worlds.list_locations_for_realm(realm.id), else: []
    manifest = Editor.load_sprite_manifest()

    socket =
      socket
      |> assign(:page_title, "Map Editor")
      |> assign(:world_map, world_map)
      |> assign(:locations, locations)
      |> assign(:manifest, manifest)
      |> assign(:dirty, %{})
      |> assign(:tool, "paint")
      |> assign(:brush, 1)
      |> assign(:active_terrain, default_terrain(world_map))
      |> assign(:active_sprite, nil)
      |> assign(:active_location, nil)
      |> assign(:new_terrain_error, nil)
      |> assign(:sprite_form_error, nil)
      |> allow_upload(:sprite,
        accept: ~w(.png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: @max_sprite_bytes
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="map-editor" id="map-editor-root">
      <div
        id="map-editor"
        phx-hook="MapEditor"
        phx-update="ignore"
        class="map-editor__canvas-wrap"
      />

      <aside class="map-editor__sidebar">
        <header class="map-editor__header">
          <h1>Map Editor</h1>
          <span class="map-editor__unsaved" data-count={map_size(@dirty)}>
            {if map_size(@dirty) > 0, do: "#{map_size(@dirty)} unsaved", else: "saved"}
          </span>
        </header>

        <section class="map-editor__section">
          <h2>Tools</h2>
          <div class="map-editor__tools">
            <button
              :for={{tool, label} <- tools()}
              type="button"
              class={["map-editor__tool-btn", @tool == tool && "map-editor__tool-btn--active"]}
              phx-click="set_tool"
              phx-value-tool={tool}
            >
              {label}
            </button>
          </div>

          <div class="map-editor__brush">
            <span>Brush</span>
            <button
              :for={
                {size, label} <- [
                  {1, "1"},
                  {2, "2"},
                  {3, "3"},
                  {"l1", "⬡7"},
                  {"l0", "⬡49"}
                ]
              }
              type="button"
              class={["map-editor__brush-btn", @brush == size && "map-editor__brush-btn--active"]}
              phx-click="set_brush"
              phx-value-size={size}
              title={brush_title(size)}
            >
              {label}
            </button>
          </div>
        </section>

        <section class="map-editor__section">
          <h2>Terrain</h2>
          <div class="map-editor__palette">
            <button
              :for={{id, terrain} <- Enum.sort_by(@world_map.terrains, &elem(&1, 0))}
              type="button"
              class={[
                "map-editor__swatch",
                @active_terrain == id && "map-editor__swatch--active"
              ]}
              style={"background-color: #{Map.get(terrain, "color", "#3a3a3a")}"}
              phx-click="set_terrain"
              phx-value-terrain={id}
              title={"#{id} (cost #{format_cost(Map.get(terrain, "cost"))})"}
            >
              <span class="map-editor__swatch-label">{id}</span>
            </button>
          </div>

          <form phx-submit="add_terrain" class="map-editor__new-terrain">
            <input type="text" name="terrain_id" placeholder="id (slug)" required />
            <input type="color" name="color" value="#4a7c47" />
            <input
              type="number"
              name="cost"
              placeholder="cost (blank = impassable)"
              step="0.1"
              min="0"
            />
            <button type="submit">Add terrain</button>
          </form>
          <p :if={@new_terrain_error} class="map-editor__error">{@new_terrain_error}</p>
        </section>

        <section class="map-editor__section">
          <h2>Sprites</h2>
          <div class="map-editor__sprites">
            <button
              :for={sprite <- @manifest["sprites"] || []}
              type="button"
              class={[
                "map-editor__sprite",
                @active_sprite == sprite["id"] && "map-editor__sprite--active"
              ]}
              phx-click="set_sprite"
              phx-value-sprite={sprite["id"]}
              title={"#{sprite["id"]} (#{sprite["terrain"]})"}
            >
              <img src={"/sprites/#{sprite["file"]}"} alt={sprite["id"]} />
              <span>{sprite["id"]}</span>
            </button>
            <button
              :if={@active_sprite}
              type="button"
              class="map-editor__sprite-clear"
              phx-click="clear_sprite"
            >
              Clear sprite
            </button>
          </div>

          <form
            phx-submit="upload_sprite"
            phx-change="validate_sprite"
            class="map-editor__upload-form"
          >
            <input type="text" name="sprite_id" placeholder="sprite id (slug)" required />
            <select name="terrain">
              <option :for={{id, _} <- @world_map.terrains} value={id}>{id}</option>
            </select>
            <.live_file_input upload={@uploads.sprite} />
            <button type="submit">Upload sprite</button>
            <div :for={entry <- @uploads.sprite.entries} class="map-editor__upload-entry">
              <span>{entry.client_name}</span>
              <progress value={entry.progress} max="100">{entry.progress}%</progress>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}>
                &times;
              </button>
              <p :for={err <- upload_errors(@uploads.sprite, entry)} class="map-editor__error">
                {error_to_string(err)}
              </p>
            </div>
          </form>
          <p :if={@sprite_form_error} class="map-editor__error">{@sprite_form_error}</p>
        </section>

        <section class="map-editor__section">
          <h2>Location</h2>
          <select phx-change="set_location" name="location_slug" class="map-editor__location-select">
            <option value="">(none)</option>
            <option
              :for={loc <- @locations}
              value={loc.slug}
              selected={@active_location == loc.slug}
            >
              {loc.name} ({loc.slug})
            </option>
          </select>
          <p class="map-editor__hint">
            With the location tool active, click a hex to place/clear the selected location.
          </p>
        </section>

        <section class="map-editor__section map-editor__save-section">
          <button type="button" class="map-editor__save-btn" phx-click="save">
            Save map
          </button>
        </section>
      </aside>
    </div>
    """
  end

  # -- tool / palette events ------------------------------------------------

  @impl true
  def handle_event("set_tool", %{"tool" => tool}, socket) do
    {:noreply, socket |> assign(:tool, tool) |> push_editor_state()}
  end

  def handle_event("set_brush", %{"size" => size}, socket) do
    brush =
      case to_string(size) do
        # Aperture-7 hierarchy brushes: paint a whole parent cell at once.
        "l1" -> "l1"
        "l0" -> "l0"
        numeric -> numeric |> String.to_integer() |> max(1) |> min(3)
      end

    {:noreply, socket |> assign(:brush, brush) |> push_editor_state()}
  end

  def handle_event("set_terrain", %{"terrain" => terrain}, socket) do
    {:noreply, socket |> assign(:active_terrain, terrain) |> push_editor_state()}
  end

  def handle_event("set_sprite", %{"sprite" => sprite}, socket) do
    {:noreply, socket |> assign(:active_sprite, sprite) |> push_editor_state()}
  end

  def handle_event("clear_sprite", _params, socket) do
    {:noreply, socket |> assign(:active_sprite, nil) |> push_editor_state()}
  end

  def handle_event("set_location", %{"location_slug" => ""}, socket) do
    {:noreply, socket |> assign(:active_location, nil) |> push_editor_state()}
  end

  def handle_event("set_location", %{"location_slug" => slug}, socket) do
    {:noreply, socket |> assign(:active_location, slug) |> push_editor_state()}
  end

  # -- terrain palette management -------------------------------------------

  def handle_event("add_terrain", %{"terrain_id" => id, "color" => color} = params, socket) do
    id = String.trim(id)
    cost = parse_cost(params["cost"])

    cond do
      id == "" ->
        {:noreply, assign(socket, :new_terrain_error, "Terrain id can't be blank.")}

      Map.has_key?(socket.assigns.world_map.terrains, id) ->
        {:noreply, assign(socket, :new_terrain_error, "Terrain \"#{id}\" already exists.")}

      true ->
        terrain = %{"color" => color, "cost" => cost}
        terrains = Map.put(socket.assigns.world_map.terrains, id, terrain)
        world_map = %{socket.assigns.world_map | terrains: terrains}

        {:noreply,
         socket
         |> assign(:world_map, world_map)
         |> assign(:new_terrain_error, nil)
         |> push_editor_state()
         |> push_event("terrains_updated", %{terrains: world_map.terrains})}
    end
  end

  # -- sprite upload ---------------------------------------------------------

  def handle_event("validate_sprite", _params, socket) do
    {:noreply, assign(socket, :sprite_form_error, nil)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :sprite, ref)}
  end

  def handle_event("upload_sprite", %{"sprite_id" => sprite_id, "terrain" => terrain}, socket) do
    sprite_id = String.trim(sprite_id)

    cond do
      sprite_id == "" ->
        {:noreply, assign(socket, :sprite_form_error, "Sprite id can't be blank.")}

      socket.assigns.uploads.sprite.entries == [] ->
        {:noreply, assign(socket, :sprite_form_error, "Choose a file to upload.")}

      true ->
        do_upload_sprite(socket, sprite_id, terrain)
    end
  end

  # -- hex edits from the canvas hook ----------------------------------------

  def handle_event("hexes_changed", %{"hexes" => hexes}, socket) when is_list(hexes) do
    dirty =
      Enum.reduce(hexes, socket.assigns.dirty, fn hex_params, acc ->
        case normalize_hex_change(hex_params) do
          {:ok, {q, r}, change} -> Map.put(acc, {q, r}, change)
          :error -> acc
        end
      end)

    {:noreply, assign(socket, :dirty, dirty)}
  end

  def handle_event("save", _params, socket) do
    world_map = apply_dirty(socket.assigns.world_map, socket.assigns.dirty)

    case WorldMap.save(world_map, WorldMap.default_path()) do
      {:ok, _path} ->
        world_map = WorldMap.load(WorldMap.default_path())

        {:noreply,
         socket
         |> assign(:world_map, world_map)
         |> assign(:dirty, %{})
         |> put_flash(:info, "Map saved (#{map_size(world_map.hexes)} hexes).")
         |> push_event("map_saved", %{})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp do_upload_sprite(socket, sprite_id, terrain) do
    results =
      consume_uploaded_entries(socket, :sprite, fn %{path: tmp_path}, entry ->
        ext = entry.client_name |> Path.extname() |> String.downcase()
        ext = if ext in ~w(.png .jpg .jpeg .webp), do: ext, else: ".png"
        filename = "#{sprite_id}#{ext}"

        case Editor.store_sprite(tmp_path, filename) do
          :ok -> {:ok, filename}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [filename] when is_binary(filename) ->
        {:ok, manifest} = Editor.upsert_sprite_manifest(sprite_id, filename, terrain)

        {:noreply,
         socket
         |> assign(:manifest, manifest)
         |> assign(:sprite_form_error, nil)
         |> put_flash(:info, "Sprite \"#{sprite_id}\" uploaded.")
         |> push_event("manifest_updated", %{manifest: manifest})}

      [{:error, reason}] ->
        {:noreply, assign(socket, :sprite_form_error, "Upload failed: #{inspect(reason)}")}

      [] ->
        {:noreply, assign(socket, :sprite_form_error, "Choose a file to upload.")}
    end
  end

  defp load_world_map do
    path = WorldMap.default_path()

    if File.exists?(path) do
      WorldMap.load(path)
    else
      %WorldMap{}
    end
  end

  defp default_terrain(%WorldMap{terrains: terrains}) do
    terrains |> Map.keys() |> Enum.sort() |> List.first()
  end

  defp tools do
    [
      {"paint", "Paint"},
      {"erase", "Erase"},
      {"road", "Road"},
      {"location", "Location"},
      {"pan", "Pan"}
    ]
  end

  defp format_cost(nil), do: "impassable"
  defp format_cost(cost), do: to_string(cost)

  defp parse_cost(nil), do: nil
  defp parse_cost(""), do: nil

  defp parse_cost(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp error_to_string(:too_large), do: "File is too large (max 2MB)."
  defp error_to_string(:not_accepted), do: "File type not accepted."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(other), do: to_string(other)

  defp normalize_hex_change(%{"q" => q, "r" => r} = params) do
    with {:ok, q} <- to_int(q), {:ok, r} <- to_int(r) do
      change =
        if params["delete"] do
          :delete
        else
          %{
            terrain: params["t"],
            sprite: blank_to_nil(params["s"]),
            road: !!params["road"],
            loc: blank_to_nil(params["loc"])
          }
        end

      {:ok, {q, r}, change}
    else
      _ -> :error
    end
  end

  defp normalize_hex_change(_), do: :error

  defp to_int(value) when is_integer(value), do: {:ok, value}

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> {:ok, int}
      :error -> :error
    end
  end

  defp to_int(_), do: :error

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # Applies the accumulated dirty set onto the loaded map struct, enforcing
  # the "one hex per location" invariant (clearing the slug from any other
  # hex that previously held it).
  defp apply_dirty(%WorldMap{} = world_map, dirty) do
    Enum.reduce(dirty, world_map, fn
      {{q, r}, :delete}, acc ->
        %{acc | hexes: Map.delete(acc.hexes, {q, r})}

      {{q, r}, change}, acc ->
        acc = maybe_clear_other_location(acc, {q, r}, change[:loc])

        existing = Map.get(acc.hexes, {q, r})

        hex = %Hex{
          q: q,
          r: r,
          terrain: change[:terrain] || (existing && existing.terrain) || default_terrain(acc),
          sprite:
            if(Map.has_key?(change, :sprite),
              do: change[:sprite],
              else: existing && existing.sprite
            ),
          road:
            if(Map.has_key?(change, :road),
              do: change[:road],
              else: (existing && existing.road) || false
            ),
          loc: if(Map.has_key?(change, :loc), do: change[:loc], else: existing && existing.loc)
        }

        %{acc | hexes: Map.put(acc.hexes, {q, r}, hex)}
    end)
    |> rebuild_location_index()
  end

  defp maybe_clear_other_location(world_map, _coord, nil), do: world_map

  defp maybe_clear_other_location(world_map, coord, slug) do
    hexes =
      Enum.into(world_map.hexes, %{}, fn
        {other_coord, %Hex{loc: ^slug} = hex} when other_coord != coord ->
          {other_coord, %{hex | loc: nil}}

        entry ->
          entry
      end)

    %{world_map | hexes: hexes}
  end

  defp rebuild_location_index(%WorldMap{} = world_map) do
    location_index =
      Enum.reduce(world_map.hexes, %{}, fn {coord, hex}, acc ->
        case hex.loc do
          nil -> acc
          slug -> Map.put(acc, slug, coord)
        end
      end)

    %{world_map | location_index: location_index}
  end

  defp brush_title(1), do: "Single hex"
  defp brush_title(2), do: "Radius 2"
  defp brush_title(3), do: "Radius 3"
  defp brush_title("l1"), do: "Level-1 cell (7 hexes)"
  defp brush_title("l0"), do: "Level-0 region (49 hexes)"

  defp push_editor_state(socket) do
    push_event(socket, "editor_state", %{
      tool: socket.assigns.tool,
      brush: socket.assigns.brush,
      terrain: socket.assigns.active_terrain,
      sprite: socket.assigns.active_sprite,
      location: socket.assigns.active_location
    })
  end
end
