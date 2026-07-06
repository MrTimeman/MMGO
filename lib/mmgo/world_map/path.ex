defmodule MMGO.WorldMap.Path do
  @moduledoc """
  A* pathfinding over the hex-tile world map (`MMGO.WorldMap`).

  Movement cost to enter a hex is the terrain's cost (from `world_map.terrains`).
  When both the hex being left and the hex being entered have `road: true`, the
  step cost is discounted to `min(terrain_cost, 1.0) * 0.4`, modelling roads as
  a fast, flattening route regardless of the underlying terrain.

  Hexes that are absent from the sparse map, or whose terrain has a `nil` cost
  (impassable, e.g. water), cannot be traversed.
  """

  alias MMGO.WorldMap

  @type axial :: WorldMap.axial()

  @road_discount 0.4
  @road_cap 1.0

  @doc """
  Finds the lowest-cost path between two axial coordinates on `world_map`.

  Returns `{:ok, %{hexes: [axial(), ...], cost: float()}}` with `hexes` running
  from `from` to `to` inclusive (a single-element list when `from == to`), or
  `{:error, :off_map}` if either endpoint isn't a traversable hex on the map,
  or `{:error, :unreachable}` if no path exists between them.
  """
  @spec a_star(WorldMap.t(), axial(), axial()) ::
          {:ok, %{hexes: [axial()], cost: float()}} | {:error, :unreachable | :off_map}
  def a_star(%WorldMap{} = world_map, {_, _} = from, {_, _} = to) do
    cond do
      not traversable?(world_map, from) -> {:error, :off_map}
      not traversable?(world_map, to) -> {:error, :off_map}
      from == to -> {:ok, %{hexes: [from], cost: 0.0}}
      true -> run_a_star(world_map, from, to)
    end
  end

  @doc """
  Resolves `from_slug` and `to_slug` to axial coordinates via the map's
  location index, then finds the path between them. Returns `{:error,
  :off_map}` if either slug isn't present on the map.
  """
  @spec path_between_locations(WorldMap.t(), String.t(), String.t()) ::
          {:ok, %{hexes: [axial()], cost: float()}} | {:error, :unreachable | :off_map}
  def path_between_locations(%WorldMap{} = world_map, from_slug, to_slug)
      when is_binary(from_slug) and is_binary(to_slug) do
    with from when not is_nil(from) <- WorldMap.hex_for_location(world_map, from_slug),
         to when not is_nil(to) <- WorldMap.hex_for_location(world_map, to_slug) do
      a_star(world_map, from, to)
    else
      nil -> {:error, :off_map}
    end
  end

  @doc """
  Converts a path cost (in hexes) to a whole number of travel days, using the
  map's `days_per_hex`. Always rounds up and returns at least 1.
  """
  @spec travel_days(WorldMap.t(), number()) :: pos_integer()
  def travel_days(%WorldMap{days_per_hex: days_per_hex}, path_cost) when is_number(path_cost) do
    (path_cost * days_per_hex)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  # -- internals ----------------------------------------------------------

  defp run_a_star(world_map, from, to) do
    min_cost = min_terrain_cost(world_map)

    open_set = :gb_sets.singleton({heuristic(from, to, min_cost), from})
    g_score = %{from => 0.0}
    came_from = %{}

    do_a_star(world_map, to, min_cost, open_set, g_score, came_from, MapSet.new())
  end

  defp do_a_star(world_map, to, min_cost, open_set, g_score, came_from, closed) do
    if :gb_sets.is_empty(open_set) do
      {:error, :unreachable}
    else
      {{_priority, current}, open_set} = :gb_sets.take_smallest(open_set)

      cond do
        current == to ->
          {:ok,
           %{hexes: reconstruct_path(came_from, current), cost: Map.fetch!(g_score, current)}}

        MapSet.member?(closed, current) ->
          do_a_star(world_map, to, min_cost, open_set, g_score, came_from, closed)

        true ->
          closed = MapSet.put(closed, current)
          current_g = Map.fetch!(g_score, current)

          {open_set, g_score, came_from} =
            world_map
            |> neighbors(current)
            |> Enum.filter(&traversable?(world_map, &1))
            |> Enum.reject(&MapSet.member?(closed, &1))
            |> Enum.reduce({open_set, g_score, came_from}, fn neighbor,
                                                              {open_set, g_score, came_from} ->
              step_cost = step_cost(world_map, current, neighbor)
              tentative_g = current_g + step_cost

              if tentative_g < Map.get(g_score, neighbor, :infinity) do
                priority = tentative_g + heuristic(neighbor, to, min_cost)

                {
                  :gb_sets.add({priority, neighbor}, open_set),
                  Map.put(g_score, neighbor, tentative_g),
                  Map.put(came_from, neighbor, current)
                }
              else
                {open_set, g_score, came_from}
              end
            end)

          do_a_star(world_map, to, min_cost, open_set, g_score, came_from, closed)
      end
    end
  end

  defp reconstruct_path(came_from, node) do
    case Map.fetch(came_from, node) do
      {:ok, previous} -> reconstruct_path(came_from, previous) ++ [node]
      :error -> [node]
    end
  end

  @directions [{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1}]

  defp neighbors(_world_map, {q, r}) do
    Enum.map(@directions, fn {dq, dr} -> {q + dq, r + dr} end)
  end

  defp traversable?(world_map, coord) do
    case WorldMap.hex_at(world_map, coord) do
      nil -> false
      hex -> terrain_cost(world_map, hex.terrain) != nil
    end
  end

  defp step_cost(world_map, from_coord, to_coord) do
    from_hex = WorldMap.hex_at(world_map, from_coord)
    to_hex = WorldMap.hex_at(world_map, to_coord)
    terrain_cost = terrain_cost(world_map, to_hex.terrain)

    if from_hex.road and to_hex.road do
      min(terrain_cost, @road_cap) * @road_discount
    else
      terrain_cost
    end
  end

  defp terrain_cost(%WorldMap{terrains: terrains}, terrain_id) do
    case Map.get(terrains, terrain_id) do
      %{"cost" => cost} -> cost
      %{cost: cost} -> cost
      _ -> nil
    end
  end

  defp heuristic({q1, r1}, {q2, r2}, min_cost) do
    dq = q2 - q1
    dr = r2 - r1
    hex_distance = (abs(dq) + abs(dr) + abs(dq + dr)) / 2
    hex_distance * min_cost * @road_discount
  end

  defp min_terrain_cost(%WorldMap{terrains: terrains}) do
    terrains
    |> Map.values()
    |> Enum.map(fn
      %{"cost" => cost} -> cost
      %{cost: cost} -> cost
      _ -> nil
    end)
    |> Enum.filter(&is_number/1)
    |> case do
      [] -> 1.0
      costs -> Enum.min(costs)
    end
  end
end
