defmodule Mix.Tasks.Mmgo.GenMap do
  use Mix.Task

  alias MMGO.Play
  alias MMGO.WorldMap
  alias MMGO.WorldMap.Generator
  alias MMGO.Worlds

  @shortdoc "Generates the starter hex world map from seeded locations/routes"

  @moduledoc """
  Generates a ~64x48 hex map for the default realm and writes it to
  `priv/static/maps/world.json` (via `MMGO.WorldMap.save/2`, using the
  configured `:world_map_path`).

  Reads locations and routes from the database, so run this against a
  seeded dev database:

      docker compose up -d
      mix ecto.setup   # if the DB is empty
      mix mmgo.gen_map

  All terrain/road generation logic is pure and lives in
  `MMGO.WorldMap.Generator`; this task only loads DB data and writes the
  result to disk.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    realm = Worlds.get_default_realm!()
    locations = Play.list_locations_with_routes(realm.id)

    location_inputs =
      Enum.map(locations, fn loc -> %{slug: loc.slug, x: loc.x, y: loc.y} end)

    route_inputs = route_pairs(locations)

    map_data = Generator.generate(location_inputs, route_inputs)

    case WorldMap.save(map_data, WorldMap.default_path()) do
      {:ok, path} ->
        Mix.shell().info(
          "Wrote hex world map to #{path} (#{length(map_data["hexes"])} hexes, " <>
            "#{length(location_inputs)} locations placed)"
        )

      {:error, reason} ->
        Mix.raise("Could not write world map: #{inspect(reason)}")
    end
  end

  # Builds slug-pair edges from each location's preloaded `:routes`
  # (as returned by `MMGO.Play.list_locations_with_routes/1`), deduplicated
  # since bidirectional routes appear on both endpoints.
  defp route_pairs(locations) do
    locations
    |> Enum.flat_map(fn loc ->
      Enum.map(loc.routes || [], fn route ->
        pair = Enum.sort([route.origin_location_id, route.destination_location_id])
        {pair, route}
      end)
    end)
    |> Enum.uniq_by(fn {pair, _route} -> pair end)
    |> Enum.map(fn {_pair, route} -> route end)
    |> Enum.map(fn route ->
      %{
        a: slug_for(locations, route.origin_location_id),
        b: slug_for(locations, route.destination_location_id)
      }
    end)
    |> Enum.reject(fn %{a: a, b: b} -> is_nil(a) or is_nil(b) end)
  end

  defp slug_for(locations, location_id) do
    case Enum.find(locations, fn loc -> loc.id == location_id end) do
      nil -> nil
      loc -> loc.slug
    end
  end
end
