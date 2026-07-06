defmodule MMGO.WorldMap do
  @moduledoc """
  Loads and saves the hex-tile world map (`priv/static/maps/world.json`).

  The map file is the terrain layer that the `HexMap` frontend hook renders.
  Gameplay location data (slugs, kinds, routes) continues to live in the
  `MMGO.Worlds` context / Postgres; this module only cares about hex terrain,
  sprites, roads, and which hex a location slug sits on.

  Parsed maps are cached in `:persistent_term`, keyed by the source path, and
  invalidated automatically whenever the file's mtime changes on disk. This
  lets an eventual map editor save directly to the source file and have
  running LiveViews pick up the change without a restart.
  """

  alias MMGO.WorldMap.Hex

  defstruct version: 1,
            realm: "default",
            orientation: "pointy",
            hex_size: 64,
            days_per_hex: 0.5,
            terrains: %{},
            hexes: %{},
            location_index: %{}

  @type axial :: {integer(), integer()}

  @type t :: %__MODULE__{
          version: integer(),
          realm: String.t(),
          orientation: String.t(),
          hex_size: number(),
          days_per_hex: number(),
          terrains: %{optional(String.t()) => map()},
          hexes: %{optional(axial()) => Hex.t()},
          location_index: %{optional(String.t()) => axial()}
        }

  @persistent_term_namespace :mmgo_world_map

  @doc """
  Returns the path the app should read/write the world map from.

  Uses the `:mmgo, :world_map_path` config when set (dev/test point this at
  the project source tree so editor saves land where `git` can see them).
  Otherwise falls back to the priv dir bundled with the compiled release.
  """
  def default_path do
    case Application.get_env(:mmgo, :world_map_path) do
      path when is_binary(path) -> path
      _ -> Application.app_dir(:mmgo, "priv/static/maps/world.json")
    end
  end

  @doc "Loads the world map from `default_path/0`, using the persistent_term cache."
  def load, do: load(default_path())

  @doc "Loads the world map from `path`, using the persistent_term cache."
  def load(path) when is_binary(path) do
    key = cache_key(path)
    mtime = file_mtime(path)

    case :persistent_term.get(key, :not_found) do
      {^mtime, %__MODULE__{} = map} when not is_nil(mtime) ->
        map

      _ ->
        map = read_and_parse!(path)
        :persistent_term.put(key, {mtime, map})
        map
    end
  end

  @doc """
  Saves `data` (a `%MMGO.WorldMap{}` or a plain map with the same shape) to
  `path` as JSON, atomically (write to a temp file then rename) and refreshes
  the cache.

  Hexes are serialized as a list sorted by `{r, q}` for stable git diffs.
  """
  def save(%__MODULE__{} = map, path) when is_binary(path) do
    save(to_json_map(map), path)
  end

  def save(%{} = data, path) when is_binary(path) do
    json_map = normalize_for_save(data)
    contents = Jason.encode!(json_map, pretty: true)

    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, contents <> "\n"),
         :ok <- File.rename(tmp_path, path) do
      :persistent_term.erase(cache_key(path))
      {:ok, path}
    end
  end

  @doc "Looks up the hex at `{q, r}`, or `nil`."
  def hex_at(%__MODULE__{hexes: hexes}, {q, r}) do
    Map.get(hexes, {q, r})
  end

  @doc "Looks up the terrain id for the hex at `{q, r}`, or `nil` if the hex is absent."
  def terrain_at(%__MODULE__{} = map, {q, r}) do
    case hex_at(map, {q, r}) do
      %Hex{terrain: terrain} -> terrain
      nil -> nil
    end
  end

  @doc "Returns the `{q, r}` axial coordinate for a location slug, or `nil`."
  def hex_for_location(%__MODULE__{location_index: index}, slug) when is_binary(slug) do
    Map.get(index, slug)
  end

  @doc """
  Converts an axial `{q, r}` coordinate to pixel coordinates for a pointy-top
  hex grid, returning `%{x: x, y: y}`.
  """
  def pixel_for_hex(%__MODULE__{hex_size: size}, {q, r}) do
    x = size * :math.sqrt(3) * (q + r / 2)
    y = size * 1.5 * r
    %{x: x, y: y}
  end

  # -- internals --------------------------------------------------------

  defp cache_key(path), do: {@persistent_term_namespace, path}

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _reason} -> nil
    end
  end

  defp read_and_parse!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> from_json_map()
  end

  defp from_json_map(json) do
    hexes =
      json
      |> Map.get("hexes", [])
      |> Enum.into(%{}, fn hex_json ->
        hex = Hex.from_json(hex_json)
        {{hex.q, hex.r}, hex}
      end)

    location_index =
      hexes
      |> Enum.reduce(%{}, fn {coord, hex}, acc ->
        case hex.loc do
          nil -> acc
          slug -> Map.put(acc, slug, coord)
        end
      end)

    %__MODULE__{
      version: Map.get(json, "version", 1),
      realm: Map.get(json, "realm", "default"),
      orientation: Map.get(json, "orientation", "pointy"),
      hex_size: Map.get(json, "hex_size", 64),
      days_per_hex: Map.get(json, "days_per_hex", 0.5),
      terrains: Map.get(json, "terrains", %{}),
      hexes: hexes,
      location_index: location_index
    }
  end

  defp to_json_map(%__MODULE__{} = map) do
    %{
      "version" => map.version,
      "realm" => map.realm,
      "orientation" => map.orientation,
      "hex_size" => map.hex_size,
      "days_per_hex" => map.days_per_hex,
      "terrains" => map.terrains,
      "hexes" => map.hexes |> Map.values() |> Enum.map(&Hex.to_json/1)
    }
  end

  # Accepts either the internal (hexes: %{ {q,r} => %Hex{} }) shape or a plain
  # map already close to the JSON shape (hexes: [%{...}, ...] or list of Hex
  # structs), and returns a JSON-ready map with hexes sorted by {r, q}.
  defp normalize_for_save(%{} = data) do
    hexes =
      data
      |> Map.get(:hexes, Map.get(data, "hexes", []))
      |> normalize_hexes()
      |> Enum.sort_by(fn hex -> {hex["r"], hex["q"]} end)

    %{
      "version" => Map.get(data, :version, Map.get(data, "version", 1)),
      "realm" => Map.get(data, :realm, Map.get(data, "realm", "default")),
      "orientation" => Map.get(data, :orientation, Map.get(data, "orientation", "pointy")),
      "hex_size" => Map.get(data, :hex_size, Map.get(data, "hex_size", 64)),
      "days_per_hex" => Map.get(data, :days_per_hex, Map.get(data, "days_per_hex", 0.5)),
      "terrains" => Map.get(data, :terrains, Map.get(data, "terrains", %{})),
      "hexes" => hexes
    }
  end

  defp normalize_hexes(hexes) when is_map(hexes) do
    hexes |> Map.values() |> normalize_hexes()
  end

  defp normalize_hexes(hexes) when is_list(hexes) do
    Enum.map(hexes, fn
      %Hex{} = hex -> Hex.to_json(hex)
      %{} = hex -> Hex.from_json(hex) |> Hex.to_json()
    end)
  end
end
