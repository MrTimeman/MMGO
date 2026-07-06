defmodule MMGO.WorldMapTest do
  use ExUnit.Case, async: true

  alias MMGO.WorldMap

  @sample %{
    "version" => 1,
    "realm" => "default",
    "orientation" => "pointy",
    "hex_size" => 64,
    "days_per_hex" => 0.5,
    "terrains" => %{
      "water" => %{"color" => "#2c4a6e", "cost" => nil},
      "grass" => %{"color" => "#4a7c47", "cost" => 1.0}
    },
    "hexes" => [
      %{"q" => 0, "r" => 0, "t" => "grass", "loc" => "capital-city"},
      %{"q" => 1, "r" => 0, "t" => "water"},
      %{"q" => 0, "r" => 1, "t" => "grass", "road" => true, "s" => "grass_1"}
    ]
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "world_map_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "world.json")
    File.write!(path, Jason.encode!(@sample))

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, path: path}
  end

  test "load/1 parses hexes into a {q,r}-keyed map and builds a location index", %{path: path} do
    map = WorldMap.load(path)

    assert %WorldMap{} = map
    assert map.version == 1
    assert map.hex_size == 64
    assert map.days_per_hex == 0.5
    assert Map.has_key?(map.terrains, "water")

    assert WorldMap.hex_at(map, {0, 0}).terrain == "grass"
    assert WorldMap.hex_at(map, {0, 0}).loc == "capital-city"
    assert WorldMap.hex_at(map, {1, 0}).terrain == "water"
    assert WorldMap.hex_at(map, {5, 5}) == nil

    assert WorldMap.hex_for_location(map, "capital-city") == {0, 0}
    assert WorldMap.hex_for_location(map, "nowhere") == nil
  end

  test "terrain_at/2 returns terrain id or nil", %{path: path} do
    map = WorldMap.load(path)

    assert WorldMap.terrain_at(map, {1, 0}) == "water"
    assert WorldMap.terrain_at(map, {99, 99}) == nil
  end

  test "impassable terrain has cost: null preserved", %{path: path} do
    map = WorldMap.load(path)

    assert map.terrains["water"]["cost"] == nil
    assert map.terrains["grass"]["cost"] == 1.0
  end

  test "pixel_for_hex/2 converts axial to pixel using pointy-top math", %{path: path} do
    map = WorldMap.load(path)

    origin = WorldMap.pixel_for_hex(map, {0, 0})
    assert_in_delta origin.x, 0.0, 1.0e-9
    assert_in_delta origin.y, 0.0, 1.0e-9

    p = WorldMap.pixel_for_hex(map, {1, 0})
    assert_in_delta p.x, 64 * :math.sqrt(3), 1.0e-9
    assert_in_delta p.y, 0.0, 1.0e-9

    p2 = WorldMap.pixel_for_hex(map, {0, 1})
    assert_in_delta p2.x, 64 * :math.sqrt(3) / 2, 1.0e-9
    assert_in_delta p2.y, 96.0, 1.0e-9
  end

  test "load/1 caches by path and mtime, refreshing after save/2", %{path: path} do
    map1 = WorldMap.load(path)
    assert WorldMap.hex_at(map1, {2, 2}) == nil

    data = Jason.decode!(File.read!(path))
    updated = Map.put(data, "hexes", data["hexes"] ++ [%{"q" => 2, "r" => 2, "t" => "grass"}])

    # ensure mtime advances even on fast filesystems / coarse mtime resolution
    {:ok, ^path} = WorldMap.save(updated, path)
    File.touch!(path, System.os_time(:second) + 2)

    map2 = WorldMap.load(path)
    assert WorldMap.hex_at(map2, {2, 2}).terrain == "grass"
  end

  test "save/2 round-trips a struct back through load/1 with sorted hexes", %{path: path} do
    map = WorldMap.load(path)

    new_map = %WorldMap{
      map
      | hexes: Map.put(map.hexes, {3, -1}, %MMGO.WorldMap.Hex{q: 3, r: -1, terrain: "forest"})
    }

    {:ok, ^path} = WorldMap.save(new_map, path)

    raw = Jason.decode!(File.read!(path))
    rs = Enum.map(raw["hexes"], & &1["r"])
    assert rs == Enum.sort(rs)

    reloaded = WorldMap.load(path)
    assert WorldMap.hex_at(reloaded, {3, -1}).terrain == "forest"
    assert WorldMap.hex_at(reloaded, {0, 0}).loc == "capital-city"
  end

  test "save/2 writes atomically leaving no .tmp file behind", %{path: path} do
    map = WorldMap.load(path)
    {:ok, _path} = WorldMap.save(map, path)

    refute File.exists?(path <> ".tmp")
  end
end
