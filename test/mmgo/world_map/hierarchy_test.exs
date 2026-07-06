defmodule MMGO.WorldMap.HierarchyTest do
  use ExUnit.Case, async: true

  alias MMGO.WorldMap.Hierarchy

  @range -40..40

  @axial_directions [
    {1, 0},
    {1, -1},
    {0, -1},
    {-1, 0},
    {-1, 1},
    {0, 1}
  ]

  defp hex_distance({q1, r1}, {q2, r2}) do
    dq = q1 - q2
    dr = r1 - r2
    (abs(dq) + abs(dr) + abs(dq + dr)) / 2
  end

  defp expected_children(center) do
    {cq, cr} = center
    neighbors = Enum.map(@axial_directions, fn {dq, dr} -> {cq + dq, cr + dr} end)
    MapSet.new([center | neighbors])
  end

  defp fine_region do
    for q <- @range, r <- @range, do: {q, r}
  end

  # -- level 1: fine -> level-1 -------------------------------------------

  describe "parent/1 (fine -> level-1)" do
    test "every fine hex in the region has a parent whose center is within hex distance 1" do
      for hex <- fine_region() do
        {i, j} = Hierarchy.parent(hex)
        center = Hierarchy.center_l1({i, j})
        distance = hex_distance(hex, center)

        assert distance <= 1,
               "expected #{inspect(hex)} to be within 1 of parent center #{inspect(center)} " <>
                 "(index #{inspect({i, j})}), got distance #{distance}"
      end
    end

    test "children_l1(parent(h)) always contains h" do
      for hex <- fine_region() do
        parent_index = Hierarchy.parent(hex)
        children = Hierarchy.children_l1(parent_index)

        assert hex in children,
               "expected #{inspect(hex)} to be among children of #{inspect(parent_index)}: #{inspect(children)}"
      end
    end

    test "children of a level-1 parent are exactly {center} union neighbors(center)" do
      centers_checked =
        for q <- -20..20, r <- -20..20, uniq: true do
          Hierarchy.parent({q, r})
        end
        |> Enum.uniq()

      for parent_index <- centers_checked do
        center = Hierarchy.center_l1(parent_index)
        children = MapSet.new(Hierarchy.children_l1(parent_index))
        assert children == expected_children(center)
      end
    end

    test "children sets of distinct level-1 parents are disjoint and cover the interior region" do
      # Restrict to an interior sub-region so boundary parents (whose full
      # 7-hex flower may spill outside @range) don't produce false failures.
      interior = for q <- -25..25, r <- -25..25, do: {q, r}

      parent_of =
        for hex <- interior, into: %{} do
          {hex, Hierarchy.parent(hex)}
        end

      grouped = Enum.group_by(interior, &parent_of[&1])

      for {parent_index, hexes} <- grouped do
        center = Hierarchy.center_l1(parent_index)
        actual = MapSet.new(hexes)
        expected = expected_children(center)

        # Only assert full equality when the parent's entire flower lies
        # inside the interior region (otherwise it's legitimately partial).
        if MapSet.subset?(expected, MapSet.new(interior)) do
          assert actual == expected,
                 "partition violated for parent #{inspect(parent_index)}: " <>
                   "got #{inspect(Enum.sort(hexes))}, expected #{inspect(Enum.sort(MapSet.to_list(expected)))}"
        end
      end

      # Coverage: every interior hex must appear in exactly one parent group,
      # i.e. the map covers all of `interior` and groups partition it.
      all_hexes_in_groups = grouped |> Map.values() |> List.flatten() |> MapSet.new()
      assert all_hexes_in_groups == MapSet.new(interior)
    end

    test "round-trip: center_l1({i, j}) |> parent() == {i, j}" do
      for i <- -10..10, j <- -10..10 do
        index = {i, j}
        center = Hierarchy.center_l1(index)
        assert Hierarchy.parent(center) == index
      end
    end
  end

  # -- level 0: level-1 -> level-0 ------------------------------------------

  describe "parent_l0/1 (level-1 -> level-0)" do
    test "every level-1 index in range has a level-0 parent within hex distance 1 (in index space)" do
      for i <- -20..20, j <- -20..20 do
        index = {i, j}
        {m, n} = Hierarchy.parent_l0(index)
        center = MMGO.WorldMap.Hierarchy |> apply_lattice_center({m, n})
        distance = hex_distance(index, center)

        assert distance <= 1,
               "expected #{inspect(index)} within 1 of l0 parent center #{inspect(center)}, got #{distance}"
      end
    end

    test "children_l0(parent_l0(idx)) always contains idx" do
      for i <- -20..20, j <- -20..20 do
        index = {i, j}
        l0_index = Hierarchy.parent_l0(index)
        children = Hierarchy.children_l0(l0_index)

        assert index in children,
               "expected #{inspect(index)} among children_l0 of #{inspect(l0_index)}: #{inspect(children)}"
      end
    end

    test "children of a level-0 parent are exactly {center} union neighbors(center), in index space" do
      centers_checked =
        for i <- -12..12, j <- -12..12, uniq: true do
          Hierarchy.parent_l0({i, j})
        end
        |> Enum.uniq()

      for l0_index <- centers_checked do
        center = apply_lattice_center(nil, l0_index)
        children = MapSet.new(Hierarchy.children_l0(l0_index))
        assert children == expected_children(center)
      end
    end

    test "descendants_l0 has exactly 49 distinct fine hexes, all with ancestors.l0 matching" do
      for m <- -3..3, n <- -3..3 do
        l0_index = {m, n}
        descendants = Hierarchy.descendants_l0(l0_index)

        assert length(descendants) == 49
        assert length(Enum.uniq(descendants)) == 49

        for hex <- descendants do
          assert Hierarchy.ancestors(hex).l0 == l0_index,
                 "expected #{inspect(hex)}'s l0 ancestor to be #{inspect(l0_index)}, " <>
                   "got #{inspect(Hierarchy.ancestors(hex).l0)}"
        end
      end
    end
  end

  # -- geometry ---------------------------------------------------------------

  describe "outline geometry" do
    test "outline_l1 corners sit at distance sqrt(7)*hex_size from the parent center" do
      hex_size = 64
      expected_radius = :math.sqrt(7) * hex_size

      for index <- [{0, 0}, {1, 0}, {-2, 3}, {5, -1}] do
        {cx, cy} = pixel_center_l1(index, hex_size)
        corners = Hierarchy.outline_l1(index, hex_size)

        assert length(corners) == 6

        for {x, y} <- corners do
          d = :math.sqrt(:math.pow(x - cx, 2) + :math.pow(y - cy, 2))
          assert_in_delta d, expected_radius, 1.0e-6
        end
      end
    end

    test "outline_l0 corners sit at distance 7*hex_size from the parent center" do
      hex_size = 64
      expected_radius = 7.0 * hex_size

      for index <- [{0, 0}, {1, 0}, {-2, 1}] do
        {cx, cy} = pixel_center_l0(index, hex_size)
        corners = Hierarchy.outline_l0(index, hex_size)

        assert length(corners) == 6

        for {x, y} <- corners do
          d = :math.sqrt(:math.pow(x - cx, 2) + :math.pow(y - cy, 2))
          assert_in_delta d, expected_radius, 1.0e-6
        end
      end
    end

    test "rotation_l1/0 matches the derived aperture-7 angle atan2(1.5, 2.5*sqrt(3))" do
      expected = :math.atan2(1.5, 2.5 * :math.sqrt(3))
      assert_in_delta Hierarchy.rotation_l1(), expected, 1.0e-6
      assert_in_delta Hierarchy.rotation_l1(), 0.3334731722518321, 1.0e-6
    end

    test "rotation_l0/0 is exactly double rotation_l1/0" do
      assert_in_delta Hierarchy.rotation_l0(), 2 * Hierarchy.rotation_l1(), 1.0e-9
    end

    test "scale_l1/0 is sqrt(7) and scale_l0/0 is 7.0" do
      assert_in_delta Hierarchy.scale_l1(), :math.sqrt(7), 1.0e-9
      assert_in_delta Hierarchy.scale_l0(), 7.0, 1.0e-9
    end
  end

  describe "ancestors/1" do
    test "returns both l1 and l0 parent indices consistently" do
      for hex <- [{0, 0}, {3, -2}, {-15, 8}, {22, 22}] do
        result = Hierarchy.ancestors(hex)
        assert result.l1 == Hierarchy.parent(hex)
        assert result.l0 == Hierarchy.parent_l0(result.l1)
      end
    end
  end

  # -- helpers mirroring the private lattice math, for assertions only ------

  defp apply_lattice_center(_mod, {i, j}) do
    # A = (2, 1), B = (-1, 3) — mirrors Hierarchy's private lattice_center/1,
    # used here only to independently compute expected centers for assertions.
    {2 * i - j, i + 3 * j}
  end

  defp pixel_center_l1(index, hex_size) do
    {q, r} = Hierarchy.center_l1(index)
    {hex_size * :math.sqrt(3) * (q + r / 2), hex_size * 1.5 * r}
  end

  defp pixel_center_l0(index, hex_size) do
    {q, r} = Hierarchy.center_l0(index)
    {hex_size * :math.sqrt(3) * (q + r / 2), hex_size * 1.5 * r}
  end
end
