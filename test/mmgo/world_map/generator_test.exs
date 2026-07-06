defmodule MMGO.WorldMap.GeneratorTest do
  use ExUnit.Case, async: true

  alias MMGO.WorldMap.Generator
  alias MMGO.WorldMap.Hex

  describe "base_terrain_grid/2" do
    test "borders the rectangle with water and fills the interior with weighted terrain" do
      grid = Generator.base_terrain_grid(20, 16)

      assert map_size(grid) == 20 * 16

      assert grid[{0, 0}].terrain == "water"
      assert grid[{0, 8}].terrain == "water"
      assert grid[{19, 8}].terrain == "water"
      assert grid[{10, 0}].terrain == "water"
      assert grid[{10, 15}].terrain == "water"

      interior_terrains =
        for q <- 3..16, r <- 3..12, into: MapSet.new(), do: grid[{q, r}].terrain

      assert MapSet.member?(interior_terrains, "grass") or
               MapSet.member?(interior_terrains, "forest")

      refute MapSet.member?(interior_terrains, "water")
    end

    test "is deterministic across calls (no RNG seed dependence)" do
      grid1 = Generator.base_terrain_grid(20, 16)
      grid2 = Generator.base_terrain_grid(20, 16)

      assert grid1 == grid2
    end
  end

  describe "terrain_for/4" do
    test "picks the same terrain for the same coordinate every time" do
      results = for _ <- 1..5, do: Generator.terrain_for({7, 9}, 20, 16)
      assert Enum.uniq(results) == [hd(results)]
    end
  end

  describe "place_locations/4" do
    test "maps 2000x2000-plane coordinates onto the hex grid proportionally, within bounds" do
      locations = [
        %{slug: "top-left", x: 0, y: 0},
        %{slug: "center", x: 1000, y: 1000},
        %{slug: "bottom-right", x: 2000, y: 2000}
      ]

      placed = Generator.place_locations(locations, 64, 48)

      assert map_size(placed) == 3

      for {_slug, {q, r}} <- placed do
        assert q >= 2 and q <= 61
        assert r >= 2 and r <= 45
      end

      {tl_q, tl_r} = placed["top-left"]
      {br_q, br_r} = placed["bottom-right"]
      assert tl_q < br_q
      assert tl_r < br_r
    end
  end

  describe "axial_line/2" do
    test "returns just the point itself when start == end" do
      assert Generator.axial_line({3, 3}, {3, 3}) == [{3, 3}]
    end

    test "produces a contiguous path between two axial points" do
      line = Generator.axial_line({0, 0}, {4, 0})

      assert List.first(line) == {0, 0}
      assert List.last(line) == {4, 0}
      assert length(line) == 5
      assert line == Enum.map(0..4, &{&1, 0})
    end

    test "handles diagonal-ish lines without gaps (consecutive hexes are neighbors)" do
      line = Generator.axial_line({0, 0}, {5, 3})

      pairs = Enum.zip(line, tl(line))

      for {{q1, r1}, {q2, r2}} <- pairs do
        dq = q2 - q1
        dr = r2 - r1
        # every step must move to an adjacent hex (axial distance of 1)
        assert abs(dq) <= 1 and abs(dr) <= 1 and {dq, dr} != {0, 0}
      end
    end
  end

  describe "draw_roads/3" do
    test "marks road: true on hexes along the line between routed locations" do
      hexes = Generator.base_terrain_grid(10, 10)
      location_coords = %{"a" => {1, 1}, "b" => {5, 1}}
      routes = [%{a: "a", b: "b"}]

      result = Generator.draw_roads(hexes, routes, location_coords)

      for q <- 1..5 do
        assert result[{q, 1}].road == true
      end

      # unrelated hex untouched
      refute result[{1, 5}].road
    end

    test "skips routes referencing unknown slugs" do
      hexes = Generator.base_terrain_grid(10, 10)
      location_coords = %{"a" => {1, 1}}
      routes = [%{a: "a", b: "missing"}]

      result = Generator.draw_roads(hexes, routes, location_coords)

      refute Enum.any?(result, fn {_coord, %Hex{road: road}} -> road end)
    end
  end

  describe "generate/3" do
    test "produces a JSON-ready map with locations placed and passable, plus roads" do
      locations = [
        %{slug: "capital-city", x: 960, y: 1040},
        %{slug: "the-tower", x: 830, y: 385}
      ]

      routes = [%{a: "capital-city", b: "the-tower"}]

      data = Generator.generate(locations, routes, width: 20, height: 16)

      assert data["version"] == 1
      assert data["hex_size"] == 64
      assert is_map(data["terrains"])
      assert data["terrains"]["water"]["cost"] == nil

      hexes_by_loc =
        for hex <- data["hexes"], hex["loc"], into: %{}, do: {hex["loc"], hex}

      assert map_size(hexes_by_loc) == 2
      assert hexes_by_loc["capital-city"]["t"] == "grass"
      assert hexes_by_loc["the-tower"]["t"] == "grass"

      assert Enum.any?(data["hexes"], fn hex -> hex["road"] end)
    end
  end
end
