defmodule MMGO.WorldMap.PathTest do
  use ExUnit.Case, async: true

  alias MMGO.WorldMap
  alias MMGO.WorldMap.Path

  # A small hand-built map used across tests. Layout (q,r):
  #
  #   r=0:  (0,0)grass* (1,0)grass  (2,0)grass  (3,0)grass  (4,0)grass*
  #   r=1:  (0,1)grass  (1,1)road   (2,1)road   (3,1)road   (4,1)grass
  #
  # A separate disconnected pair models an unreachable island, and a lone
  # water hex models an impassable tile blocking a straight route.
  defp base_hexes do
    [
      %{"q" => 0, "r" => 0, "t" => "grass", "loc" => "start"},
      %{"q" => 1, "r" => 0, "t" => "grass"},
      %{"q" => 2, "r" => 0, "t" => "grass"},
      %{"q" => 3, "r" => 0, "t" => "grass"},
      %{"q" => 4, "r" => 0, "t" => "grass", "loc" => "end"},
      %{"q" => 0, "r" => 1, "t" => "mountain", "road" => true},
      %{"q" => 1, "r" => 1, "t" => "mountain", "road" => true},
      %{"q" => 2, "r" => 1, "t" => "mountain", "road" => true},
      %{"q" => 3, "r" => 1, "t" => "mountain", "road" => true},
      %{"q" => 4, "r" => 1, "t" => "mountain", "road" => true}
    ]
  end

  defp build_map(hexes, opts \\ []) do
    terrains =
      Keyword.get(opts, :terrains, %{
        "grass" => %{"cost" => 1.0},
        "mountain" => %{"cost" => 4.0},
        "water" => %{"cost" => nil}
      })

    location_index =
      hexes
      |> Enum.reduce(%{}, fn hex, acc ->
        case hex["loc"] do
          nil -> acc
          slug -> Map.put(acc, slug, {hex["q"], hex["r"]})
        end
      end)

    hex_structs =
      Enum.into(hexes, %{}, fn hex ->
        struct =
          %WorldMap.Hex{
            q: hex["q"],
            r: hex["r"],
            terrain: hex["t"],
            sprite: hex["s"],
            loc: hex["loc"],
            road: Map.get(hex, "road", false)
          }

        {{struct.q, struct.r}, struct}
      end)

    %WorldMap{
      version: 1,
      realm: "test",
      orientation: "pointy",
      hex_size: 64,
      days_per_hex: Keyword.get(opts, :days_per_hex, 0.5),
      terrains: terrains,
      hexes: hex_structs,
      location_index: location_index
    }
  end

  describe "a_star/3" do
    test "finds a straight path across uniform grass" do
      map =
        build_map([
          %{"q" => 0, "r" => 0, "t" => "grass"},
          %{"q" => 1, "r" => 0, "t" => "grass"},
          %{"q" => 2, "r" => 0, "t" => "grass"}
        ])

      assert {:ok, %{hexes: hexes, cost: cost}} = Path.a_star(map, {0, 0}, {2, 0})

      assert hexes == [{0, 0}, {1, 0}, {2, 0}]
      assert_in_delta cost, 2.0, 0.0001
    end

    test "returns a single-hex path with zero cost when from == to" do
      map = build_map(base_hexes())

      assert {:ok, %{hexes: [{0, 0}], cost: cost}} = Path.a_star(map, {0, 0}, {0, 0})
      assert cost == 0.0
    end

    test "prefers the road shortcut over a shorter all-grass path when it's cheaper" do
      # The bottom row is all "mountain" terrain (cost 4.0) but every hex has
      # road: true, so each step between two road hexes is discounted to
      # min(4.0, 1.0) * 0.4 = 0.4 instead of the full 4.0 terrain cost. Even
      # though mountain is nominally far more expensive than grass, the road
      # discount makes the full traverse (4 steps * 0.4 = 1.6) cheaper than
      # the equivalent all-grass row above it (4 steps * 1.0 = 4.0).
      map = build_map(base_hexes())

      assert {:ok, %{hexes: hexes, cost: cost}} = Path.a_star(map, {0, 1}, {4, 1})

      assert hexes == [{0, 1}, {1, 1}, {2, 1}, {3, 1}, {4, 1}]
      assert_in_delta cost, 4 * 0.4, 0.0001
    end

    test "does not take the road discount when hexes aren't both marked road" do
      map = build_map(base_hexes())

      {:ok, %{cost: grass_row_cost}} = Path.a_star(map, {0, 0}, {4, 0})
      assert_in_delta grass_row_cost, 4.0, 0.0001
    end

    test "water hexes block a straight path, forcing a detour or failure" do
      map =
        build_map([
          %{"q" => 0, "r" => 0, "t" => "grass"},
          %{"q" => 1, "r" => 0, "t" => "water"},
          %{"q" => 2, "r" => 0, "t" => "grass"}
        ])

      assert {:error, :unreachable} = Path.a_star(map, {0, 0}, {2, 0})
    end

    test "water hexes are bypassed via a detour when one is available" do
      map =
        build_map([
          %{"q" => 0, "r" => 0, "t" => "grass"},
          %{"q" => 1, "r" => 0, "t" => "water"},
          %{"q" => 2, "r" => 0, "t" => "grass"},
          %{"q" => 0, "r" => 1, "t" => "grass"},
          %{"q" => 1, "r" => 1, "t" => "grass"},
          %{"q" => 2, "r" => 1, "t" => "grass"}
        ])

      assert {:ok, %{hexes: hexes, cost: cost}} = Path.a_star(map, {0, 0}, {2, 0})
      refute {1, 0} in hexes
      assert List.first(hexes) == {0, 0}
      assert List.last(hexes) == {2, 0}
      assert cost > 2.0
    end

    test "an unreachable island returns {:error, :unreachable}" do
      map =
        build_map([
          %{"q" => 0, "r" => 0, "t" => "grass"},
          %{"q" => 10, "r" => 10, "t" => "grass"}
        ])

      assert {:error, :unreachable} = Path.a_star(map, {0, 0}, {10, 10})
    end

    test "a coordinate absent from the sparse map is {:error, :off_map}" do
      map = build_map(base_hexes())

      assert {:error, :off_map} = Path.a_star(map, {0, 0}, {99, 99})
      assert {:error, :off_map} = Path.a_star(map, {99, 99}, {0, 0})
    end

    test "an impassable (nil-cost terrain) endpoint is {:error, :off_map}" do
      map =
        build_map([
          %{"q" => 0, "r" => 0, "t" => "grass"},
          %{"q" => 1, "r" => 0, "t" => "water"}
        ])

      assert {:error, :off_map} = Path.a_star(map, {0, 0}, {1, 0})
    end
  end

  describe "path_between_locations/3" do
    test "resolves slugs through the location index and finds a path" do
      map = build_map(base_hexes())

      assert {:ok, %{hexes: hexes}} = Path.path_between_locations(map, "start", "end")
      assert List.first(hexes) == {0, 0}
      assert List.last(hexes) == {4, 0}
    end

    test "returns {:error, :off_map} for an unknown slug" do
      map = build_map(base_hexes())

      assert {:error, :off_map} = Path.path_between_locations(map, "start", "nowhere")
      assert {:error, :off_map} = Path.path_between_locations(map, "nowhere", "end")
    end
  end

  describe "travel_days/2" do
    test "rounds up to the nearest whole day" do
      map = build_map(base_hexes(), days_per_hex: 0.5)

      assert Path.travel_days(map, 2.0) == 1
      assert Path.travel_days(map, 2.1) == 2
      assert Path.travel_days(map, 4.0) == 2
    end

    test "always returns at least 1 day, even for a zero-cost path" do
      map = build_map(base_hexes(), days_per_hex: 0.5)

      assert Path.travel_days(map, 0.0) == 1
    end

    test "scales with days_per_hex" do
      map = build_map(base_hexes(), days_per_hex: 1.0)

      assert Path.travel_days(map, 3.0) == 3
      assert Path.travel_days(map, 3.1) == 4
    end
  end
end
