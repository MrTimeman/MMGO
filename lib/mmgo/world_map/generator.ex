defmodule MMGO.WorldMap.Generator do
  @moduledoc """
  Pure (DB-free) helpers for generating the starter hex world map.

  Kept separate from `Mix.Tasks.Mmgo.GenMap` so the terrain/road/placement
  logic is unit-testable without touching Postgres. The mix task is a thin
  wrapper that loads locations/routes from the DB and calls `generate/2`.
  """

  alias MMGO.WorldMap.Hex

  @default_width 64
  @default_height 48
  @border_ring 2

  @terrain_weights [
    {"grass", 45},
    {"forest", 25},
    {"hills", 12},
    {"sand", 8},
    {"swamp", 6},
    {"mountain", 4}
  ]

  @terrains %{
    "water" => %{"color" => "#2c4a6e", "cost" => nil},
    "grass" => %{"color" => "#4a7c47", "cost" => 1.0},
    "forest" => %{"color" => "#2f5d33", "cost" => 2.0},
    "hills" => %{"color" => "#8a7a4d", "cost" => 2.5},
    "mountain" => %{"color" => "#6e6259", "cost" => 4.0},
    "sand" => %{"color" => "#c2a76a", "cost" => 1.5},
    "swamp" => %{"color" => "#4d5d43", "cost" => 3.0}
  }

  @plane_size 2000

  @type location_input :: %{slug: String.t(), x: number(), y: number()}
  @type route_input :: %{a: String.t(), b: String.t()}

  @doc "Returns the built-in terrain definitions used by generated maps."
  def terrains, do: @terrains

  @doc """
  Generates a starter map struct-shape (plain map, ready for
  `MMGO.WorldMap.save/2`) sized `width` x `height` hexes (default 64x48).

  * a two-hex-thick water border ring
  * deterministic pseudo-terrain fill (phash2-based, no RNG seed)
  * every location in `locations` placed on the hex grid (proportionally
    scaled from the 2000x2000 plane) with its hex forced to passable grass
  * `road: true` hexes drawn along axial lines between locations connected
    by a route in `routes`

  `locations` is a list of `%{slug:, x:, y:}` (or maps with those keys).
  `routes` is a list of `%{a:, b:}` slug pairs (order doesn't matter).
  """
  def generate(locations, routes, opts \\ []) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)

    base_hexes = base_terrain_grid(width, height)

    location_coords = place_locations(locations, width, height)

    hexes_with_locations =
      Enum.reduce(location_coords, base_hexes, fn {slug, coord}, acc ->
        Map.update!(acc, coord, fn %Hex{} = hex -> %Hex{hex | terrain: "grass", loc: slug} end)
      end)

    hexes_with_roads = draw_roads(hexes_with_locations, routes, location_coords)

    %{
      "version" => 1,
      "realm" => "default",
      "orientation" => "pointy",
      "hex_size" => 64,
      "days_per_hex" => 0.5,
      "terrains" => @terrains,
      "hexes" => hexes_with_roads |> Map.values() |> Enum.map(&Hex.to_json/1)
    }
  end

  @doc """
  Builds the base terrain grid for a `width` x `height` axial rectangle,
  keyed by `{q, r}`: a water border ring `border` hexes thick, and
  deterministic pseudo-random terrain (weighted toward grass/forest)
  everywhere else. Reproducible across runs (uses `:erlang.phash2/1`, no
  random seed).
  """
  def base_terrain_grid(width, height, border \\ @border_ring) do
    for q <- 0..(width - 1), r <- 0..(height - 1), into: %{} do
      coord = {q, r}
      terrain = terrain_for(coord, width, height, border)
      {coord, %Hex{q: q, r: r, terrain: terrain}}
    end
  end

  @doc """
  Deterministically picks a terrain id for `{q, r}`. Cells within `border`
  hexes of the rectangle edge are water; everything else is picked by
  weighted hash of the coordinate so the result never varies between runs.
  """
  def terrain_for({q, r}, width, height, border \\ @border_ring) do
    if on_border?(q, r, width, height, border) do
      "water"
    else
      weighted_terrain_for({q, r})
    end
  end

  defp on_border?(q, r, width, height, border) do
    q < border or r < border or q >= width - border or r >= height - border
  end

  defp weighted_terrain_for(coord) do
    total = Enum.reduce(@terrain_weights, 0, fn {_terrain, w}, acc -> acc + w end)
    roll = :erlang.phash2(coord, total)
    pick_weighted(@terrain_weights, roll)
  end

  defp pick_weighted([{terrain, _weight}], _roll), do: terrain

  defp pick_weighted([{terrain, weight} | rest], roll) do
    if roll < weight do
      terrain
    else
      pick_weighted(rest, roll - weight)
    end
  end

  @doc """
  Maps each location's `{x, y}` (on the 2000x2000 plane) proportionally onto
  the `width` x `height` hex grid (leaving room inside the border ring),
  returning `%{slug => {q, r}}`.
  """
  def place_locations(locations, width, height, border \\ @border_ring) do
    usable_q = width - 2 * border - 1
    usable_r = height - 2 * border - 1

    locations
    |> Enum.map(fn loc ->
      slug = fetch(loc, :slug)
      x = fetch(loc, :x)
      y = fetch(loc, :y)

      q = border + round(x / @plane_size * usable_q)
      r = border + round(y / @plane_size * usable_r)

      q = clamp(q, border, width - border - 1)
      r = clamp(r, border, height - border - 1)

      {slug, {q, r}}
    end)
    |> Enum.into(%{})
  end

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  @doc """
  Draws `road: true` on hexes along an axial line between each pair of
  connected locations (using cube-coordinate lerp + rounding), returning the
  updated hex map. Endpoints are locations; `routes` is a list of `%{a:, b:}`
  slug pairs. Pairs referencing an unknown slug are skipped.
  """
  def draw_roads(hexes, routes, location_coords) do
    Enum.reduce(routes, hexes, fn route, acc ->
      a = fetch(route, :a)
      b = fetch(route, :b)

      with {:ok, from} <- Map.fetch(location_coords, a),
           {:ok, to} <- Map.fetch(location_coords, b) do
        line = axial_line(from, to)

        Enum.reduce(line, acc, fn coord, hex_acc ->
          Map.update(hex_acc, coord, nil, fn
            nil -> nil
            %Hex{} = hex -> %Hex{hex | road: true}
          end)
        end)
      else
        :error -> acc
      end
    end)
  end

  @doc "Axial line interpolation between two `{q, r}` points via cube lerp + rounding."
  def axial_line({q1, r1}, {q2, r2}) do
    distance = axial_distance({q1, r1}, {q2, r2})

    if distance == 0 do
      [{q1, r1}]
    else
      for step <- 0..distance do
        t = step / distance
        cube_round(lerp_cube(axial_to_cube({q1, r1}), axial_to_cube({q2, r2}), t))
      end
    end
  end

  defp axial_distance({q1, r1}, {q2, r2}) do
    {x1, y1, z1} = axial_to_cube({q1, r1})
    {x2, y2, z2} = axial_to_cube({q2, r2})
    div(abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2), 2)
  end

  defp axial_to_cube({q, r}) do
    x = q
    z = r
    y = -x - z
    {x, y, z}
  end

  defp lerp_cube({x1, y1, z1}, {x2, y2, z2}, t) do
    {
      x1 + (x2 - x1) * t,
      y1 + (y2 - y1) * t,
      z1 + (z2 - z1) * t
    }
  end

  defp cube_round({x, y, z}) do
    rx = round(x)
    ry = round(y)
    rz = round(z)

    x_diff = abs(rx - x)
    y_diff = abs(ry - y)
    z_diff = abs(rz - z)

    {rx, rz} =
      cond do
        x_diff > y_diff and x_diff > z_diff -> {-ry - rz, rz}
        y_diff > z_diff -> {rx, rz}
        true -> {rx, -rx - ry}
      end

    {rx, rz}
  end
end
